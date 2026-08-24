import AppKit

// 生成 1024x1024 应用图标：深色渐变圆角矩形 + 白色播放三角
let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(origin: .zero, size: size)

// 圆角矩形路径（macOS 风格圆角）
let corner: CGFloat = 230
let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

// 背景渐变
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.35, alpha: 1.0),
    NSColor(calibratedRed: 0.35, green: 0.16, blue: 0.45, alpha: 1.0),
    NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.55, alpha: 1.0),
])!
gradient.draw(in: path, angle: -60)

// 播放三角形
let tri = NSBezierPath()
let cx: CGFloat = 540
let cy: CGFloat = 512
let r: CGFloat = 210
tri.move(to: NSPoint(x: cx - r * 0.62, y: cy - r * 0.85))
tri.line(to: NSPoint(x: cx - r * 0.62, y: cy + r * 0.85))
tri.line(to: NSPoint(x: cx + r * 0.88, y: cy))
tri.close()
NSColor.white.setFill()
tri.fill()

// 底部细微高光
let shine = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 300), xRadius: corner, yRadius: corner)
NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
shine.fill()

NSGraphicsContext.restoreGraphicsState()

let pngData = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: "icon_1024.png")
try! pngData.write(to: out)
print("已生成 \(out.path)")
