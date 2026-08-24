import Cocoa
import AVKit
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers
import Sparkle

// MARK: - 可拖拽视图

final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true { return .copy }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let objs = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }
        onDrop?(objs)
        return true
    }
}

// MARK: - AVPlayerLayer 视图（替代 AVPlayerView：画中画需要直接持有 playerLayer）

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeBackingLayer() -> CALayer { return playerLayer }
}

// MARK: - 主播放控制器

final class PlayerViewController: NSViewController {

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "wmv", "ts", "m2ts", "mts",
        "mpg", "mpeg", "vob", "3gp", "3g2", "rm", "rmvb", "divx", "mxf", "ogv", "m2v",
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "wma", "opus", "ac3", "ape",
    ]

    let player = AVPlayer()
    let playerLayerView = PlayerLayerView()
    let subtitleLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(labelWithString: "")

    let playerContainer = NSView()
    let sidebarContainer = NSView()
    let playlistTableView = NSTableView()
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var sidebarVisible = false

    let ffmpegPlayer = FFmpegPlayer()
    let ffmpegView = NSView()
    lazy var controlBar = PlaybackControlBar(controller: self)
    private(set) var usingFFmpeg = false

    private(set) var playlist: [URL] = []
    private(set) var currentIndex = -1

    private var subtitleCues: [SubtitleCue] = []
    private var subtitlePositionConstraint: NSLayoutConstraint!
    private var embeddedSubtitleSelection: Int?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var ffmpegSubtitleTimer: Timer?
    private var keyMonitor: Any?
    private var presentationSizeObserver: NSKeyValueObservation?
    private var controlsIdleTimer: Timer?
    private var controlsVisibleState = true
    private var lastControlInteraction = Date()

    // 新增功能状态
    private var piPController: AVPictureInPictureController?
    private var abLoopA: Double?
    private var abLoopB: Double?
    private var miniMode = false
    private var savedWindowFrame: NSRect?
    private var currentSpeed: Float = Float(Settings.shared.playbackSpeed)

    // MARK: 生命周期

    override func loadView() {
        let drop = DropView(frame: NSRect(x: 0, y: 0, width: 1000, height: 620))
        drop.onDrop = { [weak self] urls in self?.handleURLs(urls) }
        self.view = drop
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupPlayerView()
        setupFFmpegView()
        setupSubtitleLabel()
        setupHintLabel()
        setupContextMenu()
        setupPlaylistTable()
        setupKeyMonitor()
        setupMouseTracking()
        setupRemoteCommands()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.updateSubtitleLabel(time: time)
            self.checkABLoop(time: time.seconds)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged(_:)), name: .settingsChanged, object: nil)
        applyWindowSettings()
        startControlsIdleTimer()
    }

    // MARK: 控制条自动隐藏

    private func setupMouseTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil)
        playerContainer.addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        showControls()
    }

    override func mouseEntered(with event: NSEvent) {
        showControls()
    }

    private func startControlsIdleTimer() {
        controlsIdleTimer?.invalidate()
        controlsIdleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkControlsIdle()
        }
    }

    private func checkControlsIdle() {
        guard controlsVisibleState, !unifiedPaused, !miniMode else { return }
        if Date().timeIntervalSince(lastControlInteraction) > 3 && !isMouseOverControlBar() {
            setControlsVisible(false)
        }
    }

    func showControls() {
        lastControlInteraction = Date()
        if !controlsVisibleState {
            setControlsVisible(true)
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        controlsVisibleState = visible
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? 0.2 : 0.4
            controlBar.animator().alphaValue = visible ? 1 : 0
        }
    }

    private func isMouseOverControlBar() -> Bool {
        guard let window = view.window, !controlBar.isHidden else { return false }
        let loc = playerContainer.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return controlBar.frame.contains(loc)
    }

    @objc private func settingsChanged(_ note: Notification) {
        applyWindowSettings()
        subtitlePositionConstraint.constant = -CGFloat(Settings.shared.subtitlePosition)
    }

    private func applyWindowSettings() {
        view.window?.level = miniMode ? .floating : (Settings.shared.alwaysOnTop ? .floating : .normal)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        ffmpegPlayer.videoLayer.frame = ffmpegView.bounds
    }

    private func setupLayout() {
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerContainer)

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.wantsLayer = true
        sidebarContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        sidebarContainer.isHidden = true
        view.addSubview(sidebarContainer)

        // 侧栏宽度约束始终激活，通过 constant 切换 0（隐藏）/230（显示），避免 ambiguous 布局
        sidebarWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 0)
        sidebarWidthConstraint.isActive = true

        NSLayoutConstraint.activate([
            playerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            playerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerContainer.trailingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),

            sidebarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupPlayerView() {
        playerLayerView.playerLayer.player = player
        playerLayerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(playerLayerView)
        NSLayoutConstraint.activate([
            playerLayerView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            playerLayerView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            playerLayerView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            playerLayerView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
        ])
        // 点击画面播放/暂停（迷你模式下双击退出迷你模式）
        let click = NSClickGestureRecognizer(target: self, action: #selector(playerViewClicked))
        playerLayerView.addGestureRecognizer(click)
    }

    @objc private func playerViewClicked() {
        if miniMode { exitMiniMode(); return }
        guard !usingFFmpeg else { return }
        if player.rate == 0 { avkitPlay() } else { player.pause() }
    }

    private func setupSubtitleLabel() {
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.cell?.wraps = true
        subtitleLabel.cell?.isScrollable = false
        subtitleLabel.attributedStringValue = NSAttributedString()
        subtitleLabel.wantsLayer = true
        subtitleLabel.layer?.shadowColor = NSColor.black.cgColor
        subtitleLabel.layer?.shadowRadius = 3
        subtitleLabel.layer?.shadowOpacity = 0.9
        subtitleLabel.layer?.shadowOffset = .zero
        playerContainer.addSubview(subtitleLabel)
        subtitlePositionConstraint = subtitleLabel.bottomAnchor.constraint(
            equalTo: playerContainer.bottomAnchor, constant: -CGFloat(Settings.shared.subtitlePosition))
        NSLayoutConstraint.activate([
            subtitleLabel.centerXAnchor.constraint(equalTo: playerContainer.centerXAnchor),
            subtitlePositionConstraint,
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: playerContainer.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playerContainer.trailingAnchor, constant: -32),
        ])
    }

    private func setupHintLabel() {
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        hintLabel.isBezeled = false
        hintLabel.drawsBackground = false
        hintLabel.alignment = .center
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        hintLabel.stringValue = "拖入视频文件，或按 ⌘O 打开"
        playerContainer.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: playerContainer.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: playerContainer.centerYAnchor),
        ])
    }

    // MARK: 短暂状态提示（复用 hintLabel）

    private func flashStatus(_ text: String) {
        hintLabel.stringValue = text
        hintLabel.textColor = .white
        hintLabel.font = NSFont.boldSystemFont(ofSize: 16)
        hintLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideFlashStatus), object: nil)
        perform(#selector(hideFlashStatus), with: nil, afterDelay: 1.4)
    }

    @objc private func hideFlashStatus() {
        hintLabel.stringValue = "拖入视频文件，或按 ⌘O 打开"
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        hintLabel.isHidden = !playlist.isEmpty
    }

    private func setupFFmpegView() {
        ffmpegView.wantsLayer = true
        ffmpegView.layer?.backgroundColor = NSColor.black.cgColor
        ffmpegView.translatesAutoresizingMaskIntoConstraints = false
        ffmpegView.isHidden = true
        playerContainer.addSubview(ffmpegView)
        NSLayoutConstraint.activate([
            ffmpegView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            ffmpegView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            ffmpegView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            ffmpegView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
        ])
        ffmpegView.layer?.addSublayer(ffmpegPlayer.videoLayer)

        let click = NSClickGestureRecognizer(target: self, action: #selector(ffmpegViewClicked))
        ffmpegView.addGestureRecognizer(click)

        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.isHidden = true
        playerContainer.addSubview(controlBar)
        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor, constant: 12),
            controlBar.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor, constant: -12),
            controlBar.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor, constant: -12),
            controlBar.heightAnchor.constraint(equalToConstant: 36),
        ])

        ffmpegPlayer.onReady = { [weak self] size in
            DispatchQueue.main.async {
                self?.ffmpegPlayer.videoLayer.frame = self?.ffmpegView.bounds ?? .zero
                self?.fitWindowToVideo(size)
            }
        }
        ffmpegPlayer.onError = { [weak self] msg in
            DispatchQueue.main.async { self?.showFFmpegError(msg) }
        }
        ffmpegPlayer.onPlaybackEnded = { [weak self] in
            DispatchQueue.main.async { self?.handlePlaybackEnded() }
        }
        // 旋转元数据：90/270 时宽高互换，重新适配窗口
        ffmpegPlayer.onRotation = { [weak self] deg in
            guard let self, self.usingFFmpeg, deg == 90 || deg == 270 else { return }
            let s = self.ffmpegPlayer.videoSize
            guard s.width > 0 && s.height > 0 else { return }
            self.fitWindowToVideo(CGSize(width: s.height, height: s.width))
        }
    }

    @objc private func ffmpegViewClicked() {
        if miniMode { exitMiniMode(); return }
        guard usingFFmpeg else { return }
        if ffmpegPlayer.isPaused { ffmpegPlayer.play() } else { ffmpegPlayer.pause() }
    }

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        view.menu = menu
    }

    // MARK: 媒体键 / 控制中心 Now Playing

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.remoteResume() }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.remotePause() }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.playNext() }
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.playPrevious() }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.unifiedSeek(to: e.positionTime) }
            return .success
        }
    }

    private func remoteResume() {
        if usingFFmpeg { ffmpegPlayer.play() } else { avkitPlay() }
    }

    private func remotePause() {
        if usingFFmpeg { ffmpegPlayer.pause() } else { player.pause() }
    }

    /// 播放（AVKit）：macOS 12+ 用 defaultRate 保持倍速
    private func avkitPlay() {
        if #available(macOS 12.0, *) {
            player.play()
        } else {
            player.play()
            player.rate = currentSpeed
        }
    }

    func updateNowPlayingInfo() {
        guard playlist.indices.contains(currentIndex) else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [MPMediaItemPropertyTitle: displayName(of: playlist[currentIndex])]
        let d = unifiedDuration
        if d.isFinite && d > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = d
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = unifiedCurrentTime
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = unifiedPaused ? 0 : Double(currentSpeed)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func displayName(of url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        let last = url.lastPathComponent
        return last.isEmpty ? url.absoluteString : last
    }

    // MARK: 播放列表侧栏

    private func setupPlaylistTable() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        sidebarContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
        ])

        playlistTableView.headerView = nil
        playlistTableView.dataSource = self
        playlistTableView.delegate = self
        playlistTableView.target = self
        playlistTableView.doubleAction = #selector(playlistDoubleClicked)
        playlistTableView.registerForDraggedTypes([.fileURL, Self.playlistRowType])
        playlistTableView.usesAlternatingRowBackgroundColors = true
        playlistTableView.rowHeight = 26

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "播放列表"
        col.width = 220
        col.resizingMask = .autoresizingMask
        playlistTableView.addTableColumn(col)

        scroll.documentView = playlistTableView
    }

    /// 播放列表内部行拖拽的自定义类型
    static let playlistRowType = NSPasteboard.PasteboardType("com.videoplayer.playlist-row")

    @objc func toggleSidebar() {
        if sidebarVisible { hideSidebar() } else { showSidebar() }
    }

    func showSidebar() {
        guard !sidebarVisible else { return }
        sidebarVisible = true
        sidebarWidthConstraint.constant = 230
        sidebarContainer.isHidden = false
        playlistTableView.reloadData()
        if playlist.indices.contains(currentIndex) {
            playlistTableView.selectRowIndexes(IndexSet(integer: currentIndex), byExtendingSelection: false)
        }
    }

    func hideSidebar() {
        guard sidebarVisible else { return }
        sidebarVisible = false
        sidebarWidthConstraint.constant = 0
        sidebarContainer.isHidden = true
    }

    /// 控制条可见性：有文件就显示
    private func updateControlsVisibility() {
        controlBar.isHidden = playlist.isEmpty
    }

    @objc private func playlistDoubleClicked() {
        let row = playlistTableView.clickedRow
        if playlist.indices.contains(row) {
            playItem(at: row)
        }
    }

    /// 追加文件到播放列表（不打断当前播放；若列表为空则开始播放）
    func appendToPlaylist(_ urls: [URL]) {
        let videos = urls.filter { $0.isFileURL && Self.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return }
        let wasEmpty = playlist.isEmpty
        playlist.append(contentsOf: videos)
        playlistTableView.reloadData()
        updateControlsVisibility()
        if wasEmpty {
            playItem(at: 0)
        }
    }

    private func removePlaylistItem(at row: Int) {
        guard playlist.indices.contains(row) else { return }
        playlist.remove(at: row)
        if playlist.isEmpty {
            currentIndex = -1
            player.pause()
            player.replaceCurrentItem(with: nil)
            switchToAVKit()
            hintLabel.isHidden = false
            view.window?.title = "视频播放器"
            clearSubtitles()
        } else if row < currentIndex {
            currentIndex -= 1
            updateTitle()
        } else if row == currentIndex {
            playItem(at: min(row, playlist.count - 1))
        }
        playlistTableView.reloadData()
        updateControlsVisibility()
    }

    @objc func removeSelectedFromPlaylist() {
        removePlaylistItem(at: playlistTableView.selectedRow)
    }

    /// 拖拽调整播放列表顺序
    private func movePlaylistItem(from srcRow: Int, to dstRow: Int) {
        guard srcRow != dstRow, playlist.indices.contains(srcRow), dstRow <= playlist.count else { return }
        let item = playlist.remove(at: srcRow)
        let insertRow = (srcRow < dstRow) ? dstRow - 1 : dstRow
        playlist.insert(item, at: insertRow)
        if currentIndex == srcRow {
            currentIndex = insertRow
        } else if srcRow < currentIndex && insertRow >= currentIndex {
            currentIndex -= 1
        } else if srcRow > currentIndex && insertRow <= currentIndex {
            currentIndex += 1
        }
        playlistTableView.reloadData()
        updateTitle()
    }

    // MARK: 键盘

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isEmpty || mods == .shift || mods == .numericPad else { return event }
        // 焦点在可输入控件时交给控件处理
        if let fr = view.window?.firstResponder {
            if fr is NSSlider || fr is NSTextField || fr is NSTextView || fr is NSTableView {
                return event
            }
        }
        let step = mods == .shift ? 10.0 : 5.0
        switch event.keyCode {
        case 123:  // ←
            seekBy(-step)
            return nil
        case 124:  // →
            seekBy(step)
            return nil
        case 125:  // ↓
            adjustVolume(by: -0.05)
            return nil
        case 126:  // ↑
            adjustVolume(by: 0.05)
            return nil
        case 53:  // esc：退出迷你模式
            if miniMode {
                exitMiniMode()
                return nil
            }
            return event
        case 38:  // j：后退 10 秒
            seekBy(-10)
            return nil
        case 40:  // k：播放/暂停
            togglePlayPause()
            return nil
        case 37:  // l：前进 10 秒
            seekBy(10)
            return nil
        case 5:   // g：字幕提前 0.5 秒
            adjustSubtitleOffset(-0.5)
            return nil
        case 4:   // h：字幕延后 0.5 秒
            adjustSubtitleOffset(0.5)
            return nil
        case 0:   // a：设置 A 点
            setLoopPointA()
            return nil
        case 11:  // b：设置 B 点
            setLoopPointB()
            return nil
        default:
            return event
        }
    }

    func seekBy(_ seconds: Double) {
        if usingFFmpeg {
            ffmpegPlayer.seek(to: max(0, ffmpegPlayer.currentTime + seconds))
        } else if let item = player.currentItem, item.duration.seconds.isFinite {
            let target = min(max(0, player.currentTime().seconds + seconds), item.duration.seconds)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func adjustVolume(by delta: Float) {
        if usingFFmpeg {
            ffmpegPlayer.setVolume(ffmpegPlayer.currentVolume + delta)
        } else {
            player.volume = max(0, min(1, player.volume + delta))
        }
    }

    // MARK: 打开 / 播放

    func openFiles(_ urls: [URL]) {
        let videos = urls.filter { $0.isFileURL && Self.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !videos.isEmpty else { return }
        playlist = videos
        playlistTableView.reloadData()
        playItem(at: 0)
        RecentManager.shared.add(videos)
        // 多个文件时自动展开播放列表
        if videos.count > 1 {
            showSidebar()
        }
        updateControlsVisibility()
    }

    /// 保存当前播放进度（切换/退出前调用）
    func saveResumePosition() {
        guard playlist.indices.contains(currentIndex) else { return }
        let url = playlist[currentIndex]
        guard url.isFileURL else { return }
        let time: Double
        if usingFFmpeg {
            time = ffmpegPlayer.currentTime
        } else {
            time = player.currentTime().seconds
        }
        if time.isFinite && time > 1 {
            RecentManager.shared.setResumePosition(time, for: url)
        }
    }

    func playItem(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        saveResumePosition()
        currentIndex = index
        let url = playlist[index]

        switchToAVKit()
        updateControlsVisibility()
        showControls()

        playlistTableView.reloadData()
        playlistTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)

        // 根据偏好设置选择解码后端
        if Settings.shared.backend == .ffmpeg {
            playWithFFmpeg(url: url)
            return
        }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        registerEndObserver(for: item)

        // 观察状态：自动模式下，AVPlayer 无法解码则回退到 FFmpeg 软解；强制 AVKit 失败时给出提示
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            NSLog("[AV] 状态变化 status=%ld url=%@", item.status.rawValue, url.lastPathComponent)
            if item.status == .failed && Settings.shared.backend == .auto {
                DispatchQueue.main.async {
                    self?.handleAVFailure(url: url)
                }
            } else if item.status == .failed && Settings.shared.backend == .avkit {
                DispatchQueue.main.async {
                    guard let self, self.playlist.indices.contains(self.currentIndex), self.playlist[self.currentIndex] == url else { return }
                    let alert = NSAlert()
                    alert.messageText = "播放失败"
                    alert.informativeText = "无法解码「\(url.lastPathComponent)」。可尝试在偏好设置中切换到「自动」或 FFmpeg 软解。"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            } else if item.status == .readyToPlay {
                DispatchQueue.main.async {
                    self?.applyStoredAudioTrack(url: url, item: item)
                }
            }
        }

        // 观察视频尺寸，用于窗口适配
        presentationSizeObserver?.invalidate()
        presentationSizeObserver = item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
            let size = item.presentationSize
            if size.width > 0 && size.height > 0 {
                DispatchQueue.main.async {
                    self?.fitWindowToVideo(size)
                }
            }
        }

        if Settings.shared.autoPlay {
            avkitPlay()
        } else if #available(macOS 12.0, *) {
            // 不自动播放时也记录倍速，手动播放时生效
            player.defaultRate = currentSpeed
        }

        // 恢复上次播放位置（仅本地文件）
        if url.isFileURL, let resume = RecentManager.shared.resumePosition(for: url), resume > 5 {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }

        updateTitle()
        if Settings.shared.autoLoadSubtitle {
            autoLoadSidecarSubtitle(for: url)
        } else {
            clearSubtitles()
        }
    }

    @objc func playNext() {
        let next = currentIndex + 1
        if playlist.indices.contains(next) { playItem(at: next) }
    }

    @objc func playPrevious() {
        let prev = currentIndex - 1
        if playlist.indices.contains(prev) { playItem(at: prev) }
    }

    // MARK: FFmpeg 后端切换

    private func switchToAVKit() {
        guard usingFFmpeg else { return }
        ffmpegPlayer.stop()
        player.volume = ffmpegPlayer.currentVolume
        usingFFmpeg = false
        ffmpegSubtitleTimer?.invalidate()
        ffmpegSubtitleTimer = nil
        ffmpegView.isHidden = true
        playerLayerView.isHidden = false
    }

    private func handleAVFailure(url: URL) {
        guard playlist.indices.contains(currentIndex), playlist[currentIndex] == url else { return }
        NSLog("[FFmpeg] AVPlayer 无法解码，自动回退软解: %@", url.lastPathComponent)
        playWithFFmpeg(url: url)
    }

    private func playWithFFmpeg(url: URL) {
        NSLog("[FFmpeg] 软解播放: %@", url.lastPathComponent)
        usingFFmpeg = true
        player.pause()
        playerLayerView.isHidden = true
        ffmpegView.isHidden = false
        ffmpegPlayer.videoLayer.frame = ffmpegView.bounds
        ffmpegPlayer.setVolume(player.volume)
        ffmpegPlayer.open(url: url)
        ffmpegPlayer.play()
        if currentSpeed != 1.0 {
            ffmpegPlayer.setRate(Double(currentSpeed))
        }
        updateTitle()
        if Settings.shared.autoLoadSubtitle {
            autoLoadSidecarSubtitle(for: url)
        } else {
            clearSubtitles()
        }
        embeddedSubtitleSelection = nil

        // 音轨记忆：恢复上次选择的音轨
        if let ord = RecentManager.shared.audioTrackOrdinal(for: url) {
            ffmpegPlayer.selectAudioStream(ordinal: ord)
        }

        // 内嵌字幕提取完成后：优先恢复记忆的字幕轨，否则自动选第一条
        ffmpegPlayer.onSubtitlesReady = { [weak self] in
            guard let self, self.usingFFmpeg else { return }
            if self.subtitleCues.isEmpty {
                if RecentManager.shared.isSubtitleDisabled(for: url) { return }
                let streams = self.ffmpegPlayer.subtitleStreams
                if let ord = RecentManager.shared.subtitleTrackOrdinal(for: url), streams.indices.contains(ord) {
                    self.selectEmbeddedSubtitle(streamIndex: streams[ord].index)
                } else if let first = streams.first {
                    self.selectEmbeddedSubtitle(streamIndex: first.index)
                }
            }
        }

        // 恢复上次播放位置（仅本地文件）
        if url.isFileURL, let resume = RecentManager.shared.resumePosition(for: url), resume > 5 {
            ffmpegPlayer.seek(to: resume)
        }

        ffmpegSubtitleTimer?.invalidate()
        ffmpegSubtitleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.usingFFmpeg else { return }
            let t = self.ffmpegPlayer.currentTime
            self.updateSubtitleLabel(time: CMTime(seconds: t, preferredTimescale: 600))
            self.checkABLoop(time: t)
        }
    }

    @objc func forceFFmpegPlayback() {
        guard playlist.indices.contains(currentIndex) else { return }
        playWithFFmpeg(url: playlist[currentIndex])
    }

    private func showFFmpegError(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = "播放失败"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func registerEndObserver(for item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }
    }

    private func handlePlaybackEnded() {
        if Settings.shared.loopPlayback {
            playItem(at: currentIndex)
        } else {
            playNext()
        }
    }

    @objc func togglePlayPause() {
        if usingFFmpeg {
            if ffmpegPlayer.isPaused { ffmpegPlayer.play() } else { ffmpegPlayer.pause() }
        } else {
            if player.rate == 0 { avkitPlay() } else { player.pause() }
        }
        showControls()
    }

    // MARK: 统一播放接口（控制条使用，按后端分发）

    var unifiedCurrentTime: Double {
        usingFFmpeg ? ffmpegPlayer.currentTime : player.currentTime().seconds
    }

    var unifiedDuration: Double {
        if usingFFmpeg {
            return ffmpegPlayer.duration
        }
        guard let d = player.currentItem?.duration.seconds, d.isFinite else { return 0 }
        return d
    }

    var unifiedPaused: Bool {
        usingFFmpeg ? ffmpegPlayer.isPaused : player.rate == 0
    }

    var unifiedVolume: Float {
        usingFFmpeg ? ffmpegPlayer.currentVolume : player.volume
    }

    var playbackSpeed: Float { currentSpeed }

    /// 章节在时间轴上的位置（0~1，供控制条绘制刻度）
    var chapterRatios: [CGFloat] {
        let d = unifiedDuration
        guard d > 0 else { return [] }
        return chapterList.compactMap { ch in
            ch.start > 0 && ch.start < d ? CGFloat(ch.start / d) : nil
        }
    }

    func unifiedSeek(to seconds: Double) {
        if usingFFmpeg {
            ffmpegPlayer.seek(to: seconds)
        } else if let item = player.currentItem, item.duration.seconds.isFinite {
            let target = max(0, min(seconds, item.duration.seconds))
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func unifiedSetVolume(_ volume: Float) {
        let v = max(0, min(1, volume))
        if usingFFmpeg {
            ffmpegPlayer.setVolume(v)
        } else {
            player.volume = v
        }
    }

    @objc func toggleFullScreen() {
        if miniMode { exitMiniMode() }
        view.window?.toggleFullScreen(nil)
    }

    // MARK: 播放控制（右键菜单 / 设置）

    @objc func setPlaybackSpeed(_ sender: NSMenuItem) {
        let speed = sender.representedObject as? Float ?? 1.0
        currentSpeed = speed
        Settings.shared.playbackSpeed = Double(speed)
        if usingFFmpeg {
            ffmpegPlayer.setRate(Double(speed))
        } else {
            if #available(macOS 12.0, *) {
                player.defaultRate = speed
            }
            if player.rate != 0 { player.rate = speed }
        }
        flashStatus("播放速度：" + (speed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.1fx", speed) : String(format: "%gx", speed)))
    }

    @objc func toggleLoop() {
        Settings.shared.loopPlayback.toggle()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    @objc func toggleAlwaysOnTop() {
        Settings.shared.alwaysOnTop.toggle()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    @objc func openDocument() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择视频文件"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK else { return }
            self?.handleURLs(panel.urls)
        }
    }

    @objc func openFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择包含视频的文件夹"
        panel.prompt = "打开文件夹"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let dir = panel.url else { return }
            self?.openFolderContents(dir)
        }
    }

    func openFolderContents(_ dir: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            let alert = NSAlert()
            alert.messageText = "无法访问文件夹"
            alert.informativeText = "没有读取「\(dir.lastPathComponent)」的权限，请在 系统设置 → 隐私与安全性 中授权。"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        var videos: [URL] = []
        for case let fileURL as URL in enumerator {
            if Self.videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                videos.append(fileURL)
            }
        }
        // 自然排序：第2集 < 第10集
        videos.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !videos.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "未找到视频"
            alert.informativeText = "该文件夹（含子文件夹）中没有找到支持的视频文件。"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        openFiles(videos)
    }

    // MARK: 打开流媒体 URL（⌘U）

    @objc func openURLSheet() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "打开流媒体 URL"
        alert.informativeText = "支持 http(s)（HLS 等）、rtsp、rtmp 流"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        tf.placeholderString = "https://example.com/stream.m3u8"
        alert.accessoryView = tf
        alert.addButton(withTitle: "播放")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = tf
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            self?.openStreamURL(tf.stringValue)
        }
    }

    private func openStreamURL(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s),
              let scheme = u.scheme?.lowercased(),
              ["http", "https", "rtsp", "rtmp", "udp"].contains(scheme) else {
            flashStatus("无效的流媒体 URL")
            return
        }
        playlist.append(u)
        playlistTableView.reloadData()
        updateControlsVisibility()
        playItem(at: playlist.count - 1)
    }

    @objc func openPreferences() {
        PreferenceWindowController.shared.show()
    }

    // MARK: 拖拽 / 打开面板统一入口

    func handleURLs(_ urls: [URL]) {
        var videos: [URL] = []
        var subs: [URL] = []
        for u in urls {
            let ext = u.pathExtension.lowercased()
            if Self.videoExtensions.contains(ext) {
                videos.append(u)
            } else if ext == "srt" || ext == "vtt" {
                subs.append(u)
            }
        }
        if !videos.isEmpty {
            openFiles(videos)
        }
        if let s = subs.first {
            loadSubtitleFile(s)
        }
    }

    // MARK: 字幕

    @objc func promptOpenSubtitle() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择字幕文件（.srt / .vtt）"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.loadSubtitleFile(url)
        }
    }

    private func loadSubtitleFile(_ url: URL) {
        let cues = SubtitleParser.load(url: url)
        if cues.isEmpty {
            let alert = NSAlert()
            alert.messageText = "无法加载字幕"
            alert.informativeText = "未能解析该字幕文件：\(url.lastPathComponent)"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        subtitleCues = cues
        subtitleLabel.attributedStringValue = NSAttributedString()
        if playlist.indices.contains(currentIndex) {
            RecentManager.shared.setSubtitleDisabled(false, for: playlist[currentIndex])
        }
    }

    private func clearSubtitles() {
        subtitleCues = []
        subtitleLabel.attributedStringValue = NSAttributedString()
    }

    /// 选择内嵌字幕流（FFmpeg 模式）；nil 表示关闭字幕
    func selectEmbeddedSubtitle(streamIndex: Int?) {
        if let idx = streamIndex {
            let cues = ffmpegPlayer.embeddedCues(for: idx)
            subtitleCues = cues
            embeddedSubtitleSelection = idx
        } else {
            subtitleCues = []
            embeddedSubtitleSelection = nil
        }
        subtitleLabel.attributedStringValue = NSAttributedString()
    }

    @objc func selectEmbeddedSubtitleFromMenu(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }
        selectEmbeddedSubtitle(streamIndex: idx)
        if let ord = ffmpegPlayer.subtitleStreams.firstIndex(where: { $0.index == idx }),
           playlist.indices.contains(currentIndex) {
            let url = playlist[currentIndex]
            RecentManager.shared.setSubtitleTrackOrdinal(ord, for: url)
            RecentManager.shared.setSubtitleDisabled(false, for: url)
        }
    }

    @objc func selectExternalSubtitle() {
        guard usingFFmpeg else { return }
        // 重新显示外挂字幕：重新加载当前文件同名字幕
        guard playlist.indices.contains(currentIndex) else { return }
        autoLoadSidecarSubtitle(for: playlist[currentIndex])
        embeddedSubtitleSelection = nil
        RecentManager.shared.setSubtitleDisabled(false, for: playlist[currentIndex])
    }

    @objc func disableSubtitles() {
        subtitleCues = []
        embeddedSubtitleSelection = nil
        subtitleLabel.attributedStringValue = NSAttributedString()
        if playlist.indices.contains(currentIndex) {
            RecentManager.shared.setSubtitleDisabled(true, for: playlist[currentIndex])
        }
    }

    /// 字幕同步微调（±0.5s，快捷键 G/H）
    private func adjustSubtitleOffset(_ delta: Double) {
        let s = Settings.shared
        let v = min(60, max(-60, s.subtitleOffset + delta))
        s.subtitleOffset = v
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        flashStatus(String(format: "字幕同步：%+.1f 秒", v))
    }

    @objc func resetSubtitleOffset() {
        Settings.shared.subtitleOffset = 0
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        flashStatus("字幕同步已重置")
    }

    // MARK: 音轨

    private func avAudioGroupAndOptions() -> (group: AVMediaSelectionGroup, options: [AVMediaSelectionOption])? {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              !group.options.isEmpty else { return nil }
        return (group, group.options)
    }

    private func audioOptionTitle(_ op: AVMediaSelectionOption) -> String {
        var t = op.displayName
        if let lang = op.extendedLanguageTag { t += "（\(lang)）" }
        return t
    }

    @objc func selectAudioTrackFromMenu(_ sender: NSMenuItem) {
        guard let ord = sender.representedObject as? Int, playlist.indices.contains(currentIndex) else { return }
        let url = playlist[currentIndex]
        RecentManager.shared.setAudioTrackOrdinal(ord, for: url)
        if usingFFmpeg {
            ffmpegPlayer.selectAudioStream(ordinal: ord)
        } else if let (group, options) = avAudioGroupAndOptions(), options.indices.contains(ord) {
            player.currentItem?.select(options[ord], in: group)
        }
    }

    private func applyStoredAudioTrack(url: URL, item: AVPlayerItem) {
        guard let ord = RecentManager.shared.audioTrackOrdinal(for: url),
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              group.options.indices.contains(ord) else { return }
        item.select(group.options[ord], in: group)
    }

    /// 音频延迟（仅 FFmpeg 软解模式生效；正值 = 音频更晚）
    @objc func adjustAudioDelay(_ sender: NSMenuItem) {
        guard let delta = sender.representedObject as? Double else { return }
        ffmpegPlayer.audioDelay += delta
        flashStatus(String(format: "音频延迟：%+.2f 秒", ffmpegPlayer.audioDelay))
    }

    @objc func resetAudioDelay() {
        ffmpegPlayer.audioDelay = 0
        flashStatus("音频延迟已重置")
    }

    // MARK: 章节

    var chapterList: [(start: Double, title: String)] {
        if usingFFmpeg {
            return ffmpegPlayer.chapters.map { ($0.start, $0.title) }
        }
        guard let item = player.currentItem else { return [] }
        let groups = item.asset.chapterMetadataGroups(withTitleLocale: Locale.current, containingItemsWithCommonKeys: [AVMetadataKey.commonKeyTitle])
        return groups.enumerated().compactMap { i, g in
            guard g.timeRange.start.seconds.isFinite else { return nil }
            let title = g.items.first?.stringValue ?? "章节 \(i + 1)"
            return (g.timeRange.start.seconds, title)
        }
    }

    @objc func jumpToChapter(_ sender: NSMenuItem) {
        guard let start = sender.representedObject as? Double else { return }
        unifiedSeek(to: start)
    }

    // MARK: A-B 循环

    @objc func setLoopPointA() {
        abLoopA = unifiedCurrentTime
        normalizeABLoop()
        if let b = abLoopB {
            flashStatus("A-B 循环：\(Self.formatDuration(abLoopA!)) → \(Self.formatDuration(b))")
        } else {
            flashStatus("A 点已设置：\(Self.formatDuration(abLoopA!))")
        }
    }

    @objc func setLoopPointB() {
        abLoopB = unifiedCurrentTime
        normalizeABLoop()
        if let a = abLoopA {
            flashStatus("A-B 循环：\(Self.formatDuration(a)) → \(Self.formatDuration(abLoopB!))")
        } else {
            flashStatus("B 点已设置：\(Self.formatDuration(abLoopB!))")
        }
    }

    @objc func clearABLoop() {
        abLoopA = nil
        abLoopB = nil
        flashStatus("A-B 循环已取消")
    }

    private func normalizeABLoop() {
        guard let a = abLoopA, let b = abLoopB, b < a else { return }
        abLoopA = b
        abLoopB = a
    }

    private func checkABLoop(time: Double) {
        guard let a = abLoopA, let b = abLoopB, b - a > 0.5, time >= b else { return }
        unifiedSeek(to: a)
    }

    // MARK: 画中画（macOS 12+，硬解模式）

    @objc func togglePictureInPicture() {
        guard !usingFFmpeg else {
            flashStatus("画中画仅在硬解模式下可用")
            return
        }
        if #available(macOS 12.0, *) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                flashStatus("当前系统不支持画中画")
                return
            }
            if let c = piPController, c.isPictureInPictureActive {
                c.stopPictureInPicture()
                return
            }
            guard playlist.indices.contains(currentIndex) else {
                flashStatus("请先播放视频")
                return
            }
            let source = AVPictureInPictureController.ContentSource(playerLayer: playerLayerView.playerLayer)
            let c = AVPictureInPictureController(contentSource: source)
            c.delegate = self
            piPController = c
            setControlsVisible(false)
            c.startPictureInPicture()
        } else {
            flashStatus("画中画需要 macOS 12 或更高版本")
        }
    }

    // MARK: 迷你模式（⌘M）

    @objc func toggleMiniMode() {
        if miniMode { exitMiniMode() } else { enterMiniMode() }
    }

    private func enterMiniMode() {
        guard let window = view.window, !miniMode else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        savedWindowFrame = window.frame
        hideSidebar()
        miniMode = true
        window.styleMask = [.borderless]
        window.isMovableByWindowBackground = true
        window.level = .floating
        let base = savedWindowFrame?.size ?? NSSize(width: 640, height: 360)
        let scale = min(360.0 / max(base.width, 1), 1.0)
        window.setContentSize(NSSize(
            width: max(base.width * scale, 320),
            height: max(base.height * scale, 180)))
        window.center()
        setControlsVisible(false)
    }

    private func exitMiniMode() {
        guard let window = view.window, miniMode else { return }
        miniMode = false
        window.isMovableByWindowBackground = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.level = Settings.shared.alwaysOnTop ? .floating : .normal
        if let f = savedWindowFrame {
            window.setFrame(f, display: true)
        }
        savedWindowFrame = nil
        window.makeKeyAndOrderFront(nil)
        showControls()
    }

    // MARK: 截图（⌘S）

    @objc func takeSnapshot() {
        guard playlist.indices.contains(currentIndex) else {
            flashStatus("请先打开视频")
            return
        }
        if usingFFmpeg {
            guard let pb = ffmpegPlayer.lastPixelBuffer, let cg = cgImage(fromPixelBuffer: pb) else {
                flashStatus("当前没有可截取的画面")
                return
            }
            presentSnapshotSave(cgImage: cg)
        } else {
            guard let item = player.currentItem else { return }
            let time = player.currentTime()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let gen = AVAssetImageGenerator(asset: item.asset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                var actual = CMTime.zero
                var cg: CGImage?
                do { cg = try gen.copyCGImage(at: time, actualTime: &actual) } catch { cg = nil }
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let cg else {
                        self.flashStatus("截图失败")
                        return
                    }
                    self.presentSnapshotSave(cgImage: cg)
                }
            }
        }
    }

    private func cgImage(fromPixelBuffer pb: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        return ctx.createCGImage(ci, from: ci.extent)
    }

    private func presentSnapshotSave(cgImage cg: CGImage) {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let base = playlist[currentIndex].deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(base)-\(Self.timeStampString()).png"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                self?.flashStatus("截图保存失败")
                return
            }
            do {
                try data.write(to: url)
                self?.flashStatus("已保存截图：\(url.lastPathComponent)")
            } catch {
                self?.flashStatus("截图保存失败")
            }
        }
    }

    private static func timeStampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f.string(from: Date())
    }

    // MARK: 媒体信息（⌘I）

    @objc func showMediaInfo() {
        guard playlist.indices.contains(currentIndex) else {
            flashStatus("请先打开视频")
            return
        }
        let lines: [String]
        if usingFFmpeg {
            lines = ffmpegPlayer.mediaInfoLines
        } else {
            lines = avkitMediaInfo()
        }
        guard !lines.isEmpty else {
            flashStatus("无法获取媒体信息")
            return
        }
        let alert = NSAlert()
        alert.messageText = "媒体信息"
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func avkitMediaInfo() -> [String] {
        guard let item = player.currentItem else { return [] }
        var lines: [String] = []
        let d = item.duration.seconds
        if d.isFinite && d > 0 {
            lines.append("时长：\(Self.formatDuration(d))")
        }
        for t in item.asset.tracks(withMediaType: .video) {
            let size = t.naturalSize
            var codec = "未知"
            if let first = t.formatDescriptions.first {
                let desc = first as! CMFormatDescription
                codec = Self.fourCCString(CMFormatDescriptionGetMediaSubType(desc))
            }
            lines.append("视频：\(codec)，\(Int(size.width))×\(Int(size.height))，\(String(format: "%.2f", t.nominalFrameRate)) fps")
        }
        for t in item.asset.tracks(withMediaType: .audio) {
            var sr = 0
            var ch = 0
            var codec = "未知"
            if let first = t.formatDescriptions.first {
                let desc = first as! CMFormatDescription
                codec = Self.fourCCString(CMFormatDescriptionGetMediaSubType(desc))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    sr = Int(asbd.pointee.mSampleRate)
                    ch = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
            lines.append("音频：\(codec)，\(sr) Hz，\(ch) 声道")
        }
        return lines
    }

    private static func fourCCString(_ code: OSType) -> String {
        let c = code.bigEndian
        let bytes: [UInt8] = [
            UInt8((c >> 24) & 0xFF), UInt8((c >> 16) & 0xFF),
            UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF),
        ]
        if let s = String(bytes: bytes, encoding: .utf8), !s.isEmpty {
            return s
        }
        return String(format: "0x%08X", code)
    }

    static func formatDuration(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    // MARK: 字幕渲染

    private func autoLoadSidecarSubtitle(for videoURL: URL) {
        clearSubtitles()
        guard videoURL.isFileURL else { return }
        let dir = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for f in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let ext = f.pathExtension.lowercased()
            guard ext == "srt" || ext == "vtt" else { continue }
            let name = f.deletingPathExtension().lastPathComponent
            // 匹配 同名.srt 或 同名.zh.srt / 同名.chs.srt 等常见命名
            if name == base || name.hasPrefix(base + ".") {
                let cues = SubtitleParser.load(url: f)
                if !cues.isEmpty { subtitleCues = cues; break }
            }
        }
    }

    private func updateSubtitleLabel(time: CMTime) {
        guard !subtitleCues.isEmpty else { return }
        let secs = time.seconds + Settings.shared.subtitleOffset
        var shown: String? = nil
        for cue in subtitleCues {
            if secs >= cue.start && secs < cue.end { shown = cue.text; break }
        }
        subtitleLabel.attributedStringValue = makeSubtitleAttributed(shown ?? "")
    }

    private func makeSubtitleAttributed(_ text: String) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString() }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(Settings.shared.subtitleFontSize), weight: .medium),
            .foregroundColor: Settings.shared.subtitleColor.color,
            .strokeColor: NSColor.black,
            .strokeWidth: -3.0,
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    private func updateTitle() {
        guard playlist.indices.contains(currentIndex) else { return }
        let name = displayName(of: playlist[currentIndex])
        if playlist.count > 1 {
            view.window?.title = "\(name)  （\(currentIndex + 1)/\(playlist.count)）"
        } else {
            view.window?.title = name
        }
        hintLabel.isHidden = true
        updateNowPlayingInfo()
    }

    // MARK: 窗口适配

    /// 打开视频后让窗口适配视频尺寸（不超过屏幕 80%）
    func fitWindowToVideo(_ videoSize: CGSize) {
        guard Settings.shared.fitWindowToVideo, !miniMode else { return }
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        guard videoSize.width > 0, videoSize.height > 0 else { return }
        let visible = screen.visibleFrame
        let maxW = visible.width * 0.8
        let maxH = visible.height * 0.8
        let sidebarExtra: CGFloat = sidebarVisible ? 230 : 0
        let scale = min(maxW / (videoSize.width + sidebarExtra), maxH / videoSize.height, 1.5)
        var content = NSSize(
            width: videoSize.width * scale + sidebarExtra,
            height: videoSize.height * scale)
        content.width = min(content.width, visible.width * 0.95)
        content.height = min(content.height, visible.height * 0.95)
        window.setContentSize(content)
        window.center()
    }
}

// MARK: - 画中画代理

extension PlayerViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        piPController = nil
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        piPController = nil
        flashStatus("画中画启动失败")
    }
}

// MARK: - 右键菜单

extension PlayerViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === view.menu else { return }
        menu.removeAllItems()

        let open = NSMenuItem(title: "打开文件…", action: #selector(openDocument), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let folder = NSMenuItem(title: "打开文件夹…", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        let urlItem = NSMenuItem(title: "打开流媒体 URL…", action: #selector(openURLSheet), keyEquivalent: "")
        urlItem.target = self
        menu.addItem(urlItem)
        menu.addItem(.separator())

        // 字幕
        let subItem = NSMenuItem(title: "字幕", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        let noneItem = NSMenuItem(title: "关闭字幕", action: #selector(disableSubtitles), keyEquivalent: "")
        noneItem.target = self
        noneItem.state = subtitleCues.isEmpty ? .on : .off
        subMenu.addItem(noneItem)
        let extItem = NSMenuItem(title: "外挂字幕", action: #selector(selectExternalSubtitle), keyEquivalent: "")
        extItem.target = self
        extItem.state = (!subtitleCues.isEmpty && embeddedSubtitleSelection == nil) ? .on : .off
        subMenu.addItem(extItem)
        if usingFFmpeg {
            let streams = ffmpegPlayer.subtitleStreams
            if streams.isEmpty {
                let noEmbed = NSMenuItem(title: "（无内嵌字幕）", action: nil, keyEquivalent: "")
                noEmbed.isEnabled = false
                subMenu.addItem(noEmbed)
            } else {
                for (i, st) in streams.enumerated() {
                    let title = st.language.isEmpty ? "内嵌字幕 \(i + 1)" : "内嵌字幕 \(i + 1)（\(st.language)）"
                    let it = NSMenuItem(title: title, action: #selector(selectEmbeddedSubtitleFromMenu(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = st.index
                    it.state = embeddedSubtitleSelection == st.index ? .on : .off
                    subMenu.addItem(it)
                }
            }
        } else {
            let sysItem = NSMenuItem(title: "内嵌字幕由系统渲染", action: nil, keyEquivalent: "")
            sysItem.isEnabled = false
            subMenu.addItem(sysItem)
        }
        subMenu.addItem(.separator())
        let loadSub = NSMenuItem(title: "加载字幕文件…", action: #selector(promptOpenSubtitle), keyEquivalent: "")
        loadSub.target = self
        subMenu.addItem(loadSub)
        subMenu.addItem(.separator())
        let syncLabel = NSMenuItem(title: String(format: "字幕同步：%+.1f 秒", Settings.shared.subtitleOffset), action: nil, keyEquivalent: "")
        syncLabel.isEnabled = false
        subMenu.addItem(syncLabel)
        let subEarlier = NSMenuItem(title: "字幕提前 0.5 秒（G）", action: #selector(subtitleOffsetAction(_:)), keyEquivalent: "")
        subEarlier.target = self
        subEarlier.representedObject = -0.5
        subMenu.addItem(subEarlier)
        let subLater = NSMenuItem(title: "字幕延后 0.5 秒（H）", action: #selector(subtitleOffsetAction(_:)), keyEquivalent: "")
        subLater.target = self
        subLater.representedObject = 0.5
        subMenu.addItem(subLater)
        let subReset = NSMenuItem(title: "重置字幕同步", action: #selector(resetSubtitleOffset), keyEquivalent: "")
        subReset.target = self
        subMenu.addItem(subReset)
        subItem.submenu = subMenu
        menu.addItem(subItem)

        // 音轨
        let audioItem = NSMenuItem(title: "音轨", action: nil, keyEquivalent: "")
        let audioMenu = NSMenu()
        if usingFFmpeg {
            let list = ffmpegPlayer.audioStreams
            if list.isEmpty {
                let noAudio = NSMenuItem(title: "（无音轨）", action: nil, keyEquivalent: "")
                noAudio.isEnabled = false
                audioMenu.addItem(noAudio)
            } else {
                for (i, st) in list.enumerated() {
                    let title = st.language.isEmpty ? "音轨 \(i + 1)" : "音轨 \(i + 1)（\(st.language)）"
                    let it = NSMenuItem(title: title, action: #selector(selectAudioTrackFromMenu(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = i
                    it.state = ffmpegPlayer.currentAudioIndex == st.index ? .on : .off
                    audioMenu.addItem(it)
                }
                audioMenu.addItem(.separator())
                let delayLabel = NSMenuItem(title: String(format: "音频延迟：%+.2f 秒", ffmpegPlayer.audioDelay), action: nil, keyEquivalent: "")
                delayLabel.isEnabled = false
                audioMenu.addItem(delayLabel)
                let ad1 = NSMenuItem(title: "音频延迟 +100ms", action: #selector(adjustAudioDelay(_:)), keyEquivalent: "")
                ad1.target = self
                ad1.representedObject = 0.1
                audioMenu.addItem(ad1)
                let ad2 = NSMenuItem(title: "音频延迟 −100ms", action: #selector(adjustAudioDelay(_:)), keyEquivalent: "")
                ad2.target = self
                ad2.representedObject = -0.1
                audioMenu.addItem(ad2)
                let ad0 = NSMenuItem(title: "重置音频延迟", action: #selector(resetAudioDelay), keyEquivalent: "")
                ad0.target = self
                audioMenu.addItem(ad0)
            }
        } else {
            if let (group, options) = avAudioGroupAndOptions() {
                for (i, op) in options.enumerated() {
                    let it = NSMenuItem(title: audioOptionTitle(op), action: #selector(selectAudioTrackFromMenu(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = i
                    it.state = player.currentItem?.selectedMediaOption(in: group) == op ? .on : .off
                    audioMenu.addItem(it)
                }
            } else {
                let noAudio = NSMenuItem(title: "（无音轨）", action: nil, keyEquivalent: "")
                noAudio.isEnabled = false
                audioMenu.addItem(noAudio)
            }
        }
        audioItem.submenu = audioMenu
        menu.addItem(audioItem)

        // 章节
        let chapters = chapterList
        if !chapters.isEmpty {
            let chItem = NSMenuItem(title: "章节", action: nil, keyEquivalent: "")
            let chMenu = NSMenu()
            for (i, ch) in chapters.enumerated() {
                let it = NSMenuItem(title: "\(i + 1). \(ch.title)", action: #selector(jumpToChapter(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = ch.start
                chMenu.addItem(it)
            }
            chItem.submenu = chMenu
            menu.addItem(chItem)
        }

        menu.addItem(.separator())

        let playing = usingFFmpeg ? !ffmpegPlayer.isPaused : player.rate != 0
        let pp = NSMenuItem(title: playing ? "暂停" : "播放", action: #selector(togglePlayPause), keyEquivalent: "")
        pp.target = self
        menu.addItem(pp)
        let prev = NSMenuItem(title: "上一个", action: #selector(playPrevious), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)
        let next = NSMenuItem(title: "下一个", action: #selector(playNext), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        menu.addItem(.separator())

        let speedItem = NSMenuItem(title: "播放速度", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
        for s in speeds {
            let it = NSMenuItem(title: s == 1.0 ? "1.0x（正常）" : "\(s)x", action: #selector(setPlaybackSpeed(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s
            it.state = abs(currentSpeed - s) < 0.01 ? .on : .off
            speedMenu.addItem(it)
        }
        speedItem.submenu = speedMenu
        menu.addItem(speedItem)

        let loop = NSMenuItem(title: "循环播放", action: #selector(toggleLoop), keyEquivalent: "")
        loop.target = self
        loop.state = Settings.shared.loopPlayback ? .on : .off
        menu.addItem(loop)

        // A-B 循环
        let abItem = NSMenuItem(title: "A-B 循环", action: nil, keyEquivalent: "")
        let abMenu = NSMenu()
        let setA = NSMenuItem(title: "设置 A 点（A 键）", action: #selector(setLoopPointA), keyEquivalent: "")
        setA.target = self
        abMenu.addItem(setA)
        let setB = NSMenuItem(title: "设置 B 点（B 键）", action: #selector(setLoopPointB), keyEquivalent: "")
        setB.target = self
        abMenu.addItem(setB)
        let clearAB = NSMenuItem(title: "取消 A-B 循环", action: #selector(clearABLoop), keyEquivalent: "")
        clearAB.target = self
        clearAB.state = (abLoopA != nil && abLoopB != nil) ? .on : .off
        abMenu.addItem(clearAB)
        abItem.submenu = abMenu
        menu.addItem(abItem)

        let top = NSMenuItem(title: "窗口置顶", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        top.target = self
        top.state = Settings.shared.alwaysOnTop ? .on : .off
        menu.addItem(top)

        let sidebar = NSMenuItem(title: sidebarVisible ? "隐藏播放列表" : "显示播放列表", action: #selector(toggleSidebar), keyEquivalent: "")
        sidebar.target = self
        menu.addItem(sidebar)

        let mini = NSMenuItem(title: miniMode ? "退出迷你模式" : "迷你模式", action: #selector(toggleMiniMode), keyEquivalent: "")
        mini.target = self
        menu.addItem(mini)

        let remove = NSMenuItem(title: "从播放列表移除", action: #selector(removeSelectedFromPlaylist), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = playlistTableView.selectedRow >= 0
        menu.addItem(remove)

        menu.addItem(.separator())

        let ff = NSMenuItem(title: "用 FFmpeg 软解播放", action: #selector(forceFFmpegPlayback), keyEquivalent: "")
        ff.target = self
        menu.addItem(ff)

        menu.addItem(.separator())

        let snap = NSMenuItem(title: "存储截图…", action: #selector(takeSnapshot), keyEquivalent: "")
        snap.target = self
        menu.addItem(snap)
        let info = NSMenuItem(title: "媒体信息", action: #selector(showMediaInfo), keyEquivalent: "")
        info.target = self
        menu.addItem(info)
        let pip = NSMenuItem(title: "画中画", action: #selector(togglePictureInPicture), keyEquivalent: "")
        pip.target = self
        menu.addItem(pip)

        menu.addItem(.separator())

        let full = NSMenuItem(title: "进入/退出全屏", action: #selector(toggleFullScreen), keyEquivalent: "")
        full.target = self
        menu.addItem(full)

        let prefs = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)
    }

    @objc private func subtitleOffsetAction(_ sender: NSMenuItem) {
        guard let delta = sender.representedObject as? Double else { return }
        adjustSubtitleOffset(delta)
    }
}

// MARK: - 播放列表数据源

extension PlayerViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return playlist.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard playlist.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("playlistCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingMiddle
            cell.textField = tf
            cell.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = displayName(of: playlist[row])
        cell.textField?.textColor = row == currentIndex ? .controlAccentColor : .labelColor
        cell.textField?.font = NSFont.systemFont(ofSize: 12, weight: row == currentIndex ? .semibold : .regular)
        return cell
    }

    // 拖拽：外部文件追加 / 内部行排序
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: Self.playlistRowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingPasteboard.types?.contains(Self.playlistRowType) == true {
            return dropOperation == .above ? .move : .move
        }
        return info.draggingPasteboard.types?.contains(.fileURL) == true ? .copy : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // 内部行拖拽 → 排序
        if let src = info.draggingPasteboard.string(forType: Self.playlistRowType).flatMap(Int.init) {
            movePlaylistItem(from: src, to: row)
            return true
        }
        // 外部文件 → 追加
        guard let objs = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }
        appendToPlaylist(objs)
        return true
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var playerVC: PlayerViewController!
    private var recentSubmenu: NSMenu!
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        playerVC = PlayerViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "视频播放器"
        window.center()
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = playerVC
        window.isReleasedWhenClosed = false
        window.level = Settings.shared.alwaysOnTop ? .floating : .normal
        window.setFrameAutosaveName("VideoPlayerMainWindow")  // 自动记忆窗口位置与大小

        buildMainMenu()
        // Sparkle 自动更新：自动在应用菜单加入「检查更新…」
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if Settings.shared.openFullscreen {
            window.toggleFullScreen(nil)
        }

        // 支持命令行直接传入文件路径
        let files = CommandLine.arguments.dropFirst()
            .filter { FileManager.default.fileExists(atPath: $0) }
        if !files.isEmpty {
            playerVC.openFiles(files.map { URL(fileURLWithPath: $0) })
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildRecentMenu), name: .recentChanged, object: nil)

        // 调试：--snapshot <路径> 自截图后退出（无屏幕录制权限时分析 UI 用）
        if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(idx + 1) {
            let path = CommandLine.arguments[idx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let view = self.window.contentView else { return }
                func dumpView(_ v: NSView, _ depth: Int) {
                    let ind = String(repeating: "  ", count: depth)
                    print("\(ind)\(type(of: v)) hidden=\(v.isHidden) frame=\(NSStringFromRect(v.frame))")
                    for s in v.subviews { dumpView(s, depth + 1) }
                }
                print("=== 视图层级 ===")
                dumpView(view, 0)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                        print("快照已保存: \(path)")
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        playerVC.saveResumePosition()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerVC.saveResumePosition()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        playerVC?.handleURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: 菜单

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 视频播放器", action: #selector(showAbout), keyEquivalent: "")
        let prefs = appMenu.addItem(withTitle: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 视频播放器", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 视频播放器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 文件菜单
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        let open = fileMenu.addItem(withTitle: "打开…", action: #selector(openDocument), keyEquivalent: "o")
        open.target = self
        let openFolderItem = fileMenu.addItem(withTitle: "打开文件夹…", action: #selector(openFolderAction), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command, .option]
        openFolderItem.target = self
        let openURL = fileMenu.addItem(withTitle: "打开流媒体 URL…", action: #selector(openURLAction), keyEquivalent: "u")
        openURL.target = self
        let recent = fileMenu.addItem(withTitle: "打开最近", action: nil, keyEquivalent: "")
        recentSubmenu = NSMenu()
        recent.submenu = recentSubmenu
        rebuildRecentMenu()
        let openSub = fileMenu.addItem(withTitle: "加载字幕…", action: #selector(openSubtitle), keyEquivalent: "o")
        openSub.keyEquivalentModifierMask = [.command, .shift]
        openSub.target = self
        fileMenu.addItem(.separator())
        let snap = fileMenu.addItem(withTitle: "存储截图…", action: #selector(snapshotAction), keyEquivalent: "s")
        snap.target = self
        let info = fileMenu.addItem(withTitle: "媒体信息", action: #selector(mediaInfoAction), keyEquivalent: "i")
        info.target = self
        fileMenu.addItem(.separator())
        let close = fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = nil
        fileMenuItem.submenu = fileMenu

        // 播放菜单
        let playMenuItem = NSMenuItem()
        mainMenu.addItem(playMenuItem)
        let playMenu = NSMenu(title: "播放")
        let playPause = playMenu.addItem(withTitle: "播放/暂停", action: #selector(PlayerViewController.togglePlayPause), keyEquivalent: " ")
        playPause.target = playerVC
        let next = playMenu.addItem(withTitle: "下一个", action: #selector(PlayerViewController.playNext), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        next.target = playerVC
        next.keyEquivalentModifierMask = [.command]
        let prev = playMenu.addItem(withTitle: "上一个", action: #selector(PlayerViewController.playPrevious), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prev.target = playerVC
        prev.keyEquivalentModifierMask = [.command]
        playMenu.addItem(.separator())
        let ffmpeg = playMenu.addItem(withTitle: "用 FFmpeg 软解播放当前文件", action: #selector(PlayerViewController.forceFFmpegPlayback), keyEquivalent: "r")
        ffmpeg.target = playerVC
        ffmpeg.keyEquivalentModifierMask = [.command, .option]
        playMenuItem.submenu = playMenu

        // 显示菜单
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        let full = viewMenu.addItem(withTitle: "进入全屏", action: #selector(PlayerViewController.toggleFullScreen), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        full.target = playerVC
        let sidebarItem = viewMenu.addItem(withTitle: "显示播放列表", action: #selector(toggleSidebarAction), keyEquivalent: "l")
        sidebarItem.keyEquivalentModifierMask = [.command, .shift]
        sidebarItem.target = self
        let mini = viewMenu.addItem(withTitle: "迷你模式", action: #selector(miniModeAction), keyEquivalent: "m")
        mini.target = self
        let pip = viewMenu.addItem(withTitle: "画中画", action: #selector(pipAction), keyEquivalent: "")
        pip.target = self
        viewMenuItem.submenu = viewMenu

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openDocument() {
        playerVC.openDocument()
    }

    @objc private func openSubtitle() {
        playerVC.promptOpenSubtitle()
    }

    @objc private func openFolderAction() {
        playerVC.openFolder()
    }

    @objc private func openURLAction() {
        playerVC.openURLSheet()
    }

    @objc private func snapshotAction() {
        playerVC.takeSnapshot()
    }

    @objc private func mediaInfoAction() {
        playerVC.showMediaInfo()
    }

    @objc private func miniModeAction() {
        playerVC.toggleMiniMode()
    }

    @objc private func pipAction() {
        playerVC.togglePictureInPicture()
    }

    @objc private func toggleSidebarAction() {
        playerVC.toggleSidebar()
    }

    @objc private func rebuildRecentMenu() {
        guard recentSubmenu != nil else { return }
        recentSubmenu.removeAllItems()
        let items = RecentManager.shared.recent
        if items.isEmpty {
            let empty = NSMenuItem(title: "无最近记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentSubmenu.addItem(empty)
        } else {
            for (i, url) in items.enumerated() {
                var title = "\(i + 1). \(url.lastPathComponent)"
                // 显示上次播放进度
                if let pos = RecentManager.shared.resumePosition(for: url), pos > 5 {
                    title += "  ·  \(RecentManager.formatTime(pos))"
                }
                let it = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = url.path
                recentSubmenu.addItem(it)
            }
            recentSubmenu.addItem(.separator())
            let clear = NSMenuItem(title: "清除记录", action: #selector(clearRecent), keyEquivalent: "")
            clear.target = self
            recentSubmenu.addItem(clear)
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        playerVC.openFiles([URL(fileURLWithPath: path)])
    }

    @objc private func clearRecent() {
        RecentManager.shared.clear()
    }

    @objc private func openPreferences() {
        PreferenceWindowController.shared.show()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "视频播放器 \(version)"
        alert.informativeText = "一个轻量的原生 macOS 视频播放器\n\n· AVFoundation 硬件解码（默认，省电）\n· FFmpeg 软解兜底（通吃几乎所有格式）\n· 无法播放时自动切换软解，也可 ⌥⌘R 手动切换\n· 右键菜单：常用操作 · 偏好设置：解码后端/字幕/窗口\n\n快捷键：空格 播放/暂停 · ⌘→/⌘← 上一个/下一个 · J/K/L 控制 · G/H 字幕同步 · A/B 循环 · ⌘S 截图 · ⌘M 迷你模式 · ⌃⌘F 全屏 · ⌘, 偏好设置"
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
