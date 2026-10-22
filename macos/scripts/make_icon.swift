// Draws DragWheel's app icon (a radial wheel) into an .iconset folder.
// Usage: swift scripts/make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-square background with a warm gradient
    let inset = s * 0.09
    let bg = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: bg, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(srgbRed: 1, green: 0.62, blue: 0.25, alpha: 1).cgColor,
                                       NSColor(srgbRed: 0.93, green: 0.30, blue: 0.10, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Eight petals
    let c = CGPoint(x: s / 2, y: s / 2)
    let inner = s * 0.15, outer = s * 0.34
    for i in 0..<8 {
        let mid = CGFloat(i) * .pi / 4 + .pi / 2
        let a0 = mid - .pi / 8 + 0.06, a1 = mid + .pi / 8 - 0.06
        let p = CGMutablePath()
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(NSColor(white: 1, alpha: i == 0 ? 1 : 0.78).cgColor)
        ctx.fillPath()
    }
    // Hub
    ctx.setFillColor(NSColor(white: 1, alpha: 0.95).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - inner * 0.72, y: c.y - inner * 0.72, width: inner * 1.44, height: inner * 1.44))
    ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.36, blue: 0.12, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - inner * 0.3, y: c.y - inner * 0.3, width: inner * 0.6, height: inner * 0.6))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
