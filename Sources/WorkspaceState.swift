import Foundation

enum WorkspaceMode: Int, Codable, CaseIterable {
    case windows, applications, files
    var title: String { switch self { case .windows: return "窗口"; case .applications: return "应用"; case .files: return "文件" } }
    var subtitle: String { switch self { case .windows: return "窗口收纳"; case .applications: return "应用资源库"; case .files: return "桌面文件夹" } }
}

/// Kept separate from the app library so remembering a page never rewrites categories.
struct WorkspaceStateRepository {
    let url: URL
    private struct State: Codable { let mode: WorkspaceMode }

    static var standard: WorkspaceStateRepository {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowNest", isDirectory: true)
        return WorkspaceStateRepository(url: folder.appendingPathComponent("workspace.json"))
    }
    func load() throws -> WorkspaceMode {
        guard FileManager.default.fileExists(atPath: url.path) else { return .windows }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: url)).mode
    }
    func save(_ mode: WorkspaceMode) throws {
        let data = try JSONEncoder().encode(State(mode: mode))
        try PrivateStorage.write(data, to: url)
    }
}
