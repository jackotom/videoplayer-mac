import AppKit
import AVKit

// 进度条单元格：在进度条上绘制章节刻度
final class ChapterSliderCell: NSSliderCell {
    var chapterRatios: [CGFloat] = []

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        super.drawBar(inside: rect, flipped: flipped)
        guard !chapterRatios.isEmpty else { return }
        NSColor.white.withAlphaComponent(0.55).setFill()
        for r in chapterRatios where r > 0.01 && r < 0.99 {
            let x = rect.minX + rect.width * r
            NSRect(x: x - 0.5, y: rect.midY - 5, width: 1, height: 10).fill()
        }
    }
}

// 统一播放控制条（AVKit / FFmpeg 双后端通用）：
// [上一个] [播放/暂停] [下一个] [倍速] [当前时间] ——进度条—— [总时长] [音量] [音频输出] [全屏]
final class PlaybackControlBar: NSView {

    weak var controller: PlayerViewController?

    private let prevButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let speedButton = NSButton()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let slider = NSSlider()
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let volumeSlider = NSSlider()
    private let routePicker = AVRoutePickerView()
    private let fullscreenButton = NSButton()
    private let chapterCell = ChapterSliderCell()
    private var updateTimer: Timer?
    private var userSeeking = false
    private var lastSeekTime = Date.distantPast
    private var seekingResetTimer: Timer?

    init(controller: PlayerViewController) {
        self.controller = controller
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 6

        configureButton(prevButton, symbol: "backward.end.fill", tooltip: "上一个视频（⌘←）", action: #selector(prevClicked))
        configureButton(playPauseButton, symbol: "pause.fill", tooltip: "播放/暂停（空格 / K）", action: #selector(playPauseClicked))
        configureButton(nextButton, symbol: "forward.end.fill", tooltip: "下一个视频（⌘→）", action: #selector(nextClicked))
        configureButton(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", tooltip: "全屏（⌃⌘F）", action: #selector(fullscreenClicked))

        // 倍速按钮：点击弹出速度菜单
        speedButton.title = "1.0x"
        speedButton.bezelStyle = .inline
        speedButton.isBordered = false
        speedButton.contentTintColor = .white
        speedButton.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        speedButton.target = self
        speedButton.action = #selector(speedClicked)
        speedButton.toolTip = "播放速度"
        speedButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.font = mono
        timeLabel.textColor = .white
        durationLabel.font = mono
        durationLabel.textColor = .white

        chapterCell.sliderType = .linear
        slider.cell = chapterCell
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.toolTip = "拖动跳转（←/→ 快进快退，J/L 10 秒）"

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.floatValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.controlSize = .small
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.toolTip = "音量（↑/↓ 调节）"
        volumeSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        // 音频输出（隔空播放）路由选择器
        routePicker.isRoutePickerButtonBordered = false
        routePicker.setAccessibilityLabel("音频输出")
        routePicker.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = NSStackView(views: [
            prevButton, playPauseButton, nextButton, speedButton,
            timeLabel, slider, durationLabel,
            volumeSlider, routePicker, fullscreenButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func configureButton(_ b: NSButton, symbol: String, tooltip: String, action: Selector) {
        b.bezelStyle = .inline
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = action
        b.toolTip = tooltip
    }

    @objc private func prevClicked() { controller?.playPrevious() }
    @objc private func nextClicked() { controller?.playNext() }
    @objc private func playPauseClicked() { controller?.togglePlayPause() }
    @objc private func fullscreenClicked() { controller?.toggleFullScreen() }

    @objc private func speedClicked() {
        let menu = NSMenu()
        let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
        let current = controller?.playbackSpeed ?? 1.0
        for s in speeds {
            let it = NSMenuItem(title: s == 1.0 ? "1.0x（正常）" : "\(s)x", action: #selector(speedSelected(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s
            it.state = abs(current - s) < 0.01 ? .on : .off
            menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: speedButton.bounds.height + 6), in: speedButton)
    }

    @objc private func speedSelected(_ sender: NSMenuItem) {
        controller?.setPlaybackSpeed(sender)
    }

    @objc private func sliderChanged() {
        guard let c = controller else { return }
        userSeeking = true
        if Date().timeIntervalSince(lastSeekTime) > 0.25 {
            lastSeekTime = Date()
            c.unifiedSeek(to: slider.doubleValue * max(c.unifiedDuration, 1))
        }
        seekingResetTimer?.invalidate()
        seekingResetTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.userSeeking = false
        }
    }

    @objc private func volumeChanged() {
        controller?.unifiedSetVolume(volumeSlider.floatValue)
    }

    func updateUI() {
        guard let c = controller else { return }
        let t = c.unifiedCurrentTime
        let d = c.unifiedDuration
        if !userSeeking {
            slider.doubleValue = d > 0 ? min(1, t / d) : 0
        }
        timeLabel.stringValue = formatTime(t)
        durationLabel.stringValue = formatTime(d)
        playPauseButton.image = NSImage(
            systemSymbolName: c.unifiedPaused ? "play.fill" : "pause.fill",
            accessibilityDescription: nil)
        prevButton.isEnabled = c.currentIndex > 0
        nextButton.isEnabled = c.currentIndex + 1 < c.playlist.count
        // 音量滑块与后端（含键盘 ↑↓ 调节）保持同步
        volumeSlider.floatValue = c.unifiedVolume
        // 倍速按钮标题
        let sp = c.playbackSpeed
        speedButton.title = sp.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.1fx", sp) : String(format: "%gx", sp)
        // 章节刻度
        chapterCell.chapterRatios = c.chapterRatios
        // 控制中心 Now Playing 信息
        c.updateNowPlayingInfo()
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}
