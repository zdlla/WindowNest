import Foundation
import Darwin

@main struct PrivateStorageTests {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("storage-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        var checks = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        func mode(_ path: URL) -> Int { (try! fm.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber).intValue & 0o777 }
        let root = base.appendingPathComponent("WindowNest")
        let cache = root.appendingPathComponent("FileSearch")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let legacy = cache.appendingPathComponent("legacy.zstd")
        let bytes = Data("private filenames\n资料.pdf".utf8)
        try bytes.write(to: legacy)
        _ = chmod(root.path, 0o755); _ = chmod(cache.path, 0o755); _ = chmod(legacy.path, 0o644)
        let outside = base.appendingPathComponent("outside.txt")
        try Data("untouched".utf8).write(to: outside); _ = chmod(outside.path, 0o644)
        let link = root.appendingPathComponent("link.json")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        try PrivateStorage.secureTree(root)
        check(mode(root) == 0o700, "Old root remained publicly searchable")
        check(mode(cache) == 0o700 && mode(legacy) == 0o600, "Old index permissions were not migrated")
        check(try Data(contentsOf: legacy) == bytes, "Permission migration changed index bytes")
        check(mode(outside) == 0o644, "Migration followed a symlink outside app storage")
        do { try PrivateStorage.write(bytes, to: link); check(false, "Write followed a symlink") } catch { check(true, "Symlink rejected") }
        check(try String(contentsOf: outside, encoding: .utf8) == "untouched", "Symlink target overwritten")
        let saved = root.appendingPathComponent("preferences.json")
        try PrivateStorage.write(bytes, to: saved)
        let savedBytes = try Data(contentsOf: saved)
        check(mode(saved) == 0o600 && savedBytes == bytes, "New file did not remain private")
        _ = chmod(saved.path, 0o644)
        try PrivateStorage.write(Data("replacement".utf8), to: saved)
        check(mode(saved) == 0o600, "Atomic replacement lost permissions")
        let directoryLink = base.appendingPathComponent("directory-link")
        try fm.createSymbolicLink(at: directoryLink, withDestinationURL: root)
        do { try PrivateStorage.ensureDirectory(directoryLink); check(false, "Directory symlink accepted") } catch { check(true, "Directory symlink rejected") }
        print("Passed \(checks) private-storage migration and symlink checks")
    }
}
