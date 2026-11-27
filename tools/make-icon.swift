// Generates app/AppIcon.icns. Run: swift tools/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon grid: body is ~80% of the canvas
    let inset = s * 0.1, body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1), ending: NSColor(calibratedWhite: 0.05, alpha: 1))!
        .draw(in: bg, angle: -90)
    let zones: [NSColor] = [
        NSColor(srgbRed: 1.0, green: 0.15, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.1, green: 1.0, blue: 0.45, alpha: 1),
        NSColor(srgbRed: 0.1, green: 0.5, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.75, green: 0.2, blue: 1.0, alpha: 1)]
    // keycap rows
    let rows = 4, cols = 4
    let gx = body.minX + body.width * 0.13, gw = body.width * 0.74
    let gy = body.minY + body.height * 0.2, gh = body.height * 0.6
    let gap = gw * 0.035
    let kw = (gw - CGFloat(cols - 1) * gap) / CGFloat(cols), kh = (gh - CGFloat(rows - 1) * gap) / CGFloat(rows)
    for c in 0..<cols {
        for r in 0..<rows {
            let rect = NSRect(x: gx + CGFloat(c) * (kw + gap), y: gy + CGFloat(r) * (kh + gap), width: kw, height: kh)
            let p = NSBezierPath(roundedRect: rect, xRadius: kw * 0.18, yRadius: kw * 0.18)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: s * 0.035, color: zones[c].withAlphaComponent(0.9).cgColor)
            zones[c].withAlphaComponent(0.92).setFill(); p.fill()
            ctx.restoreGState()
            NSGradient(starting: NSColor.white.withAlphaComponent(0.35), ending: NSColor.white.withAlphaComponent(0))!
                .draw(in: p, angle: -90)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "app/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try! render(512).write(to: URL(fileURLWithPath: "app/icon-preview.png"))
print(p.terminationStatus == 0 ? "ok" : "iconutil failed")
