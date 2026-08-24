import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
    static let recentChanged = Notification.Name("recentChanged")
}

// MARK: - 最近播放记录 + 播放位置记忆

final class RecentManager {
    static let shared = RecentManager()
    private init() {}
    private let d = UserDefaults.standard
    private let maxRecent = 12

    var recent: [URL] {
        let arr = d.stringArray(forKey: "recentFiles") ?? []
        return arr.compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        var list = recent.map { $0.path }
        for u in urls {
            list.removeAll { $0 == u.path }
            list.insert(u.path, at: 0)
        }
        d.set(Array(list.prefix(maxRecent)), forKey: "recentFiles")
        NotificationCenter.default.post(name: .recentChanged, object: nil)
    }

    func clear() {
        d.removeObject(forKey: "recentFiles")
        NotificationCenter.default.post(name: .recentChanged, object: nil)
    }

    func resumePosition(for url: URL) -> Double? {
        let dict = d.dictionary(forKey: "resumePositions") as? [String: Double] ?? [:]
        return dict[url.path]
    }

    func setResumePosition(_ seconds: Double, for url: URL) {
        var dict = d.dictionary(forKey: "resumePositions") as? [String: Double] ?? [:]
        dict[url.path] = seconds
        d.set(dict, forKey: "resumePositions")
    }

    // MARK: 每文件轨道偏好

    func audioTrackOrdinal(for url: URL) -> Int? {
        let dict = d.dictionary(forKey: "audioTrackPrefs") as? [String: Int] ?? [:]
        return dict[url.path]
    }

    func setAudioTrackOrdinal(_ ord: Int, for url: URL) {
        var dict = d.dictionary(forKey: "audioTrackPrefs") as? [String: Int] ?? [:]
        dict[url.path] = ord
        d.set(dict, forKey: "audioTrackPrefs")
    }

    func subtitleTrackOrdinal(for url: URL) -> Int? {
        let dict = d.dictionary(forKey: "subtitleTrackPrefs") as? [String: Int] ?? [:]
        return dict[url.path]
    }

    func setSubtitleTrackOrdinal(_ ord: Int, for url: URL) {
        var dict = d.dictionary(forKey: "subtitleTrackPrefs") as? [String: Int] ?? [:]
        dict[url.path] = ord
        d.set(dict, forKey: "subtitleTrackPrefs")
    }

    func isSubtitleDisabled(for url: URL) -> Bool {
        let dict = d.dictionary(forKey: "subtitleDisabled") as? [String: Bool] ?? [:]
        return dict[url.path] ?? false
    }

    func setSubtitleDisabled(_ disabled: Bool, for url: URL) {
        var dict = d.dictionary(forKey: "subtitleDisabled") as? [String: Bool] ?? [:]
        if disabled {
            dict[url.path] = true
        } else {
            dict.removeValue(forKey: url.path)
        }
        d.set(dict, forKey: "subtitleDisabled")
    }

    static func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - 设置存储（UserDefaults 持久化）

final class Settings {
    static let shared = Settings()
    private init() {}
    private let d = UserDefaults.standard

    enum Backend: String, CaseIterable {
        case auto, avkit, ffmpeg
        var title: String {
            switch self {
            case .auto: return "自动（推荐）"
            case .avkit: return "硬件解码 AVFoundation"
            case .ffmpeg: return "软件解码 FFmpeg"
            }
        }
    }

    private enum Key {
        static let backend = "preferredBackend"
        static let loop = "loopPlayback"
        static let autoPlay = "autoPlay"
        static let subtitleSize = "subtitleFontSize"
        static let autoSubtitle = "autoLoadSubtitle"
        static let alwaysOnTop = "alwaysOnTop"
        static let openFullscreen = "openFullscreen"
        static let subtitlePosition = "subtitlePosition"
        static let subtitleColor = "subtitleColorIndex"
        static let fitWindow = "fitWindowToVideo"
        static let ffmpegHW = "ffmpegHardwareDecode"
        static let subtitleOffset = "subtitleOffset"
        static let playbackSpeed = "playbackSpeed"
    }

    enum SubtitleColorOption: Int, CaseIterable {
        case white, yellow, green, blue
        var title: String {
            switch self {
            case .white: return "白色"
            case .yellow: return "黄色"
            case .green: return "绿色"
            case .blue: return "蓝色"
            }
        }
        var color: NSColor {
            switch self {
            case .white: return .white
            case .yellow: return NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.2, alpha: 1)
            case .green: return NSColor(calibratedRed: 0.45, green: 1.0, blue: 0.45, alpha: 1)
            case .blue: return NSColor(calibratedRed: 0.5, green: 0.8, blue: 1.0, alpha: 1)
            }
        }
    }

    var backend: Backend {
        get { Backend(rawValue: d.string(forKey: Key.backend) ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: Key.backend) }
    }

    var loopPlayback: Bool {
        get { d.object(forKey: Key.loop) == nil ? false : d.bool(forKey: Key.loop) }
        set { d.set(newValue, forKey: Key.loop) }
    }

    var autoPlay: Bool {
        get { d.object(forKey: Key.autoPlay) == nil ? true : d.bool(forKey: Key.autoPlay) }
        set { d.set(newValue, forKey: Key.autoPlay) }
    }

    var subtitleFontSize: Double {
        get { d.object(forKey: Key.subtitleSize) == nil ? 26.0 : d.double(forKey: Key.subtitleSize) }
        set { d.set(newValue, forKey: Key.subtitleSize) }
    }

    var autoLoadSubtitle: Bool {
        get { d.object(forKey: Key.autoSubtitle) == nil ? true : d.bool(forKey: Key.autoSubtitle) }
        set { d.set(newValue, forKey: Key.autoSubtitle) }
    }

    var alwaysOnTop: Bool {
        get { d.bool(forKey: Key.alwaysOnTop) }
        set { d.set(newValue, forKey: Key.alwaysOnTop) }
    }

    var openFullscreen: Bool {
        get { d.bool(forKey: Key.openFullscreen) }
        set { d.set(newValue, forKey: Key.openFullscreen) }
    }

    /// 字幕距底部距离（pt）
    var subtitlePosition: Double {
        get { d.object(forKey: Key.subtitlePosition) == nil ? 64.0 : d.double(forKey: Key.subtitlePosition) }
        set { d.set(newValue, forKey: Key.subtitlePosition) }
    }

    var subtitleColor: SubtitleColorOption {
        get { SubtitleColorOption(rawValue: d.integer(forKey: Key.subtitleColor)) ?? .white }
        set { d.set(newValue.rawValue, forKey: Key.subtitleColor) }
    }

    /// 打开文件时窗口自动适配视频大小
    var fitWindowToVideo: Bool {
        get { d.object(forKey: Key.fitWindow) == nil ? true : d.bool(forKey: Key.fitWindow) }
        set { d.set(newValue, forKey: Key.fitWindow) }
    }

    /// FFmpeg 优先使用 VideoToolbox 硬件解码（下次打开文件生效）
    var ffmpegHardwareDecode: Bool {
        get { d.object(forKey: Key.ffmpegHW) == nil ? true : d.bool(forKey: Key.ffmpegHW) }
        set { d.set(newValue, forKey: Key.ffmpegHW) }
    }

    /// 字幕同步偏移（秒，正 = 字幕延后显示）
    var subtitleOffset: Double {
        get { d.object(forKey: Key.subtitleOffset) == nil ? 0 : d.double(forKey: Key.subtitleOffset) }
        set { d.set(newValue, forKey: Key.subtitleOffset) }
    }

    /// 播放速度（跨启动记忆）
    var playbackSpeed: Double {
        get {
            let v = d.object(forKey: Key.playbackSpeed) == nil ? 1.0 : d.double(forKey: Key.playbackSpeed)
            return min(4.0, max(0.25, v))
        }
        set { d.set(newValue, forKey: Key.playbackSpeed) }
    }
}

// MARK: - 偏好设置窗口

final class PreferenceWindowController: NSWindowController {

    static let shared = PreferenceWindowController()

    private var backendPopup: NSPopUpButton!
    private var loopCheck: NSButton!
    private var autoPlayCheck: NSButton!
    private var autoSubtitleCheck: NSButton!
    private var sizeSlider: NSSlider!
    private var sizeValueLabel: NSTextField!
    private var subtitleColorPopup: NSPopUpButton!
    private var positionSlider: NSSlider!
    private var positionValueLabel: NSTextField!
    private var topCheck: NSButton!
    private var fullscreenCheck: NSButton!
    private var fitWindowCheck: NSButton!
    private var hwDecodeCheck: NSButton!
    private var offsetSlider: NSSlider!
    private var offsetValueLabel: NSTextField!

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "偏好设置"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        buildUI()
        loadValues()
        win.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        func sectionTitle(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }
        func fieldLabel(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            return l
        }

        backendPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        backendPopup.addItems(withTitles: Settings.Backend.allCases.map { $0.title })
        backendPopup.target = self
        backendPopup.action = #selector(changed(_:))

        loopCheck = NSButton(checkboxWithTitle: "循环播放", target: self, action: #selector(changed(_:)))
        autoPlayCheck = NSButton(checkboxWithTitle: "打开文件后自动播放", target: self, action: #selector(changed(_:)))
        hwDecodeCheck = NSButton(checkboxWithTitle: "FFmpeg 优先硬件解码（VideoToolbox，下次打开文件生效）", target: self, action: #selector(changed(_:)))
        autoSubtitleCheck = NSButton(checkboxWithTitle: "自动加载同目录同名字幕", target: self, action: #selector(changed(_:)))

        sizeSlider = NSSlider(value: 26, minValue: 14, maxValue: 48, target: self, action: #selector(changed(_:)))
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        sizeValueLabel = NSTextField(labelWithString: "26")
        sizeValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        sizeValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

        let sliderRow = NSStackView(views: [sizeSlider, sizeValueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8

        subtitleColorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        subtitleColorPopup.addItems(withTitles: Settings.SubtitleColorOption.allCases.map { $0.title })
        subtitleColorPopup.target = self
        subtitleColorPopup.action = #selector(changed(_:))

        positionSlider = NSSlider(value: 64, minValue: 20, maxValue: 200, target: self, action: #selector(changed(_:)))
        positionSlider.isContinuous = true
        positionSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        positionValueLabel = NSTextField(labelWithString: "64")
        positionValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        positionValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

        let positionRow = NSStackView(views: [positionSlider, positionValueLabel])
        positionRow.orientation = .horizontal
        positionRow.spacing = 8

        offsetSlider = NSSlider(value: 0, minValue: -5, maxValue: 5, target: self, action: #selector(changed(_:)))
        offsetSlider.isContinuous = true
        offsetSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        offsetValueLabel = NSTextField(labelWithString: "0.0")
        offsetValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        offsetValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        let offsetRow = NSStackView(views: [offsetSlider, offsetValueLabel])
        offsetRow.orientation = .horizontal
        offsetRow.spacing = 8

        topCheck = NSButton(checkboxWithTitle: "窗口始终置顶", target: self, action: #selector(changed(_:)))
        fullscreenCheck = NSButton(checkboxWithTitle: "启动后自动全屏", target: self, action: #selector(changed(_:)))
        fitWindowCheck = NSButton(checkboxWithTitle: "打开文件时窗口自动适配视频大小", target: self, action: #selector(changed(_:)))

        let grid = NSGridView(views: [
            [NSView(), sectionTitle("播放")],
            [fieldLabel("解码后端"), backendPopup],
            [NSView(), loopCheck],
            [NSView(), autoPlayCheck],
            [NSView(), hwDecodeCheck],
            [NSView(), sectionTitle("字幕")],
            [NSView(), autoSubtitleCheck],
            [fieldLabel("字幕字号"), sliderRow],
            [fieldLabel("字幕颜色"), subtitleColorPopup],
            [fieldLabel("字幕位置"), positionRow],
            [fieldLabel("字幕同步"), offsetRow],
            [NSView(), sectionTitle("窗口")],
            [NSView(), topCheck],
            [NSView(), fullscreenCheck],
            [NSView(), fitWindowCheck],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
    }

    private func loadValues() {
        let s = Settings.shared
        backendPopup.selectItem(at: Settings.Backend.allCases.firstIndex(of: s.backend) ?? 0)
        loopCheck.state = s.loopPlayback ? .on : .off
        autoPlayCheck.state = s.autoPlay ? .on : .off
        autoSubtitleCheck.state = s.autoLoadSubtitle ? .on : .off
        sizeSlider.doubleValue = s.subtitleFontSize
        sizeValueLabel.stringValue = "\(Int(s.subtitleFontSize))"
        subtitleColorPopup.selectItem(at: s.subtitleColor.rawValue)
        positionSlider.doubleValue = s.subtitlePosition
        positionValueLabel.stringValue = "\(Int(s.subtitlePosition))"
        offsetSlider.doubleValue = s.subtitleOffset
        offsetValueLabel.stringValue = String(format: "%+.1f 秒", s.subtitleOffset)
        topCheck.state = s.alwaysOnTop ? .on : .off
        fullscreenCheck.state = s.openFullscreen ? .on : .off
        fitWindowCheck.state = s.fitWindowToVideo ? .on : .off
        hwDecodeCheck.state = s.ffmpegHardwareDecode ? .on : .off
    }

    @objc private func changed(_ sender: Any?) {
        let s = Settings.shared
        let idx = backendPopup.indexOfSelectedItem
        if Settings.Backend.allCases.indices.contains(idx) {
            s.backend = Settings.Backend.allCases[idx]
        }
        s.loopPlayback = loopCheck.state == .on
        s.autoPlay = autoPlayCheck.state == .on
        s.autoLoadSubtitle = autoSubtitleCheck.state == .on
        s.subtitleFontSize = sizeSlider.doubleValue
        let colorIdx = subtitleColorPopup.indexOfSelectedItem
        if let c = Settings.SubtitleColorOption(rawValue: colorIdx) {
            s.subtitleColor = c
        }
        s.subtitlePosition = positionSlider.doubleValue
        s.subtitleOffset = offsetSlider.doubleValue
        s.alwaysOnTop = topCheck.state == .on
        s.openFullscreen = fullscreenCheck.state == .on
        s.fitWindowToVideo = fitWindowCheck.state == .on
        s.ffmpegHardwareDecode = hwDecodeCheck.state == .on
        sizeValueLabel.stringValue = "\(Int(sizeSlider.doubleValue))"
        positionValueLabel.stringValue = "\(Int(positionSlider.doubleValue))"
        offsetValueLabel.stringValue = String(format: "%+.1f 秒", offsetSlider.doubleValue)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
