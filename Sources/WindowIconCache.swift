import AppKit

/// Display-sized, decoded local images. Follows Nuke's processing-before-cache
/// approach, using CoreGraphics and the existing MIT LRU instead of a network
/// image pipeline. Called on WindowService's serial queue; LRU reads are safe.
final class WindowIconCache {
    struct Key: Hashable { let pid: Int32; let bundleID: String }
    static let pixels = 96
    private let cache = LRUCache<Key, NSImage>(totalCostLimit: 2 * 1024 * 1024, countLimit: 64)

    func cached(pid: Int32, bundleID: String) -> NSImage? { cache.value(forKey: Key(pid: pid, bundleID: bundleID)) }

    func image(pid: Int32, bundleID: String, source: NSImage) -> NSImage {
        let key = Key(pid: pid, bundleID: bundleID)
        if let image = cache.value(forKey: key) { return image }
        guard let bitmap = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        let scale = min(1, Double(Self.pixels) / Double(max(bitmap.width, bitmap.height)))
        let width = max(1, Int(Double(bitmap.width) * scale)), height = max(1, Int(Double(bitmap.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.interpolationQuality = .high
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decoded = context.makeImage() else { return source }
        let image = NSImage(cgImage: decoded, size: NSSize(width: Double(width) / 2, height: Double(height) / 2))
        cache.setValue(image, forKey: key, cost: width * height * 4)
        return image
    }

    func prune(pids: Set<Int32>) {
        for key in cache.keys where !pids.contains(key.pid) { cache.removeValue(forKey: key) }
    }
}
