import AppKit
import UniformTypeIdentifiers

/// Shared, bounded type-icon cache. Only the extension and directory flag are
/// used; user files are never opened or passed to a preview/thumbnail service.
@MainActor final class FileTypeIcons {
    static let shared=FileTypeIcons()
    static let assets:Set<String>=["7z","ai","bmp","css","csv","doc","docx","epub","gif","gz","heic","html","image","jpg","js","json","key","md","mov","mp3","mp4","pages","pdf","png","ppt","pptx","psd","py","rar","rtf","svg","tar","tiff","txt","wav","xls","xlsx","xml","zip"]
    private static let aliases=["jpeg":"jpg","jpe":"jpg","tif":"tiff","htm":"html","markdown":"md"]
    private let assetDirectory:URL?
    private let cache:NSCache<NSString,NSImage>={
        let cache=NSCache<NSString,NSImage>();cache.countLimit=64;cache.totalCostLimit=2*1024*1024;return cache
    }()
    init(assetDirectory:URL? = Bundle.main.resourceURL?.appendingPathComponent("FileTypeIcons",isDirectory:true)) { self.assetDirectory=assetDirectory }

    static func assetName(for extensionName:String,directory:Bool)->String? {
        guard !directory else { return nil }
        let ext=extensionName.lowercased()
        let canonical=aliases[ext] ?? ext
        if assets.contains(canonical) { return canonical }
        if let type=UTType(filenameExtension:ext),type.conforms(to:.image) { return "image" }
        return nil
    }

    func image(for url:URL,directory:Bool)->NSImage {
        let asset=Self.assetName(for:url.pathExtension,directory:directory)
        let type:UTType=directory ? .folder : UTType(filenameExtension:url.pathExtension) ?? .data
        let key=(asset.map { "bundled:\($0)" } ?? "system:\(type.identifier)") as NSString
        if let image=cache.object(forKey:key) { return image }
        let original:NSImage
        if let asset,let location=assetDirectory?.appendingPathComponent(asset+".png"),let image=NSImage(contentsOf:location) {
            original=image
        } else { original=NSWorkspace.shared.icon(for:type) }
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context=NSGraphicsContext(bitmapImageRep:bitmap) else { return original }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;context.imageInterpolation = .high
        NSColor.clear.setFill();NSRect(x:0,y:0,width:96,height:96).fill(using:.copy)
        original.draw(in:NSRect(x:0,y:0,width:96,height:96));NSGraphicsContext.restoreGraphicsState()
        let image=NSImage(size:NSSize(width:48,height:48));image.addRepresentation(bitmap)
        cache.setObject(image,forKey:key,cost:96*96*4);return image
    }
}
