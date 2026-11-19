import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("WindowNest.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: s)
        transform.concat()
        let base = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(calibratedRed: 0.25, green: 0.60, blue: 1, alpha: 1),
                   ending: NSColor(calibratedRed: 0.11, green: 0.28, blue: 0.75, alpha: 1))!.draw(in: base, angle: -75)
        for (x, y, width, height, alpha) in [(260.0, 490.0, 504.0, 300.0, 0.42), (225, 430, 574, 310, 0.7)] {
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 42, yRadius: 42).fill()
        }
        NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 188, y: 248, width: 648, height: 350), xRadius: 64, yRadius: 64).fill()
        NSColor(calibratedRed: 0.16, green: 0.40, blue: 0.84, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 415, y: 438, width: 194, height: 49), xRadius: 24, yRadius: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
// ICNS is a chunked container; embed the lossless PNG representations directly.
// This also works on hosts where iconutil's image converter is unavailable.
func bigEndian(_ number: Int) -> Data {
    var value = UInt32(number).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
let representations = [("icp4", "16x16"), ("icp5", "32x32"), ("icp6", "32x32@2x"),
    ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"),
    ("ic10", "512x512@2x"), ("ic11", "16x16@2x"), ("ic12", "32x32@2x"),
    ("ic13", "128x128@2x"), ("ic14", "256x256@2x")]
var chunks = Data()
for (kind, name) in representations {
    let png = try Data(contentsOf: root.appendingPathComponent("icon_\(name).png"))
    chunks.append(Data(kind.utf8))
    chunks.append(bigEndian(png.count + 8))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(chunks.count + 8))
icns.append(chunks)
let destination = root.deletingLastPathComponent().appendingPathComponent("WindowNest.icns")
try icns.write(to: destination)
guard NSImage(contentsOf: destination) != nil else { fatalError("Invalid icon") }
