import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreAudio
import Accelerate

// FFmpeg 软解播放器后端：解复用 + 解码 → CMSampleBuffer → AVSampleBufferRenderSynchronizer 音视频同步渲染
final class FFmpegPlayer {

    // MARK: 常量（FFmpeg 宏在 Swift 中不可用，此处手动定义）

    private static let avTimeBaseQ = AVRational(num: 1, den: Int32(1_000_000))  // AV_TIME_BASE_Q
    private static let avSeekFlagBackward: Int32 = 1                            // AVSEEK_FLAG_BACKWARD
    private static let swsBilinear: Int32 = 2                                   // SWS_BILINEAR
    private static let avNumDataPointers = 8                                    // AV_NUM_DATA_POINTERS
    private static let swsCS_ITU709: Int32 = 1
    private static let swsCS_ITU601: Int32 = 5
    private static let swsCS_BT2020: Int32 = 9
    /// 超过该大小的文件，内嵌字幕改为后台独立线程提取，避免起播前读完整个文件
    private static let subtitleSyncPreloadLimit: Int64 = 1_500_000_000

    // MARK: FFmpeg 状态

    private var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
    private var videoCodecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var audioCodecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var swsCtx: UnsafeMutablePointer<SwsContext>?
    private var swrCtx: OpaquePointer?
    private var swsSrcFormat: Int32 = -1
    private var hwDeviceCtx: UnsafeMutablePointer<AVBufferRef>?
    private var videoStreamIdx = -1
    private var audioStreamIdx = -1
    private var videoTimeBase = AVRational(num: 1, den: 1)
    private var audioTimeBase = AVRational(num: 1, den: 1)
    private var videoFrameDuration = CMTime(value: 1, timescale: 30)

    // MARK: 渲染

    let videoLayer = AVSampleBufferDisplayLayer()
    let audioRenderer = AVSampleBufferAudioRenderer()
    let synchronizer = AVSampleBufferRenderSynchronizer()

    private(set) var videoSize = CGSize.zero
    private(set) var duration: Double = 0

    /// 内嵌文本字幕流（index / 语言）
    private(set) var subtitleStreams: [(index: Int, language: String)] = []
    /// 音轨列表（index / 语言）
    private(set) var audioStreams: [(index: Int, language: String)] = []
    /// 章节列表
    private(set) var chapters: [(start: Double, end: Double, title: String)] = []
    /// 媒体信息（⌘I 展示）
    private(set) var mediaInfoLines: [String] = []

    /// 当前打开的资源标识（文件路径或流 URL），用于识别异步字幕结果是否已过期
    private(set) var openedURLString: String = ""

    // MARK: 跨线程状态（锁保护）

    private let lock = NSLock()
    private var _stopped = true
    private var _paused = false
    private var _eof = false
    private var _playbackRate: Double = 1.0
    private var _audioDelay: Double = 0
    private var _rotation: Int = 0
    private var _pendingSeekSeconds: Double?
    private var _pendingAudioIndex: Int?
    private var _embeddedSubtitles: [Int: [SubtitleCue]] = [:]
    private var _lastPixelBuffer: CVPixelBuffer?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var stopped: Bool { locked { _stopped } }
    private func setStopped(_ v: Bool) { locked { _stopped = v } }

    private var paused: Bool { locked { _paused } }
    private func setPaused(_ v: Bool) { locked { _paused = v } }

    private var eof: Bool { locked { _eof } }
    private func setEof(_ v: Bool) { locked { _eof = v } }

    private var playbackRate: Double { locked { _playbackRate } }
    private func setPlaybackRate(_ v: Double) { locked { _playbackRate = v } }

    var audioDelay: Double {
        get { locked { _audioDelay } }
        set { locked { _audioDelay = max(-10, min(10, newValue)) } }
    }

    var rotation: Int { locked { _rotation } }
    private func setRotation(_ v: Int) { locked { _rotation = v } }

    private func takePendingSeek() -> Double? { locked { defer { _pendingSeekSeconds = nil }; return _pendingSeekSeconds } }
    private func setPendingSeek(_ s: Double?) { locked { _pendingSeekSeconds = s } }

    private func takePendingAudioIndex() -> Int? { locked { defer { _pendingAudioIndex = nil }; return _pendingAudioIndex } }
    private func setPendingAudioIndex(_ i: Int?) { locked { _pendingAudioIndex = i } }

    func embeddedCues(for index: Int) -> [SubtitleCue] { locked { _embeddedSubtitles[index] ?? [] } }
    private func setEmbeddedSubtitles(_ dict: [Int: [SubtitleCue]]) { locked { _embeddedSubtitles = dict } }

    /// 最近一帧画面（BGRA，供截图使用）
    var lastPixelBuffer: CVPixelBuffer? { locked { _lastPixelBuffer } }
    private func setLastPixelBuffer(_ pb: CVPixelBuffer?) { locked { _lastPixelBuffer = pb } }

    // MARK: 播放线程状态

    private var playThread: Thread?
    private var lastEnqueuedSeconds: Double = 0
    private var bufferedSeconds: Double = 0
    private var syncSubtitlePreload = false
    private var pixelPool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    // 回调
    var onPlaybackEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    var onReady: ((CGSize) -> Void)?
    var onSubtitlesReady: (() -> Void)?
    var onRotation: ((Int) -> Void)?

    var currentTime: Double {
        return synchronizer.currentTime().seconds
    }

    var currentAudioIndex: Int { locked { audioStreamIdx } }

    // MARK: - 打开

    func open(url: URL) {
        cleanup()
        setStopped(false)
        setPaused(false)
        setEof(false)
        setPlaybackRate(1.0)
        audioDelay = 0
        setRotation(0)
        lastEnqueuedSeconds = 0
        bufferedSeconds = 0

        let urlString = url.isFileURL ? url.path : url.absoluteString
        openedURLString = urlString
        guard let cPath = urlString.cString(using: .utf8) else {
            fail("无效的文件路径")
            return
        }
        guard avformat_open_input(&fmtCtx, cPath, nil, nil) == 0, let fmt = fmtCtx else {
            fail("无法打开文件：\(url.lastPathComponent)")
            return
        }
        guard avformat_find_stream_info(fmt, nil) >= 0 else {
            fail("无法解析流信息")
            return
        }

        if fmt.pointee.duration != Int64.min {  // AV_NOPTS_VALUE
            duration = Double(fmt.pointee.duration) / 1_000_000.0  // AV_TIME_BASE
        }

        let nbStreams = Int(fmt.pointee.nb_streams)
        for i in 0..<nbStreams {
            guard let st = fmt.pointee.streams[i], let par = st.pointee.codecpar else { continue }
            let type = par.pointee.codec_type
            if type == AVMEDIA_TYPE_VIDEO && videoStreamIdx < 0 {
                if openVideoDecoder(stream: st) {
                    videoStreamIdx = i
                    videoTimeBase = st.pointee.time_base
                    let w = Int(par.pointee.width)
                    let h = Int(par.pointee.height)
                    videoSize = CGSize(width: w, height: h)
                    if let fps = fpsFrom(st) {
                        videoFrameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
                    }
                }
            } else if type == AVMEDIA_TYPE_AUDIO {
                audioStreams.append((index: i, language: languageOf(st)))
                if audioStreamIdx < 0, openAudioDecoder(stream: st) {
                    audioStreamIdx = i
                    audioTimeBase = st.pointee.time_base
                }
            } else if type == AVMEDIA_TYPE_SUBTITLE {
                if Self.isTextSubtitle(par.pointee.codec_id) {
                    subtitleStreams.append((index: i, language: languageOf(st)))
                }
            }
        }

        guard videoStreamIdx >= 0 || audioStreamIdx >= 0 else {
            fail("未找到可解码的音视频流")
            return
        }

        chapters = readChapters(fmt)
        mediaInfoLines = buildMediaInfo(fmt: fmt)

        // 配置渲染层
        videoLayer.videoGravity = .resizeAspect
        if videoStreamIdx >= 0 { synchronizer.addRenderer(videoLayer) }
        if audioStreamIdx >= 0 { synchronizer.addRenderer(audioRenderer) }

        // 内嵌字幕：小文件起播前同步提取；大文件/网络流后台独立线程提取，不阻塞首帧
        if !subtitleStreams.isEmpty {
            let fileSize: Int64
            if url.isFileURL, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            } else {
                fileSize = 0
            }
            if fileSize > 0 && fileSize < Self.subtitleSyncPreloadLimit {
                syncSubtitlePreload = true
            } else {
                syncSubtitlePreload = false
                startAsyncSubtitleExtraction(urlString: urlString, targets: subtitleStreams)
            }
        } else {
            syncSubtitlePreload = false
        }

        onReady?(videoSize)
        startThread()
    }

    private func fpsFrom(_ st: UnsafeMutablePointer<AVStream>) -> Int32? {
        let r = st.pointee.avg_frame_rate
        guard r.num > 0, r.den > 0 else { return nil }
        let fps = Int32(round(Double(r.num) / Double(r.den)))
        return fps > 0 ? fps : nil
    }

    private func readChapters(_ fmt: UnsafeMutablePointer<AVFormatContext>) -> [(start: Double, end: Double, title: String)] {
        var result: [(start: Double, end: Double, title: String)] = []
        let n = Int(fmt.pointee.nb_chapters)
        for i in 0..<n {
            guard let ch = fmt.pointee.chapters[i] else { continue }
            let tb = ch.pointee.time_base
            let scale = Double(tb.num) / Double(max(tb.den, 1))
            let start = Double(ch.pointee.start) * scale
            let end = Double(ch.pointee.end) * scale
            // FFmpeg 7+ 移除了 AVChapter.title，标题从 metadata 读取
            let title: String
            if let md = ch.pointee.metadata,
               let entry = av_dict_get(md, "title", nil, 0),
               let value = entry.pointee.value {
                title = String(cString: value)
            } else {
                title = "章节 \(i + 1)"
            }
            result.append((start, end, title))
        }
        return result
    }

    private func codecName(_ id: AVCodecID) -> String {
        if let desc = avcodec_descriptor_get(id), let name = desc.pointee.name {
            return String(cString: name)
        }
        return "未知"
    }

    private func buildMediaInfo(fmt: UnsafeMutablePointer<AVFormatContext>) -> [String] {
        var lines: [String] = []
        if let name = fmt.pointee.iformat?.pointee.name {
            lines.append("容器格式：\(String(cString: name))")
        }
        if duration > 0 {
            let t = Int(duration)
            lines.append(String(format: "时长：%02d:%02d:%02d（%.1f 秒）", t / 3600, (t % 3600) / 60, t % 60, duration))
        }
        if fmt.pointee.bit_rate > 0 {
            lines.append(String(format: "总码率：%.2f Mbps", Double(fmt.pointee.bit_rate) / 1_000_000))
        }
        if !chapters.isEmpty {
            lines.append("章节：\(chapters.count) 个")
        }
        for i in 0..<Int(fmt.pointee.nb_streams) {
            guard let st = fmt.pointee.streams[i], let par = st.pointee.codecpar else { continue }
            let codec = codecName(par.pointee.codec_id)
            let lang = languageOf(st)
            let langSuffix = lang.isEmpty ? "" : "（\(lang)）"
            switch par.pointee.codec_type {
            case AVMEDIA_TYPE_VIDEO:
                let w = Int(par.pointee.width), h = Int(par.pointee.height)
                let fps = fpsFrom(st).map { String(format: "%.2f", Double($0)) } ?? "未知"
                var bit = ""
                if par.pointee.bit_rate > 0 {
                    bit = String(format: "，%.2f Mbps", Double(par.pointee.bit_rate) / 1_000_000)
                }
                lines.append("视频 #\(i)：\(codec)，\(w)×\(h)，\(fps) fps\(bit)")
            case AVMEDIA_TYPE_AUDIO:
                let sr = Int(par.pointee.sample_rate)
                let ch = Int(par.pointee.ch_layout.nb_channels)
                var bit = ""
                if par.pointee.bit_rate > 0 {
                    bit = String(format: "，%.0f kbps", Double(par.pointee.bit_rate) / 1000)
                }
                lines.append("音频 #\(i)：\(codec)\(langSuffix)，\(sr) Hz，\(ch) 声道\(bit)")
            case AVMEDIA_TYPE_SUBTITLE:
                lines.append("字幕 #\(i)：\(codec)\(langSuffix)")
            default:
                break
            }
        }
        return lines
    }

    private func openVideoDecoder(stream st: UnsafeMutablePointer<AVStream>) -> Bool {
        guard let codecPar = st.pointee.codecpar else { return false }
        guard let decoder = avcodec_find_decoder(codecPar.pointee.codec_id) else { return false }

        videoCodecCtx = avcodec_alloc_context3(decoder)
        guard let vc = videoCodecCtx else { return false }
        guard avcodec_parameters_to_context(vc, codecPar) >= 0 else { return false }

        // 优先挂载 VideoToolbox 硬件加速（GPU 解码，帧再回传内存）
        if Settings.shared.ffmpegHardwareDecode {
            var hw: UnsafeMutablePointer<AVBufferRef>?
            if av_hwdevice_ctx_create(&hw, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0) == 0, hw != nil {
                vc.pointee.hw_device_ctx = av_buffer_ref(hw)
                hwDeviceCtx = vc.pointee.hw_device_ctx
                NSLog("[FFmpeg] 已挂载 VideoToolbox 硬件加速")
                av_buffer_unref(&hw)
            }
        }

        guard avcodec_open2(vc, decoder, nil) >= 0 else {
            // 硬解挂载导致打开失败则去掉硬解重试
            if vc.pointee.hw_device_ctx != nil {
                av_buffer_unref(&vc.pointee.hw_device_ctx)
                hwDeviceCtx = nil
                if avcodec_open2(vc, decoder, nil) >= 0 {
                    NSLog("[FFmpeg] 硬解不可用，已回退软解")
                    return true
                }
            }
            return false
        }
        return true
    }

    /// 为指定音频流构建 解码器 + 重采样器（供首次打开与音轨切换共用）
    private func makeAudioPipeline(stream st: UnsafeMutablePointer<AVStream>) -> (codec: UnsafeMutablePointer<AVCodecContext>, swr: OpaquePointer)? {
        guard let codecPar = st.pointee.codecpar,
              let decoder = avcodec_find_decoder(codecPar.pointee.codec_id) else { return nil }
        guard let ac = avcodec_alloc_context3(decoder) else { return nil }
        func freeCodec() {
            var freed: UnsafeMutablePointer<AVCodecContext>? = ac
            avcodec_free_context(&freed)
        }
        guard avcodec_parameters_to_context(ac, codecPar) >= 0 else {
            freeCodec()
            return nil
        }
        guard avcodec_open2(ac, decoder, nil) >= 0 else {
            freeCodec()
            return nil
        }

        // 重采样器：任意样本格式 → float32 interleaved（采样率 / 声道布局保持不变）
        var outLayout = ac.pointee.ch_layout
        let inSampleRate = Int32(ac.pointee.sample_rate)
        var swr: OpaquePointer?
        let ret = swr_alloc_set_opts2(
            &swr,
            &outLayout,
            AV_SAMPLE_FMT_FLT,
            inSampleRate,
            &ac.pointee.ch_layout,
            ac.pointee.sample_fmt,
            inSampleRate,
            0,
            nil
        )
        guard ret >= 0, let swrObj = swr else {
            freeCodec()
            return nil
        }
        if swr_init(swrObj) < 0 {
            swr_free(&swr)
            freeCodec()
            return nil
        }
        return (ac, swrObj)
    }

    private func openAudioDecoder(stream st: UnsafeMutablePointer<AVStream>) -> Bool {
        guard let p = makeAudioPipeline(stream: st) else { return false }
        audioCodecCtx = p.codec
        swrCtx = p.swr
        return true
    }

    // MARK: - 控制

    func play() {
        guard !stopped else { return }
        setPaused(false)
        let rate = playbackRate
        synchronizer.setRate(Float(rate), time: synchronizer.currentTime())
    }

    func pause() {
        guard !stopped else { return }
        setPaused(true)
        synchronizer.setRate(0.0, time: synchronizer.currentTime())
    }

    /// 设置播放速率；暂停时只记忆速率，恢复播放后生效
    func setRate(_ rate: Double) {
        guard !stopped else { return }
        let clamped = max(0.25, min(4.0, rate))
        setPlaybackRate(clamped)
        guard !paused else { return }
        synchronizer.setRate(Float(clamped), time: synchronizer.currentTime())
    }

    /// 设置音量 0~1
    private(set) var currentVolume: Float = 1.0

    func setVolume(_ volume: Float) {
        currentVolume = max(0, min(1, volume))
        audioRenderer.volume = currentVolume
    }

    var isPaused: Bool { return paused }

    func seek(to seconds: Double) {
        setPendingSeek(max(0, seconds))
    }

    /// 按音轨列表顺序（ordinal）切换音轨；切换在播放线程内完成并自动从当前位置续播
    func selectAudioStream(ordinal: Int) {
        locked {
            guard audioStreams.indices.contains(ordinal) else { return }
            _pendingAudioIndex = audioStreams[ordinal].index
        }
    }

    func stop() {
        setStopped(true)
        playThread?.cancel()
        playThread = nil
        let t = synchronizer.currentTime()
        synchronizer.removeRenderer(videoLayer, at: t)
        synchronizer.removeRenderer(audioRenderer, at: t)
        videoLayer.flush()
        audioRenderer.flush()
        cleanup()
    }

    private func fail(_ message: String) {
        setStopped(true)
        onError?(message)
    }

    private func cleanup() {
        if swsCtx != nil { sws_freeContext(swsCtx); self.swsCtx = nil }
        if swrCtx != nil { swr_free(&swrCtx); self.swrCtx = nil }
        if videoCodecCtx != nil { avcodec_free_context(&videoCodecCtx); self.videoCodecCtx = nil }
        if audioCodecCtx != nil { avcodec_free_context(&audioCodecCtx); self.audioCodecCtx = nil }
        if fmtCtx != nil { avformat_close_input(&fmtCtx); self.fmtCtx = nil }
        hwDeviceCtx = nil  // 引用随 avcodec_free_context 释放
        videoStreamIdx = -1
        audioStreamIdx = -1
        subtitleStreams = []
        audioStreams = []
        chapters = []
        mediaInfoLines = []
        setEmbeddedSubtitles([:])
        setPendingSeek(nil)
        setPendingAudioIndex(nil)
        setLastPixelBuffer(nil)
        pixelPool = nil
        poolSize = .zero
        syncSubtitlePreload = false
        swsSrcFormat = -1
    }

    // MARK: - 内嵌字幕

    private static func isTextSubtitle(_ codecId: AVCodecID) -> Bool {
        switch codecId {
        case AV_CODEC_ID_SUBRIP, AV_CODEC_ID_ASS, AV_CODEC_ID_SSA,
             AV_CODEC_ID_WEBVTT, AV_CODEC_ID_MOV_TEXT, AV_CODEC_ID_TEXT:
            return true
        default:
            return false
        }
    }

    private func languageOf(_ st: UnsafeMutablePointer<AVStream>) -> String {
        guard let md = st.pointee.metadata,
              let entry = av_dict_get(md, "language", nil, 0),
              let value = entry.pointee.value else { return "" }
        return String(cString: value)
    }

    /// 小文件：播放前一次性提取所有内嵌文本字幕（在播放线程内执行，与 demux 串行）
    private func preloadEmbeddedSubtitles() {
        guard !subtitleStreams.isEmpty, let fmtCtx else { return }
        NSLog("[FFmpeg] 开始提取内嵌字幕，流数=%d", subtitleStreams.count)

        var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        defer { av_packet_free(&pkt) }

        var collected: [Int: [SubtitleCue]] = [:]
        var readCount = 0
        while av_read_frame(fmtCtx, pkt!) >= 0 {
            defer { av_packet_unref(pkt!) }
            readCount += 1
            let idx = Int(pkt!.pointee.stream_index)
            guard subtitleStreams.contains(where: { $0.index == idx }),
                  let par = fmtCtx.pointee.streams[idx]?.pointee.codecpar else { continue }
            let cues = parseSubtitlePacketData(pkt: pkt!, codecId: par.pointee.codec_id, streamIndex: idx, fmtCtx: fmtCtx)
            if !cues.isEmpty {
                collected[idx, default: []].append(contentsOf: cues)
            }
        }
        NSLog("[FFmpeg] 字幕提取循环结束，共读 %d 个 packet，字幕 %d 条", readCount,
              collected.values.reduce(0) { $0 + $1.count })

        // 回到开头，准备播放
        let streamIdx = videoStreamIdx >= 0 ? Int32(videoStreamIdx) : Int32(audioStreamIdx)
        if streamIdx >= 0 {
            av_seek_frame(fmtCtx, streamIdx, 0, Self.avSeekFlagBackward)
            if videoStreamIdx >= 0 { avcodec_flush_buffers(videoCodecCtx) }
            if audioStreamIdx >= 0 { avcodec_flush_buffers(audioCodecCtx) }
        }

        setEmbeddedSubtitles(collected)
        if !collected.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onSubtitlesReady?()
            }
        }
    }

    /// 大文件 / 网络流：独立线程用自己的 demux 上下文后台提取，不阻塞起播
    private func startAsyncSubtitleExtraction(urlString: String, targets: [(index: Int, language: String)]) {
        let idxs = Set(targets.map { $0.index })
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            var ctx: UnsafeMutablePointer<AVFormatContext>?
            guard let c = urlString.cString(using: .utf8),
                  avformat_open_input(&ctx, c, nil, nil) == 0,
                  let ctxStrong = ctx,
                  avformat_find_stream_info(ctxStrong, nil) >= 0 else { return }

            var collected: [Int: [SubtitleCue]] = [:]
            var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
            defer { av_packet_free(&pkt) }
            while av_read_frame(ctxStrong, pkt) >= 0 {
                defer { av_packet_unref(pkt) }
                let idx = Int(pkt!.pointee.stream_index)
                guard idxs.contains(idx),
                      let par = ctxStrong.pointee.streams[idx]?.pointee.codecpar else { continue }
                let cues = self.parseSubtitlePacketData(pkt: pkt!, codecId: par.pointee.codec_id, streamIndex: idx, fmtCtx: ctxStrong)
                if !cues.isEmpty {
                    collected[idx, default: []].append(contentsOf: cues)
                }
            }
            avformat_close_input(&ctx)

            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped, self.openedURLString == urlString else { return }
                self.setEmbeddedSubtitles(collected)
                if !collected.isEmpty {
                    self.onSubtitlesReady?()
                }
            }
        }
    }

    private func parseSubtitlePacketData(pkt: UnsafeMutablePointer<AVPacket>, codecId: AVCodecID, streamIndex: Int, fmtCtx: UnsafeMutablePointer<AVFormatContext>) -> [SubtitleCue] {
        guard let data = pkt.pointee.data, pkt.pointee.size > 0 else { return [] }
        let size = Int(pkt.pointee.size)
        let bytes = Array(UnsafeBufferPointer(start: data, count: size))

        guard let st = fmtCtx.pointee.streams[streamIndex] else { return [] }
        let tb = st.pointee.time_base
        let tbSeconds = Double(tb.num) / Double(max(tb.den, 1))
        let start = Double(pkt.pointee.pts) * tbSeconds
        let dur = Double(pkt.pointee.duration) * tbSeconds
        let end = dur > 0 ? start + dur : start + 3

        switch codecId {
        case AV_CODEC_ID_ASS, AV_CODEC_ID_SSA:
            if let text = String(bytes: bytes, encoding: .utf8) {
                let cues = SubtitleParser.parseASS(text: text)
                if !cues.isEmpty { return cues }
                let cleaned = cleanSubtitleText(text)
                if !cleaned.isEmpty { return [SubtitleCue(start: start, end: end, text: cleaned)] }
            }
        case AV_CODEC_ID_SUBRIP, AV_CODEC_ID_WEBVTT:
            if let text = String(bytes: bytes, encoding: .utf8) {
                // 有些封装直接存完整 SRT 块，有些只存纯文本（时间在 PTS 里）
                if text.contains("-->") {
                    return SubtitleParser.parse(text: text)
                }
                let cleaned = cleanSubtitleText(text)
                if !cleaned.isEmpty { return [SubtitleCue(start: start, end: end, text: cleaned)] }
            }
        case AV_CODEC_ID_MOV_TEXT, AV_CODEC_ID_TEXT:
            // MP4 mov_text：2 字节长度前缀 + UTF-8 文本
            if bytes.count > 2 {
                let len = Int(bytes[0]) << 8 | Int(bytes[1])
                if len > 0, len <= bytes.count - 2,
                   let text = String(bytes: Array(bytes[2..<(2 + len)]), encoding: .utf8) {
                    let cleaned = cleanSubtitleText(text)
                    if !cleaned.isEmpty { return [SubtitleCue(start: start, end: end, text: cleaned)] }
                }
            }
        default:
            break
        }
        return []
    }

    private func cleanSubtitleText(_ s: String) -> String {
        var t = s
        while let open = t.range(of: "{"), let close = t.range(of: "}", range: open.upperBound..<t.endIndex) {
            t.removeSubrange(open.lowerBound..<close.upperBound)
        }
        t = SubtitleParser.stripBasicTags(t)
        return t
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 播放循环（单后台线程：解复用 + 解码 + enqueue）

    private func startThread() {
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "ffmpeg-play-loop"
        playThread = t
        t.start()
    }

    private func runLoop() {
        // 小文件：播放前先提取内嵌字幕（与 demux 串行，避免竞争）
        if syncSubtitlePreload {
            preloadEmbeddedSubtitles()
        }

        while !stopped {
            if let target = takePendingAudioIndex() {
                switchAudioStream(to: target)
                continue
            }
            if let target = takePendingSeek() {
                performSeek(to: target)
                continue
            }
            if eof {
                // 已读完全部数据，等已入队的样本真正播放完
                let t = synchronizer.currentTime().seconds
                let target = duration > 0 ? duration : lastEnqueuedSeconds
                if target > 0 && t >= target - 0.2 {
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            updateBuffered()
            if paused || bufferedSeconds > 5.0 {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            if !stepOnce() { continue }  // stepOnce 内部置 eof = true
        }

        if !stopped {
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackEnded?()
            }
        }
    }

    /// 在播放线程内切换音轨：重建解码器，flush 音频渲染器，并从当前播放位置续播
    private func switchAudioStream(to targetIndex: Int) {
        guard let fmtCtx else { return }
        guard targetIndex != audioStreamIdx,
              Int(fmtCtx.pointee.nb_streams) > targetIndex,
              let st = fmtCtx.pointee.streams[targetIndex],
              let par = st.pointee.codecpar,
              par.pointee.codec_type == AVMEDIA_TYPE_AUDIO,
              let pipeline = makeAudioPipeline(stream: st) else { return }

        if audioCodecCtx != nil { avcodec_free_context(&audioCodecCtx); audioCodecCtx = nil }
        if swrCtx != nil { swr_free(&swrCtx); swrCtx = nil }
        audioCodecCtx = pipeline.codec
        swrCtx = pipeline.swr
        audioStreamIdx = targetIndex
        audioTimeBase = st.pointee.time_base

        audioRenderer.flush()
        let now = synchronizer.currentTime().seconds
        setPendingSeek(now.isFinite && now >= 0 ? now : 0)
        setEof(false)
    }

    /// 读取一个 packet 并解码。返回 false 表示 EOF。
    private func stepOnce() -> Bool {
        guard let fmtCtx else { return false }
        var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        defer { av_packet_free(&pkt) }

        let ret = av_read_frame(fmtCtx, pkt!)
        if ret < 0 {
            setEof(true)
            return false
        }
        defer { av_packet_unref(pkt!) }

        let idx = Int(pkt!.pointee.stream_index)
        if idx == videoStreamIdx {
            decodeVideo(pkt: pkt!)
        } else if idx == audioStreamIdx {
            decodeAudio(pkt: pkt!)
        }
        return true
    }

    private func updateBuffered() {
        bufferedSeconds = max(0, lastEnqueuedSeconds - synchronizer.currentTime().seconds)
    }

    // MARK: - 视频解码

    private func decodeVideo(pkt: UnsafeMutablePointer<AVPacket>) {
        guard let vc = videoCodecCtx else { return }
        guard avcodec_send_packet(vc, pkt) >= 0 else { return }

        var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        defer { av_frame_free(&frame) }

        while avcodec_receive_frame(vc, frame!) >= 0 {
            let rawFmt = frame!.pointee.format
            var swFrame: UnsafeMutablePointer<AVFrame>?
            var frameToUse = frame!

            // 181 videotoolbox：CVPixelBuffer 硬件帧 → 转回内存
            if rawFmt == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
                swFrame = av_frame_alloc()
                if swFrame != nil, av_hwframe_transfer_data(swFrame, frame!, 0) >= 0 {
                    frameToUse = swFrame!
                } else {
                    av_frame_free(&swFrame)
                    continue
                }
            }
            defer { if swFrame != nil { av_frame_free(&swFrame) } }

            // 检测旋转元数据（display matrix），90/270 时画面旋转并通知窗口调整尺寸
            if let sd = av_frame_get_side_data(frameToUse, AV_FRAME_DATA_DISPLAYMATRIX),
               let m = sd.pointee.data {
                let matrix = m.withMemoryRebound(to: Int32.self, capacity: 9) { $0 }
                var deg = Int(round(av_display_rotation_get(matrix)))
                deg = ((deg % 360) + 360) % 360
                if deg != rotation {
                    setRotation(deg)
                    DispatchQueue.main.async { [weak self] in
                        self?.onRotation?(deg)
                    }
                }
            }

            // videotoolbox_vld（GPU 解码、内存 NV12 布局）→ 按 NV12 作为 sws 源格式
            let swsSourceFormat: Int32 = (rawFmt == Self.videotoolboxVldFormat)
                ? AV_PIX_FMT_NV12.rawValue
                : frameToUse.pointee.format

            // 若源像素格式变化，重建 sws
            if swsCtx == nil || swsSourceFormat != swsSrcFormat {
                rebuildSws(frame: frameToUse, sourceFormat: swsSourceFormat)
            }
            guard swsCtx != nil else { continue }

            if let sb = makeVideoSampleBuffer(frame: frameToUse) {
                videoLayer.enqueue(sb)
                let ptsUs = av_rescale_q(frameToUse.pointee.pts, videoTimeBase, Self.avTimeBaseQ)
                lastEnqueuedSeconds = Double(ptsUs) / 1_000_000.0
            }
        }
    }

    /// videotoolbox_vld 是运行时动态注册的像素格式
    private static let videotoolboxVldFormat: Int32 = {
        let f = av_get_pix_fmt("videotoolbox_vld")
        return f.rawValue == AV_PIX_FMT_NONE.rawValue ? -1 : Int32(f.rawValue)
    }()

    private func colorspaceConstant(for ctx: UnsafeMutablePointer<AVCodecContext>?) -> Int32 {
        guard let ctx else { return Self.swsCS_ITU601 }
        switch ctx.pointee.colorspace {
        case AVCOL_SPC_BT709: return Self.swsCS_ITU709
        case AVCOL_SPC_BT470BG, AVCOL_SPC_SMPTE170M, AVCOL_SPC_SMPTE240M: return Self.swsCS_ITU601
        case AVCOL_SPC_BT2020_CL, AVCOL_SPC_BT2020_NCL: return Self.swsCS_BT2020
        default:
            // 未声明时按分辨率猜测：高清用 709，标清用 601
            let w = ctx.pointee.width, h = ctx.pointee.height
            return (w >= 1280 || h > 576) ? Self.swsCS_ITU709 : Self.swsCS_ITU601
        }
    }

    private func isHDR(_ ctx: UnsafeMutablePointer<AVCodecContext>?) -> Bool {
        guard let ctx else { return false }
        return ctx.pointee.color_trc == AVCOL_TRC_SMPTE2084 || ctx.pointee.color_trc == AVCOL_TRC_ARIB_STD_B67
    }

    private func rebuildSws(frame: UnsafeMutablePointer<AVFrame>, sourceFormat: Int32) {
        sws_freeContext(swsCtx)
        swsCtx = nil
        let srcFmt = AVPixelFormat(rawValue: sourceFormat)
        let w = Int32(frame.pointee.width)
        let h = Int32(frame.pointee.height)
        guard w > 0, h > 0 else { return }
        swsCtx = sws_getContext(w, h, srcFmt, w, h, AV_PIX_FMT_BGRA, Self.swsBilinear, nil, nil, nil)
        if let ctx = swsCtx {
            swsSrcFormat = sourceFormat
            // 色彩空间转换：源色彩矩阵（601/709/2020）+ 源/目标量程 → sRGB 全量程
            let srcCS = colorspaceConstant(for: videoCodecCtx)
            let srcRange: Int32 = (videoCodecCtx?.pointee.color_range == AVCOL_RANGE_JPEG) ? 1 : 0
            let hdr = isHDR(videoCodecCtx)
            let brightness: Int32 = 0
            let contrast: Int32 = hdr ? Int32(1.15 * 65536) : 1 << 16
            let saturation: Int32 = hdr ? Int32(1.05 * 65536) : 1 << 16
            sws_setColorspaceDetails(
                ctx,
                sws_getCoefficients(srcCS), srcRange,
                sws_getCoefficients(Self.swsCS_ITU709), 1,
                brightness, contrast, saturation)
        }
    }

    // MARK: 像素缓冲池 + 旋转

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        if pixelPool == nil || poolSize != size {
            var pool: CVPixelBufferPool?
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            pixelPool = pool
            poolSize = size
        }
        if let pool = pixelPool {
            var pb: CVPixelBuffer?
            if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess, let pb {
                return pb
            }
        }
        // 池创建失败时回退为直接分配
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }

    private func rotatePixelBuffer(_ src: CVPixelBuffer, rotation: Int) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        let swap = (rotation == 90 || rotation == 270)
        let ow = swap ? h : w
        let oh = swap ? w : h
        guard let dst = createPixelBuffer(width: ow, height: oh) else { return nil }

        CVPixelBufferLockBaseAddress(src, [])
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, [])
            CVPixelBufferUnlockBaseAddress(dst, [])
        }
        guard let sBase = CVPixelBufferGetBaseAddress(src),
              let dBase = CVPixelBufferGetBaseAddress(dst) else { return nil }

        var sBuf = vImage_Buffer(
            data: sBase, height: vImagePixelCount(h), width: vImagePixelCount(w),
            rowBytes: CVPixelBufferGetBytesPerRow(src))
        var dBuf = vImage_Buffer(
            data: dBase, height: vImagePixelCount(oh), width: vImagePixelCount(ow),
            rowBytes: CVPixelBufferGetBytesPerRow(dst))

        // vImage rotationConstant：1 = 90° 逆时针，2 = 180°，3 = 270° 逆时针
        let constant: UInt8
        switch rotation {
        case 90: constant = 1
        case 180: constant = 2
        default: constant = 3  // 270
        }
        let backColor: [UInt8] = [0, 0, 0, 0]
        let err = vImageRotate90_ARGB8888(&sBuf, &dBuf, constant, backColor, vImage_Flags(kvImageNoFlags))
        return err == kvImageNoError ? dst : nil
    }

    private func makeVideoSampleBuffer(frame: UnsafeMutablePointer<AVFrame>) -> CMSampleBuffer? {
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)
        guard width > 0, height > 0 else { return nil }

        // 软解路径：创建 BGRA pixelBuffer（池复用）并 sws_scale 转换
        guard let pixelBuffer = createPixelBuffer(width: width, height: height) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let dstBase = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var dstData: [UnsafeMutablePointer<UInt8>?] = [dstBase?.assumingMemoryBound(to: UInt8.self)]
        var dstStride: [Int32] = [Int32(bytesPerRow)]
        let srcData = frameDataPointers(frame)
        let srcStride = frameStride(frame)
        sws_scale(swsCtx, srcData, srcStride, 0, Int32(height), &dstData, &dstStride)

        // 旋转元数据：90/180/270 时对像素做旋转
        var outputPB = pixelBuffer
        let rot = rotation
        if rot != 0 {
            guard let rotated = rotatePixelBuffer(pixelBuffer, rotation: rot) else { return nil }
            outputPB = rotated
        }
        setLastPixelBuffer(outputPB)

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: outputPB, formatDescriptionOut: &formatDesc)
        guard let formatDesc else { return nil }

        let ptsUs = av_rescale_q(frame.pointee.pts, videoTimeBase, Self.avTimeBaseQ)
        let pts = CMTime(value: ptsUs, timescale: 1_000_000)
        var timing = CMSampleTimingInfo(
            duration: videoFrameDuration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)

        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPB,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sb)
        return sb
    }

    // MARK: - 音频解码

    private func decodeAudio(pkt: UnsafeMutablePointer<AVPacket>) {
        guard let ac = audioCodecCtx, let swrCtx else { return }
        guard avcodec_send_packet(ac, pkt) >= 0 else { return }

        var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        defer { av_frame_free(&frame) }

        while avcodec_receive_frame(ac, frame!) >= 0 {
            if let sb = makeAudioSampleBuffer(frame: frame!, swrCtx: swrCtx) {
                audioRenderer.enqueue(sb)
                let ptsUs = av_rescale_q(frame!.pointee.pts, audioTimeBase, Self.avTimeBaseQ)
                lastEnqueuedSeconds = Double(ptsUs) / 1_000_000.0
            }
        }
    }

    private func makeAudioSampleBuffer(frame: UnsafeMutablePointer<AVFrame>, swrCtx: OpaquePointer) -> CMSampleBuffer? {
        let sampleRate = Int(frame.pointee.sample_rate)
        let channels = Int(frame.pointee.ch_layout.nb_channels)
        let inSamples = Int(frame.pointee.nb_samples)
        guard sampleRate > 0, channels > 0, inSamples > 0 else { return nil }

        let bytesPerSample = 4
        let dataSize = inSamples * channels * bytesPerSample

        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        defer { outBuf.deallocate() }
        var outData: [UnsafeMutablePointer<UInt8>?] = [outBuf]

        let converted = swr_convert(swrCtx, &outData, Int32(inSamples), frameDataPointers(frame), Int32(inSamples))
        guard converted > 0 else { return nil }

        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = Float64(sampleRate)
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        asbd.mBitsPerChannel = 32
        asbd.mChannelsPerFrame = UInt32(channels)
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerFrame = UInt32(channels * bytesPerSample)
        asbd.mBytesPerPacket = UInt32(channels * bytesPerSample)

        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDesc)
        guard let formatDesc else { return nil }

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: dataSize, flags: 0, blockBufferOut: &blockBuffer)
        guard let blockBuffer else { return nil }
        CMBlockBufferReplaceDataBytes(with: outBuf, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: dataSize)

        // 音频延迟（A/V 同步微调）：正值 = 音频更晚播出
        let delayUs = Int64(audioDelay * 1_000_000)
        let ptsUs = av_rescale_q(frame.pointee.pts, audioTimeBase, Self.avTimeBaseQ)
        let pts = CMTime(value: ptsUs + delayUs, timescale: 1_000_000)

        var packetDesc = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(dataSize))

        var sb: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(converted),
            presentationTimeStamp: pts,
            packetDescriptions: &packetDesc,
            sampleBufferOut: &sb)
        return sb
    }

    // MARK: - Seek

    private func performSeek(to seconds: Double) {
        guard let fmtCtx else { return }
        let targetUs = Int64(seconds * 1_000_000)
        let streamIdx = videoStreamIdx >= 0 ? Int32(videoStreamIdx) : Int32(audioStreamIdx)
        let base = videoStreamIdx >= 0 ? videoTimeBase : audioTimeBase
        let targetTs = av_rescale_q(targetUs, Self.avTimeBaseQ, base)

        av_seek_frame(fmtCtx, streamIdx, targetTs, Self.avSeekFlagBackward)
        if videoStreamIdx >= 0 { avcodec_flush_buffers(videoCodecCtx) }
        if audioStreamIdx >= 0 { avcodec_flush_buffers(audioCodecCtx) }

        videoLayer.flush()
        audioRenderer.flush()

        let time = CMTime(value: targetUs, timescale: 1_000_000)
        let rate = paused ? 0.0 : playbackRate
        synchronizer.setRate(Float(rate), time: time)
        lastEnqueuedSeconds = seconds
        bufferedSeconds = 0
        setEof(false)
    }

    // MARK: - 指针辅助

    /// 把 AVFrame.data 转成 sws/swr 需要的 `const uint8_t *[]`
    private func frameDataPointers(_ frame: UnsafeMutablePointer<AVFrame>) -> [UnsafePointer<UInt8>?] {
        let d = frame.pointee.data  // FFmpeg 8: 固定长度数组，导入为 8 元组
        return [d.0, d.1, d.2, d.3, d.4, d.5, d.6, d.7].map { $0.map { UnsafePointer($0) } }
    }

    private func frameStride(_ frame: UnsafeMutablePointer<AVFrame>) -> [Int32] {
        let ls = frame.pointee.linesize
        return [ls.0, ls.1, ls.2, ls.3, ls.4, ls.5, ls.6, ls.7]
    }
}
