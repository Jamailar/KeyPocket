import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let d = CGFloat(pixels)
        let rect = NSRect(x: d * 0.08, y: d * 0.08, width: d * 0.84, height: d * 0.84)
        let path = NSBezierPath(roundedRect: rect, xRadius: d * 0.19, yRadius: d * 0.19)
        let gradient = NSGradient(starting: NSColor(red: 0.13, green: 0.35, blue: 0.29, alpha: 1), ending: NSColor(red: 0.27, green: 0.55, blue: 0.45, alpha: 1))!
        gradient.draw(in: path, angle: 70)
        let symbol = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [NSColor(red: 0.96, green: 0.95, blue: 0.86, alpha: 1)]))!
        symbol.draw(in: NSRect(x: d * 0.23, y: d * 0.37, width: d * 0.54, height: d * 0.26))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
