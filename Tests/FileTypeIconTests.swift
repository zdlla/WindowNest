import AppKit

@main struct FileTypeIconTests {
    @MainActor static func main() throws {
        let assets=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let icons=FileTypeIcons(assetDirectory:assets)
        // These paths do not exist: type rendering needs neither file data nor metadata.
        let prefix=URL(fileURLWithPath:"/WindowNest-Nonexistent-Icon-Fixture",isDirectory:true)
        for name in FileTypeIcons.assets {
            let path=assets.appendingPathComponent(name+".png")
            let representation=try NSBitmapImageRep(data:Data(contentsOf:path)).unwrap()
            precondition(representation.pixelsWide==96 && representation.pixelsHigh==96)
            let rendered=icons.image(for:prefix.appendingPathComponent("Sample."+name),directory:false)
            precondition(rendered.size==NSSize(width:48,height:48))
        }
        let pdf=icons.image(for:prefix.appendingPathComponent("Sample.PDF"),directory:false)
        let jpg=icons.image(for:prefix.appendingPathComponent("Sample.jpg"),directory:false)
        let jpeg=icons.image(for:prefix.appendingPathComponent("Sample.JPEG"),directory:false)
        precondition(jpg === jpeg,"Extension aliases should share the decoded icon")
        precondition(pdf !== jpg)
        let bitmap=try (pdf.representations.first as? NSBitmapImageRep).unwrap()
        precondition((bitmap.colorAt(x:0,y:0)?.alphaComponent ?? 1)<0.01,"Document margins must stay transparent")
        func coloredPixels(_ image:NSImage,red:Bool)->Int {
            let pixels=image.representations.first as! NSBitmapImageRep
            return (0..<96).reduce(0) { sum,y in sum+(0..<96).filter { x in
                guard let c=pixels.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.alphaComponent>0.9 else { return false }
                return red ? c.redComponent>c.greenComponent*1.8 : c.greenComponent>c.redComponent*1.8
            }.count }
        }
        precondition(coloredPixels(pdf,red:true)>100 && coloredPixels(jpg,red:false)>100,"Must render the bundled colored assets")
        precondition(FileTypeIcons.assetName(for:"PDF",directory:true)==nil)
        precondition(FileTypeIcons.assetName(for:"unknown-extension-windownest",directory:false)==nil)
        _=icons.image(for:prefix.appendingPathComponent("Unknown.unknown-extension-windownest"),directory:false)
        _=icons.image(for:prefix.appendingPathComponent("Folder.pdf"),directory:true)
        let missing=FileTypeIcons(assetDirectory:prefix)
        _=missing.image(for:prefix.appendingPathComponent("Sample.pdf"),directory:false)
        for ext in ["txt","rtf","xml","docx","xlsx","pptx","md","py"] {
            let original=icons.image(for:prefix.appendingPathComponent("Sample.\(ext)"),directory:false)
            let size=original.size
            let menu=icons.menuImage(for:ext)
            precondition(menu.size==NSSize(width:16,height:16))
            precondition(original.size==size && menu !== original,"Menu scaling must not shrink file-grid icons")
        }
        print("Passed 39 bundled images, colored rendering, aliases, cache reuse, folders and missing-asset fallback without reading user files")
    }
}
private extension Optional {
    func unwrap() throws->Wrapped {
        guard let value=self else { throw CocoaError(.fileReadCorruptFile) };return value
    }
}
