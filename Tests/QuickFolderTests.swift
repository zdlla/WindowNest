import Foundation

@main struct QuickFolderTests {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("WindowNest-QuickFolders-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let first = root.appendingPathComponent("科研资料", isDirectory: true)
        let second = root.appendingPathComponent("工作文件", isDirectory: true)
        try fm.createDirectory(at: first, withIntermediateDirectories: true)
        try fm.createDirectory(at: second, withIntermediateDirectories: true)
        let repository = QuickFolderRepository(url: root.appendingPathComponent("private/quick-folders.json"))
        let store = QuickFolderStore(repository: repository)
        precondition(store.folders.isEmpty && store.error == nil)
        store.add([first, second, first])
        precondition(store.folders.map(\.name) == ["科研资料", "工作文件"])
        let a = store.folders[0]; let b = store.folders[1]
        let resolved = try a.resolvedURL(); precondition(resolved == first)
        let loaded = try repository.load(); precondition(loaded == store.folders)
        let reloaded = QuickFolderStore(repository: repository)
        precondition(reloaded.folders == store.folders, "Pins and stable identities survive restart")
        let fileMode = try fm.attributesOfItem(atPath: repository.url.path)[.posixPermissions] as! NSNumber
        let dirMode = try fm.attributesOfItem(atPath: repository.url.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
        precondition(fileMode.intValue == 0o600 && dirMode.intValue == 0o700)
        store.move(b.id, by: -1)
        precondition(store.folders.map(\.id) == [b.id, a.id])
        store.move(b.id, by: -1)
        precondition(store.folders.map(\.id) == [b.id, a.id])
        let renamed = root.appendingPathComponent("科研资料（已重命名）", isDirectory: true)
        try fm.moveItem(at: first, to: renamed)
        let movedURL = try a.resolvedURL(); precondition(movedURL == renamed, "Bookmark follows a moved folder")
        store.add([renamed])
        precondition(store.folders.count == 2, "A moved pin must not be duplicated")
        store.remove(a.id)
        precondition(store.folders == [b] && fm.fileExists(atPath: renamed.path), "Unpin never deletes folders")
        store.remove(UUID())
        precondition(store.folders == [b])
        let file = root.appendingPathComponent("not-a-folder.txt")
        try Data("fixture".utf8).write(to: file)
        store.add([file])
        precondition(store.folders == [b] && store.error != nil)
        let invalidRepo = QuickFolderRepository(url: root.appendingPathComponent("corrupt.json"))
        let original = Data("{broken".utf8); try original.write(to: invalidRepo.url)
        let invalid = QuickFolderStore(repository: invalidRepo); invalid.add([renamed])
        let preserved = try Data(contentsOf: invalidRepo.url)
        precondition(invalid.error != nil && preserved == original)
        try fm.removeItem(at: second)
        var missingError: String?
        store.open(b) { missingError = $0 }
        precondition(missingError != nil && store.folders == [b], "Missing targets report an error without launching or silently unpinning")
        print("Passed quick-folder persistence, bookmarks, deduplication, ordering, missing target and private-file checks")
    }
}
