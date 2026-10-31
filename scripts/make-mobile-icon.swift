import AppKit

// iOS supplies the icon mask. Render an opaque square at an exact pixel size.
guard CommandLine.arguments.count == 2,
    let pixels = CGContext(
        data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else {
    FileHandle.standardError.write(Data("Usage: swift scripts/make-mobile-icon.swift /path/to/AppIcon.png\n".utf8))
    exit(1)
}
let context = NSGraphicsContext(cgContext: pixels, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGradient(
    starting: NSColor(red: 0.15, green: 0.62, blue: 0.54, alpha: 1),
    ending: NSColor(red: 0.07, green: 0.33, blue: 0.35, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -70)
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 230, y: 238, width: 564, height: 548), xRadius: 70, yRadius: 70).fill()
NSColor(red: 0.12, green: 0.48, blue: 0.44, alpha: 1).setStroke()
let rule = NSBezierPath()
rule.move(to: NSPoint(x: 272, y: 647))
rule.line(to: NSPoint(x: 752, y: 647))
rule.lineWidth = 12
rule.stroke()
for x in [370, 654] {
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 17, y: 736, width: 34, height: 96), xRadius: 17, yRadius: 17).fill()
}
let check = NSBezierPath()
check.move(to: NSPoint(x: 353, y: 446))
check.line(to: NSPoint(x: 467, y: 342))
check.line(to: NSPoint(x: 676, y: 551))
check.lineWidth = 55
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.stroke()
NSGraphicsContext.restoreGraphicsState()
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let image = pixels.makeImage(),
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Could not encode icon\n".utf8))
    exit(1)
}
try data.write(to: destination, options: .atomic)
