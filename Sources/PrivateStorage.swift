import Foundation
import Darwin

/// Restrict app-owned data, including old installations. This is a POSIX
/// privacy boundary between accounts, not isolation from another app of the UID.
enum PrivateStorage {
    static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try validate(url, directory: true)
        guard chmod(url.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES) }
    }

    static func write(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: url.path) || isSymlink(url) { try validate(url, directory: false) }
        try data.write(to: url, options: .atomic)
        try restrictFile(url)
    }

    static func prepareStandardFolder() throws {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowNest", isDirectory: true)
        try secureTree(folder)
    }

    static func secureTree(_ folder: URL) throws {
        try ensureDirectory(folder)
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
            let type = info.st_mode & mode_t(S_IFMT)
            // Never chmod or recurse through a symlink into another directory.
            if type == mode_t(S_IFLNK) { continue }
            guard info.st_uid == getuid() else { throw CocoaError(.fileWriteNoPermission) }
            if type == mode_t(S_IFDIR) { try secureTree(url) }
            else if type == mode_t(S_IFREG) { try restrictFile(url) }
        }
    }

    private static func restrictFile(_ url: URL) throws {
        try validate(url, directory: false)
        guard chmod(url.path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES) }
    }
    private static func isSymlink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
    }
    private static func validate(_ url: URL, directory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG) else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
