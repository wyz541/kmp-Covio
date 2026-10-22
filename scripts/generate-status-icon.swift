#!/usr/bin/env swift

import AppKit
import Foundation

private let pointSize: CGFloat = 18

private func color(
    _ hex: UInt32,
    _ alpha: CGFloat = 1
) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func gradient(
    _ colors: [NSColor],
    angle: CGFloat
) -> NSGradient {
    NSGradient(colors: colors)!
}

/// 菜单栏的拟物玻璃吊卡。最终资源由本脚本预渲染，运行时不再计算渐变和阴影。
private func drawStatusIcon(in rect: NSRect) {
    guard rect.width > 0, rect.height > 0 else { return }

    let scale = min(rect.width, rect.height) / pointSize
    let originX = rect.minX + (rect.width - pointSize * scale) / 2
    let originY = rect.minY + (rect.height - pointSize * scale) / 2
    func point(_ value: CGFloat) -> CGFloat { value * scale }
    func x(_ value: CGFloat) -> CGFloat { originX + point(value) }
    func y(_ value: CGFloat) -> CGFloat { originY + point(value) }

    let shadow = NSShadow()
    shadow.shadowColor = color(0x05102F, 0.30)
    shadow.shadowBlurRadius = point(0.7)
    shadow.shadowOffset = NSSize(width: 0, height: point(-0.55))

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let bar = NSBezierPath(
        roundedRect: NSRect(
            x: x(2.4),
            y: y(2.2),
            width: point(13.2),
            height: point(3.4)
        ),
        xRadius: point(1.7),
        yRadius: point(1.7)
    )
    gradient(
        [color(0xF9FAFC), color(0x8D96A8), color(0xD9DEE8)],
        angle: -90
    ).draw(in: bar, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    bar.lineWidth = point(0.35)
    color(0xFFFFFF, 0.58).setStroke()
    bar.stroke()

    let stem = NSBezierPath(
        roundedRect: NSRect(
            x: x(8.45),
            y: y(5.3),
            width: point(1.1),
            height: point(3.2)
        ),
        xRadius: point(0.55),
        yRadius: point(0.55)
    )
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    gradient(
        [color(0xF7FAFF), color(0x7383B7), color(0xC9D4F5)],
        angle: 0
    ).draw(in: stem, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    let card = NSBezierPath(
        roundedRect: NSRect(
            x: x(5.5),
            y: y(8.1),
            width: point(7),
            height: point(7.4)
        ),
        xRadius: point(1.65),
        yRadius: point(1.65)
    )
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    gradient(
        [color(0x9DB5FF), color(0x526ED0), color(0x243A86)],
        angle: -90
    ).draw(in: card, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    card.lineWidth = point(0.45)
    color(0xC9D8FF, 0.74).setStroke()
    card.stroke()

    let gloss = NSBezierPath(
        roundedRect: NSRect(
            x: x(6.15),
            y: y(8.65),
            width: point(5.7),
            height: point(1.45)
        ),
        xRadius: point(0.7),
        yRadius: point(0.7)
    )
    color(0xFFFFFF, 0.25).setFill()
    gloss.fill()

    let sparkle = NSBezierPath(
        ovalIn: NSRect(
            x: x(6.3),
            y: y(10.6),
            width: point(1.1),
            height: point(3.1)
        )
    )
    color(0xFFFFFF, 0.15).setFill()
    sparkle.fill()
}

private func render(size: Int) throws -> Data {
    let image = NSImage(
        size: NSSize(width: pointSize, height: pointSize),
        flipped: true
    ) { rect in
        drawStatusIcon(in: rect)
        return true
    }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

var arguments = Array(CommandLine.arguments.dropFirst())
let checkOnly = arguments.contains("--check")
arguments.removeAll { $0 == "--check" }
let outputDirectory = URL(
    fileURLWithPath: arguments.first ?? "macosApp/src",
    isDirectory: true
)

let outputs = [
    "CovioStatusIcon.png": try render(size: 18),
    "CovioStatusIcon@2x.png": try render(size: 36),
]

if checkOnly {
    let stale = outputs.filter { name, data in
        let url = outputDirectory.appendingPathComponent(name)
        return (try? Data(contentsOf: url)) != data
    }.map(\.key)
    guard stale.isEmpty else {
        for name in stale {
            print("stale: \(outputDirectory.appendingPathComponent(name).path)")
        }
        throw CocoaError(.fileReadCorruptFile)
    }
    print("Status icon assets are current.")
    exit(EXIT_SUCCESS)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)
for (name, data) in outputs {
    try data.write(
        to: outputDirectory.appendingPathComponent(name),
        options: .atomic
    )
}
print("Wrote \(outputs.count) status icon assets to \(outputDirectory.path)")
