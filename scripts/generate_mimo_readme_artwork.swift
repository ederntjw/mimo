#!/usr/bin/env swift

import AppKit
import Foundation

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let iconURL = repositoryRoot.appendingPathComponent("assets/mimo_strawberry_app_icon.png")
private let outputURL = repositoryRoot.appendingPathComponent("assets/repository-open-graph.png")
private let canvasSize = NSSize(width: 1280, height: 640)

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight)
    guard
        let descriptor = system.fontDescriptor.withDesign(.rounded),
        let rounded = NSFont(descriptor: descriptor, size: size)
    else {
        return system
    }
    return rounded
}

private func drawText(
    _ value: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineSpacing: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

private func drawSparkle(center: NSPoint, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x, y: center.y + radius))
    path.curve(
        to: NSPoint(x: center.x + radius, y: center.y),
        controlPoint1: NSPoint(x: center.x + radius * 0.12, y: center.y + radius * 0.22),
        controlPoint2: NSPoint(x: center.x + radius * 0.78, y: center.y + radius * 0.12)
    )
    path.curve(
        to: NSPoint(x: center.x, y: center.y - radius),
        controlPoint1: NSPoint(x: center.x + radius * 0.22, y: center.y - radius * 0.12),
        controlPoint2: NSPoint(x: center.x + radius * 0.12, y: center.y - radius * 0.78)
    )
    path.curve(
        to: NSPoint(x: center.x - radius, y: center.y),
        controlPoint1: NSPoint(x: center.x - radius * 0.12, y: center.y - radius * 0.22),
        controlPoint2: NSPoint(x: center.x - radius * 0.78, y: center.y - radius * 0.12)
    )
    path.curve(
        to: NSPoint(x: center.x, y: center.y + radius),
        controlPoint1: NSPoint(x: center.x - radius * 0.22, y: center.y + radius * 0.12),
        controlPoint2: NSPoint(x: center.x - radius * 0.12, y: center.y + radius * 0.78)
    )
    fill.setFill()
    path.fill()
}

guard let icon = NSImage(contentsOf: iconURL) else {
    fputs("Missing Mimo icon at \(iconURL.path)\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create Mimo social-card canvas\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

NSGraphicsContext.current?.imageInterpolation = .high
color(0xFFF7FA).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

color(0xF9DFE9, alpha: 0.72).setFill()
NSBezierPath(ovalIn: NSRect(x: 785, y: -160, width: 620, height: 780)).fill()
color(0xFFD9E8, alpha: 0.45).setFill()
NSBezierPath(ovalIn: NSRect(x: -210, y: 370, width: 590, height: 420)).fill()

let card = NSBezierPath(roundedRect: NSRect(x: 54, y: 52, width: 1172, height: 536), xRadius: 42, yRadius: 42)
color(0xFFFDFE, alpha: 0.78).setFill()
card.fill()
color(0xE94F8A, alpha: 0.22).setStroke()
card.lineWidth = 2
card.stroke()

drawText(
    "mimo",
    in: NSRect(x: 108, y: 390, width: 610, height: 118),
    font: roundedFont(size: 92, weight: .bold),
    color: color(0x4A2434)
)
drawText(
    "Hear it. Keep it. Ask it.",
    in: NSRect(x: 112, y: 318, width: 650, height: 58),
    font: roundedFont(size: 38, weight: .semibold),
    color: color(0xE94F8A)
)
drawText(
    "Live transcription, rolling notes, and in-meeting Q&A\nfor conversations that should not disappear.",
    in: NSRect(x: 112, y: 220, width: 650, height: 84),
    font: roundedFont(size: 26, weight: .medium),
    color: color(0x765465),
    lineSpacing: 7
)

let badge = NSBezierPath(roundedRect: NSRect(x: 112, y: 132, width: 408, height: 54), xRadius: 27, yRadius: 27)
color(0xFFD9E8).setFill()
badge.fill()
drawText(
    "macOS 14.2+  ·  Apple Silicon  ·  MIT",
    in: NSRect(x: 140, y: 145, width: 360, height: 30),
    font: roundedFont(size: 20, weight: .semibold),
    color: color(0x4A2434)
)

icon.draw(
    in: NSRect(x: 836, y: 145, width: 355, height: 355),
    from: NSRect(origin: .zero, size: icon.size),
    operation: .sourceOver,
    fraction: 1
)

drawSparkle(center: NSPoint(x: 820, y: 504), radius: 24, fill: color(0xE94F8A))
drawSparkle(center: NSPoint(x: 1173, y: 139), radius: 17, fill: color(0xE87565))
drawSparkle(center: NSPoint(x: 760, y: 171), radius: 10, fill: color(0xA75AC7))

graphicsContext.flushGraphics()

guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
    fputs("Unable to render Mimo social card\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
print("Wrote \(outputURL.path)")
