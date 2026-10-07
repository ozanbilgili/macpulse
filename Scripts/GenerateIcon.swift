import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let edge = CGFloat(size)
    let rect = NSRect(x: edge * 0.055, y: edge * 0.055, width: edge * 0.89, height: edge * 0.89)
    let background = NSBezierPath(roundedRect: rect, xRadius: edge * 0.20, yRadius: edge * 0.20)
    NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.16, alpha: 1).setFill()
    background.fill()
    let pulse = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [(0.19, 0.50), (0.33, 0.50), (0.42, 0.72), (0.54, 0.27), (0.64, 0.50), (0.81, 0.50)]
    pulse.move(to: NSPoint(x: points[0].0 * edge, y: points[0].1 * edge))
    for point in points.dropFirst() { pulse.line(to: NSPoint(x: point.0 * edge, y: point.1 * edge)) }
    pulse.lineWidth = edge * 0.065
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor(calibratedRed: 0.40, green: 0.88, blue: 0.74, alpha: 1).setStroke()
    pulse.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
