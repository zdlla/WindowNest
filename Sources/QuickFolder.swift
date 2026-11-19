import Foundation

struct QuickFolder: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let path: String
    let bookmark: Data

    init(url: URL, id: UUID = UUID()) throws {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard resource.isDirectory == true, resource.isPackage != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        self.id = id
        name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        path = url.path
        bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolve only on an explicit action. Never mount an unavailable volume
    /// or scan pinned directories while the overview is rendering or hidden.
    func resolvedURL() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values.isDirectory == true, values.isPackage != true else { throw CocoaError(.fileNoSuchFile) }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

struct QuickFolderRepository {
    let url: URL
    static var standard: Self {
        Self(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowNest/quick-folders.json"))
    }
    func load() throws -> [QuickFolder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let folders = try JSONDecoder().decode([QuickFolder].self, from: Data(contentsOf: url))
        guard Set(folders.map(\.id)).count == folders.count,
              folders.allSatisfy({ !$0.name.isEmpty && $0.path.hasPrefix("/") && !$0.bookmark.isEmpty }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return folders
    }
    func save(_ folders: [QuickFolder]) throws {
        try PrivateStorage.write(JSONEncoder().encode(folders), to: url)
    }
}
