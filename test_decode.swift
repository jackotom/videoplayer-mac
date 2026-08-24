import Foundation

// 最小解码验证：确认 Swift 能正确桥接 FFmpeg 8.x 的 C API
func testDecode(path: String) {
    let cPath = path.cString(using: .utf8)!

    var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
    guard avformat_open_input(&fmtCtx, cPath, nil, nil) == 0 else {
        print("❌ open_input failed")
        return
    }
    defer { avformat_close_input(&fmtCtx) }

    guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
        print("❌ find_stream_info failed")
        return
    }

    print("=== 流信息 ===")
    let nbStreams = Int(fmtCtx!.pointee.nb_streams)
    print("容器: \(String(cString: fmtCtx!.pointee.iformat!.pointee.name))  时长: \(fmtCtx!.pointee.duration)  流数量: \(nbStreams)")

    var videoIdx = -1, audioIdx = -1
    for i in 0..<nbStreams {
        let st = fmtCtx!.pointee.streams[i]!
        let codecType = st.pointee.codecpar!.pointee.codec_type
        let codecId = st.pointee.codecpar!.pointee.codec_id
        if codecType == AVMEDIA_TYPE_VIDEO && videoIdx < 0 {
            videoIdx = i
            print("  视频流 \(i): \(String(cString: avcodec_get_name(codecId))) \(st.pointee.codecpar!.pointee.width)x\(st.pointee.codecpar!.pointee.height)")
        } else if codecType == AVMEDIA_TYPE_AUDIO && audioIdx < 0 {
            audioIdx = i
            print("  音频流 \(i): \(String(cString: avcodec_get_name(codecId))) 采样率 \(st.pointee.codecpar!.pointee.sample_rate) 声道 \(st.pointee.codecpar!.pointee.ch_layout.nb_channels)")
        }
    }

    if videoIdx >= 0 { decodeVideo(fmtCtx: fmtCtx!, idx: videoIdx, maxFrames: 8) }
    if audioIdx >= 0 { decodeAudio(fmtCtx: fmtCtx!, idx: audioIdx, maxFrames: 8) }
    print("✅ 解码验证完成")
}

func decodeVideo(fmtCtx: UnsafeMutablePointer<AVFormatContext>, idx: Int, maxFrames: Int) {
    let st = fmtCtx.pointee.streams[idx]!
    let codecPar = st.pointee.codecpar!
    guard let decoder = avcodec_find_decoder(codecPar.pointee.codec_id) else {
        print("❌ 找不到视频解码器"); return
    }
    var ctx: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(decoder)
    guard ctx != nil else { print("❌ alloc context 失败"); return }
    defer { avcodec_free_context(&ctx) }
    guard avcodec_parameters_to_context(ctx!, codecPar) >= 0 else {
        print("❌ parameters_to_context 失败"); return
    }
    guard avcodec_open2(ctx!, decoder, nil) >= 0 else {
        print("❌ 视频解码器打开失败"); return
    }

    var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    defer { av_frame_free(&frame) }
    var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    defer { av_packet_free(&pkt) }

    var decoded = 0
    while decoded < maxFrames {
        let ret = av_read_frame(fmtCtx, pkt!)
        if ret < 0 { break }
        defer { av_packet_unref(pkt!) }
        guard pkt!.pointee.stream_index == idx else { continue }
        guard avcodec_send_packet(ctx!, pkt!) >= 0 else { continue }
        while avcodec_receive_frame(ctx!, frame!) >= 0 {
            print("  视频帧: \(frame!.pointee.width)x\(frame!.pointee.height) pixfmt=\(frame!.pointee.format) pts=\(frame!.pointee.pts)")
            decoded += 1
            if decoded >= maxFrames { break }
        }
    }
    print("  视频解码 \(decoded) 帧 ✓")
}

func decodeAudio(fmtCtx: UnsafeMutablePointer<AVFormatContext>, idx: Int, maxFrames: Int) {
    let st = fmtCtx.pointee.streams[idx]!
    let codecPar = st.pointee.codecpar!
    guard let decoder = avcodec_find_decoder(codecPar.pointee.codec_id) else {
        print("❌ 找不到音频解码器"); return
    }
    var ctx: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(decoder)
    guard ctx != nil else { return }
    defer { avcodec_free_context(&ctx) }
    guard avcodec_parameters_to_context(ctx!, codecPar) >= 0 else { return }
    guard avcodec_open2(ctx!, decoder, nil) >= 0 else {
        print("❌ 音频解码器打开失败"); return
    }

    var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    defer { av_frame_free(&frame) }
    var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    defer { av_packet_free(&pkt) }

    var decoded = 0
    while decoded < maxFrames {
        let ret = av_read_frame(fmtCtx, pkt!)
        if ret < 0 { break }
        defer { av_packet_unref(pkt!) }
        guard pkt!.pointee.stream_index == idx else { continue }
        guard avcodec_send_packet(ctx!, pkt!) >= 0 else { continue }
        while avcodec_receive_frame(ctx!, frame!) >= 0 {
            print("  音频帧: samples=\(frame!.pointee.nb_samples) fmt=\(frame!.pointee.format) rate=\(frame!.pointee.sample_rate) ch=\(frame!.pointee.ch_layout.nb_channels) pts=\(frame!.pointee.pts)")
            decoded += 1
            if decoded >= maxFrames { break }
        }
    }
    print("  音频解码 \(decoded) 帧 ✓")
}

if CommandLine.arguments.count < 2 {
    print("用法: test_decode <视频文件>")
    exit(1)
}
testDecode(path: CommandLine.arguments[1])
