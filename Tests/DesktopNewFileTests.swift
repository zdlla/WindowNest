import AppKit

@main struct DesktopNewFileTests {
    static func main()throws {
        let templates=URL(fileURLWithPath:CommandLine.arguments[1])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("WindowNest-NewFiles-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        precondition(DesktopNewFileKind.allCases.count==8)
        for kind in DesktopNewFileKind.allCases {
            let data=try kind.data(contents:kind.initialContents,templates:templates)
            let url=try DesktopBoxFileOperations.createFile(in:root,name:kind.defaultName,data:data)
            let readBack=try Data(contentsOf:url);precondition(readBack==data)
            precondition(url.pathExtension==kind.ext)
            if !kind.editableContents { precondition(data.starts(with:[0x50,0x4b])) }
        }
        let original="中文 😀 {braces} \\ slash\nSecond line\tTab"
        let data=try DesktopNewFileKind.rtf.data(contents:original)
        let rich=try NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil)
        precondition(rich.string.trimmingCharacters(in:.newlines)==original)
        print("Passed eight valid new-file types, bundled Office copies and Unicode/escaping RTF roundtrip")
    }
}
