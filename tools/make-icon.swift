// Generates app/AppIcon.icns and previews. Run: swift tools/make-icon.swift
import AppKit
import CoreImage

let zoneColors: [NSColor] = [
    NSColor(srgbRed: 1.00, green: 0.18, blue: 0.33, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.55, blue: 0.10, alpha: 1),
    NSColor(srgbRed: 0.15, green: 0.90, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.15, green: 0.55, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.70, green: 0.25, blue: 1.00, alpha: 1),
]

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background squircle
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.13, alpha: 1),
               ending: NSColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1))!.draw(in: bg, angle: -90)

    ctx.saveGState()
    bg.addClip()

    let kw = body.width * 0.56, kh = body.height * 0.52
    let kx = body.midX - kw / 2, ky = body.minY + body.height * 0.23
    let keyRect = NSRect(x: kx, y: ky, width: kw, height: kh)

    // RGB halo: rainbow key shape rendered offscreen, blurred, drawn behind the key
    let halo = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let r = keyRect.insetBy(dx: -kw * 0.04, dy: -kw * 0.04)
        NSGradient(colors: zoneColors)!.draw(in: NSBezierPath(roundedRect: r, xRadius: kw * 0.2, yRadius: kw * 0.2), angle: 0)
        return true
    }
    if let cg = halo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let ci = CIImage(cgImage: cg).clampedToExtent().applyingGaussianBlur(sigma: Double(s) * 0.06)
            .cropped(to: CGRect(x: 0, y: 0, width: s, height: s))
        let cictx = CIContext()
        if let out = cictx.createCGImage(ci, from: CGRect(x: 0, y: 0, width: s, height: s)) {
            ctx.saveGState(); ctx.setAlpha(0.95)
            ctx.draw(out, in: CGRect(x: 0, y: 0, width: s, height: s))
            ctx.restoreGState()
        }
    }

    // Keycap body: lit RGB edge
    let skirt = NSBezierPath(roundedRect: keyRect, xRadius: kw * 0.17, yRadius: kw * 0.17)
    NSGradient(colors: zoneColors)!.draw(in: skirt, angle: 0)

    let tInset = kw * 0.09
    let top = NSRect(x: kx + tInset, y: ky + tInset * 1.9, width: kw - 2 * tInset, height: kh - tInset * 2.6)
    let topPath = NSBezierPath(roundedRect: top, xRadius: top.width * 0.13, yRadius: top.width * 0.13)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.24, alpha: 1),
               ending: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.15, alpha: 1))!.draw(in: topPath, angle: -90)
    // subtle top highlight
    NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: topPath, angle: -90)

    // Legend: a sparkle on the key, in RGB gradient
    let c = NSPoint(x: top.midX, y: top.midY), r = top.height * 0.30
    let star = NSBezierPath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2
        let rad = i % 2 == 0 ? r : r * 0.28
        let p = NSPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
        i == 0 ? star.move(to: p) : star.line(to: p)
    }
    star.close()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: NSColor(srgbRed: 0.6, green: 0.4, blue: 1, alpha: 0.9).cgColor)
    NSGradient(colors: zoneColors)!.draw(in: star, angle: -45)
    ctx.restoreGState()

    ctx.restoreGState()
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
