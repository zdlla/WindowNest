import Foundation

enum DesktopBoxNavigation {
    static func directory(root:URL,components:[String])throws->URL {
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains(":") }) else { throw DesktopBoxFileError.outsideFolder }
        let base=root.standardizedFileURL.resolvingSymlinksInPath()
        let target=components.reduce(base) { $0.appendingPathComponent($1,isDirectory:true) }.resolvingSymlinksInPath()
        guard base.path=="/" || target.path==base.path || target.path.hasPrefix(base.path+"/") else { throw DesktopBoxFileError.outsideFolder }
        return target
    }
}
