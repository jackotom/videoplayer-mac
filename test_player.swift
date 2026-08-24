import AppKit
import AVFoundation

// FFmpegPlayer 真实渲染测试：弹出窗口播放，10 秒后退出
final class TestController: NSObject {
    let player = FFmpegPlayer()
    var window: NSWindow!
    var start: Date!

    func run(file: String) {
        start = Date()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view

        player.videoLayer.frame = view.bounds
        view.layer?.addSublayer(player.videoLayer)

        player.onReady = { [weak self] size in
            print("✅ 就绪 视频: \(Int(size.width))x\(Int(size.height)) 时长: \(String(format: "%.2f", self?.player.duration ?? 0))s")
            self?.player.videoLayer.frame = view.bounds
        }
        player.onError = { print("❌ 错误: \($0)") }
        player.onPlaybackEnded = { print("✅ 播放结束（EOF）") }

        player.open(url: URL(fileURLWithPath: file))
        player.play()
        window.makeKeyAndOrderFront(nil)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = self.player.currentTime
            print("进度: \(String(format: "%.2f", t))s / \(String(format: "%.2f", self.player.duration))s  暂停=\(self.player.isPaused)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            print("▶️ 执行 seek → 5.0s")
            self?.player.seek(to: 5.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            print("测试完成，退出")
            self.player.stop()
            app.terminate(nil)
        }
    }
}

@main
struct TestMain {
    static func main() {
        let c = TestController()
        c.run(file: CommandLine.arguments[1])
        NSApplication.shared.run()
    }
}
