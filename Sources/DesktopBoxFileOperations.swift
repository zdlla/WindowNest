import Foundation
import Darwin

enum DesktopBoxFileError: LocalizedError {
    case invalidName, collision, outsideFolder, recursiveMove
    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称不能为空，也不能包含 /、: 或控制字符。"
        case .collision: return "已有同名项目，请换一个名称。"
        case .outsideFolder: return "项目已移动，请刷新文件盒后重试。"
        case .recursiveMove: return "不能把文件夹移入它自己或它的子文件夹。"
        }
    }
}

/// Explicit user operations only. No automatic cleanup, overwrite or traversal.
enum DesktopBoxFileOperations {
    static func createFolder(in directory:URL)throws->URL {
        for suffix in 0..<10000 {
            let name=suffix==0 ? "新建文件夹" : "新建文件夹 \(suffix+1)"
            let target=directory.appendingPathComponent(name,isDirectory:true)
            let result=target.path.withCString { mkdir($0,0o700) }
            if result==0 { return target }
            if errno==EEXIST { continue }
            throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)
        }
        throw DesktopBoxFileError.collision
    }
    static func exists(_ url: URL) -> Bool {
        var value = stat(); return lstat(url.path, &value) == 0
    }
    static func rename(_ source: URL, in folder: URL, to name: String) throws -> URL {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), name.rangeOfCharacter(from:.controlCharacters) == nil else {
            throw DesktopBoxFileError.invalidName
        }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == root else {
            throw DesktopBoxFileError.outsideFolder
        }
        // Do not resolve the source's last component: renaming a symlink must
        // rename the link, never its target.
        let old = root.appendingPathComponent(source.lastPathComponent)
        let target = root.appendingPathComponent(name)
        guard exists(old) else { throw DesktopBoxFileError.outsideFolder }
        if old.lastPathComponent == name { return old }
        guard !exists(target) else { throw DesktopBoxFileError.collision }
        // RENAME_EXCL prevents a concurrent creator from being overwritten.
        let result = old.path.withCString { from in target.path.withCString { to in renamex_np(from,to,UInt32(RENAME_EXCL)) } }
        guard result == 0 else {
            if errno == EEXIST { throw DesktopBoxFileError.collision }
            throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)
        }
        return target
    }

    static func move(_ source: URL, into folder: URL) throws -> URL {
        guard source.isFileURL, folder.isFileURL else { throw DesktopBoxFileError.outsideFolder }
        let fm = FileManager.default
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let original = source.standardizedFileURL
        guard exists(original), (try root.resourceValues(forKeys:[.isDirectoryKey])).isDirectory == true else {
            throw DesktopBoxFileError.outsideFolder
        }
        if original.deletingLastPathComponent().resolvingSymlinksInPath() == root { return original }
        let resolved = original.resolvingSymlinksInPath()
        if (try resolved.resourceValues(forKeys:[.isDirectoryKey])).isDirectory == true,
           resolved.path == "/" || root.path == resolved.path || root.path.hasPrefix(resolved.path + "/") { throw DesktopBoxFileError.recursiveMove }
        let directory = (try? original.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true
        let suffix = directory ? "" : original.pathExtension
        let base = suffix.isEmpty ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
        for attempt in 0..<10000 {
            let name = attempt == 0 ? original.lastPathComponent : base + " \(attempt + 1)" + (suffix.isEmpty ? "" : "." + suffix)
            let target = root.appendingPathComponent(name)
            if exists(target) { continue }
            let code = original.path.withCString { from in target.path.withCString { to in renamex_np(from,to,UInt32(RENAME_EXCL)) } }
            if code == 0 { return target }
            let failure = errno
            if failure == EEXIST { continue }
            guard failure == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue:failure) ?? .EIO) }
            // Cross-volume handoff: copy into an app-owned staging directory,
            // publish without replacing, and only then remove the source.
            let staging = root.appendingPathComponent(".windownest-move-\(UUID())",isDirectory:true)
            try fm.createDirectory(at:staging,withIntermediateDirectories:false)
            defer { try? fm.removeItem(at:staging) }
            let staged = staging.appendingPathComponent(original.lastPathComponent)
            try fm.copyItem(at:original,to:staged)
            let published = staged.path.withCString { from in target.path.withCString { to in renamex_np(from,to,UInt32(RENAME_EXCL)) } }
            if published != 0 {
                if errno == EEXIST { continue }
                throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)
            }
            do { try fm.removeItem(at:original) }
            catch { throw NSError(domain:"WindowNest.FileMove",code:1,userInfo:[NSLocalizedDescriptionKey:"已复制到目标，但未能移除源项目；两个位置均保留，请在访达中检查。"] ) }
            return target
        }
        throw DesktopBoxFileError.collision
    }
}
