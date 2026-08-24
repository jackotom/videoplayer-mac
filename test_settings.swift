import AppKit

// 设置窗口 + 设置读写验证：显示偏好设置窗口 3 秒后退出
@main
struct TestSettings {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        PreferenceWindowController.shared.show()

        // 验证设置读写
        let s = Settings.shared
        let oldTop = s.alwaysOnTop
        let oldSize = s.subtitleFontSize
        s.alwaysOnTop = !oldTop
        s.subtitleFontSize = 30
        s.loopPlayback = true
        print("✅ 设置读写: 后端=\(s.backend.rawValue) 置顶=\(s.alwaysOnTop)(原\(oldTop)) 字号=\(s.subtitleFontSize)(原\(oldSize)) 循环=\(s.loopPlayback)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            s.alwaysOnTop = oldTop
            s.subtitleFontSize = oldSize
            s.loopPlayback = false
            print("✅ 设置窗口显示 3 秒无崩溃")
            app.terminate(nil)
        }
        app.run()
    }
}
