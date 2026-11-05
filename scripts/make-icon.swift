import AppKit

// Draws the Lanes app icon (three horizontal lanes) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lanes.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    let background = NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88),
                                  xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.20, alpha: 1),
                        NSColor(calibratedRed: 0.20, green: 0.26, blue: 0.52, alpha: 1)])!
        .draw(in: background, angle: -90)

    // Three lanes: a faint track with a bright bar of different length on each.
    let lanes: [(length: CGFloat, color: NSColor)] = [
        (0.62, NSColor(calibratedRed: 0.45, green: 0.85, blue: 1.00, alpha: 1)),
        (0.40, NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.30, alpha: 1)),
        (0.52, NSColor(calibratedRed: 0.55, green: 1.00, blue: 0.70, alpha: 1)),
    ]
    let barHeight = s * 0.11
    for (i, lane) in lanes.enumerated() {
        let y = s * (0.30 + 0.17 * CGFloat(i))
        let track = NSRect(x: s * 0.20, y: y, width: s * 0.60, height: barHeight)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        let bar = NSRect(x: s * 0.20, y: y, width: s * lane.length, height: barHeight)
        lane.color.setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let files: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in files {
    try png(pixels: pixels).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
