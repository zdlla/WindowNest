import Foundation

@main struct DesktopBoxFileOperationTests {
    static func main() throws {
        let fm=FileManager.default
        let root=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("WindowNest-MoveTest-\(UUID())",isDirectory:true)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        let source=root.appendingPathComponent("source",isDirectory:true),target=root.appendingPathComponent("target",isDirectory:true)
        try fm.createDirectory(at:source,withIntermediateDirectories:true);try fm.createDirectory(at:target,withIntermediateDirectories:true)
        func write(_ url:URL,_ text:String) throws { try Data(text.utf8).write(to:url) }
        func mustFail(_ action:() throws -> Void) { do { try action();preconditionFailure("Expected failure") } catch {} }
        let original=source.appendingPathComponent("Example.txt");try write(original,"fixture content")
        let moved=try DesktopBoxFileOperations.move(original,into:target)
        precondition(!fm.fileExists(atPath:original.path))
        let movedContent=try String(contentsOf:moved,encoding:.utf8);precondition(movedContent == "fixture content")
        let duplicate=source.appendingPathComponent("Example.txt");try write(duplicate,"different")
        let second=try DesktopBoxFileOperations.move(duplicate,into:target)
        precondition(second.lastPathComponent == "Example 2.txt")
        let unchanged=try String(contentsOf:moved,encoding:.utf8);precondition(unchanged == "fixture content")
        let same=try DesktopBoxFileOperations.move(moved,into:target);precondition(same == moved)
        let renamed=try DesktopBoxFileOperations.rename(moved,in:target,to:"重命名.txt")
        precondition(!fm.fileExists(atPath:moved.path) && fm.fileExists(atPath:renamed.path))
        mustFail { _ = try DesktopBoxFileOperations.rename(renamed,in:target,to:second.lastPathComponent) }
        for name in [""," ",".","..","../escape","a/b","a:b","a\nfile"] {
            mustFail { _ = try DesktopBoxFileOperations.rename(renamed,in:target,to:name) }
        }
        mustFail { _ = try DesktopBoxFileOperations.rename(renamed,in:source,to:"outside.txt") }
        let folder=source.appendingPathComponent("Folder",isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true);try write(folder.appendingPathComponent("Child.txt"),"nested")
        let nested=folder.appendingPathComponent("Inner",isDirectory:true);try fm.createDirectory(at:nested,withIntermediateDirectories:true)
        mustFail { _ = try DesktopBoxFileOperations.move(folder,into:nested) }
        precondition(fm.fileExists(atPath:folder.appendingPathComponent("Child.txt").path))
        let movedFolder=try DesktopBoxFileOperations.move(folder,into:target)
        precondition(!fm.fileExists(atPath:folder.path) && fm.fileExists(atPath:movedFolder.appendingPathComponent("Child.txt").path))
        let renamedFolder=try DesktopBoxFileOperations.rename(movedFolder,in:target,to:"RenamedFolder")
        precondition(fm.fileExists(atPath:renamedFolder.appendingPathComponent("Child.txt").path))
        let link=target.appendingPathComponent("Link.txt");try fm.createSymbolicLink(at:link,withDestinationURL:renamed)
        let renamedLink=try DesktopBoxFileOperations.rename(link,in:target,to:"NewLink.txt")
        precondition(fm.fileExists(atPath:renamed.path) && DesktopBoxFileOperations.exists(renamedLink))
        let dangling=target.appendingPathComponent("Reserved.txt");try fm.createSymbolicLink(atPath:dangling.path,withDestinationPath:root.appendingPathComponent("missing").path)
        mustFail { _ = try DesktopBoxFileOperations.rename(renamed,in:target,to:"Reserved.txt") }
        let text=try DesktopBoxFileOperations.createTextFile(in:target,name:"新建内容.md",contents:"# Example\n中文内容\n")
        let content=try String(contentsOf:text,encoding:.utf8);precondition(content=="# Example\n中文内容\n")
        let permissions=try fm.attributesOfItem(atPath:text.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue==0o600)
        mustFail { _=try DesktopBoxFileOperations.createTextFile(in:target,name:"新建内容.md",contents:"must not overwrite") }
        mustFail { _=try DesktopBoxFileOperations.createTextFile(in:target,name:"Reserved.txt",contents:"must not replace symlink") }
        for invalid in ["","..","../outside.txt","bad/name.txt","bad:name","bad\nname"] {
            mustFail { _=try DesktopBoxFileOperations.createTextFile(in:target,name:invalid,contents:"") }
        }
        mustFail { _=try DesktopBoxFileOperations.createTextFile(in:target,name:"Oversize.txt",contents:String(repeating:"文",count:400000)) }
        let after=try String(contentsOf:text,encoding:.utf8);precondition(after==content)
        let leftovers=try fm.contentsOfDirectory(atPath:target.path)
        precondition(!leftovers.contains(where:{$0.hasPrefix(".windownest-new-")}),"Failed creates must remove temporary files")
        precondition(!fm.fileExists(atPath:root.appendingPathComponent("outside.txt").path))
        print("Passed move, source removal, collisions, folder contents, rename validation, containment and symlink safety checks")
    }
}
