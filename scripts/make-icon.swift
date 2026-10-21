import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shape = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 208, yRadius: 208)
        NSGradient(
            starting: NSColor(red: 0.15, green: 0.62, blue: 0.54, alpha: 1),
            ending: NSColor(red: 0.07, green: 0.33, blue: 0.35, alpha: 1))!.draw(in: shape, angle: -70)
        let card = NSBezierPath(roundedRect: NSRect(x: 230, y: 238, width: 564, height: 548), xRadius: 70, yRadius: 70)
        NSColor.white.withAlphaComponent(0.97).setFill()
        card.fill()
        NSColor(red: 0.12, green: 0.48, blue: 0.44, alpha: 1).setStroke()
        let top = NSBezierPath()
        top.move(to: NSPoint(x: 272, y: 647))
        top.line(to: NSPoint(x: 752, y: 647))
        top.lineWidth = 12
        top.stroke()
        for x in [370, 654] {
            let ring = NSBezierPath(
                roundedRect: NSRect(x: x - 17, y: 736, width: 34, height: 96), xRadius: 17, yRadius: 17)
            NSColor.white.setFill()
            ring.fill()
        }
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 353, y: 446))
        check.line(to: NSPoint(x: 467, y: 342))
        check.line(to: NSPoint(x: 676, y: 551))
        check.lineWidth = 55
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
