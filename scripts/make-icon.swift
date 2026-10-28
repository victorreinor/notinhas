// Draws the app icon into an .iconset folder: swift scripts/make-icon.swift build.noindex/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Drawn on a 1024-point canvas, y pointing up: a sticky note with its header band and a checklist.
func drawIcon() {
    let paper = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: paper, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0xFFF0A0).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0xFFF7BC), ending: color(0xFFE77E))!.draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    color(0xF7D24E).setFill()
    NSRect(x: 100, y: 744, width: 824, height: 180).fill()
    NSGraphicsContext.restoreGraphicsState()

    let ink = color(0x3A3326)
    // Header "buttons".
    ink.withAlphaComponent(0.45).setFill()
    NSBezierPath(ovalIn: NSRect(x: 196, y: 810, width: 48, height: 48)).fill()
    NSBezierPath(ovalIn: NSRect(x: 780, y: 810, width: 48, height: 48)).fill()

    for (index, checked) in [true, false, false].enumerated() {
        let y = 560 - CGFloat(index) * 150
        let box = NSRect(x: 210, y: y, width: 92, height: 92)
        if checked {
            ink.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: box, xRadius: 24, yRadius: 24).fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 22, y: box.midY + 2))
            tick.line(to: NSPoint(x: box.minX + 40, y: box.minY + 24))
            tick.line(to: NSPoint(x: box.maxX - 20, y: box.maxY - 22))
            tick.lineWidth = 14
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 6, dy: 6), xRadius: 19, yRadius: 19)
            outline.lineWidth = 12
            ink.withAlphaComponent(0.6).setStroke()
            outline.stroke()
        }
        let width: CGFloat = index == 2 ? 300 : 440
        ink.withAlphaComponent(checked ? 0.25 : 0.4).setFill()
        NSBezierPath(roundedRect: NSRect(x: 350, y: y + 28, width: width, height: 36), xRadius: 18, yRadius: 18).fill()
    }
}

func png(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
