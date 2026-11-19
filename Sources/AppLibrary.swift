import Foundation

struct AppCategory: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
}

struct SavedApplication: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var bundleID: String?
    var categoryID: UUID?
}

enum LibraryScope: Hashable {
    case all, uncategorized, category(UUID)
    var categoryID: UUID? { if case let .category(id) = self { return id }; return nil }
}

enum LibraryError: LocalizedError {
    case invalidName, duplicateName, missingCategory, unsupportedVersion, invalidApplication, unreadableLibrary
    var errorDescription: String? {
        switch self {
        case .invalidName: return "分类名称需要包含 1–30 个字符。"
        case .duplicateName: return "已经有同名分类了，请换一个名称。"
        case .missingCategory: return "这个分类已不存在，请重新选择。"
        case .unsupportedVersion: return "收纳数据来自更新版本，当前版本不会覆盖它。"
        case .invalidApplication: return "请选择有效的 macOS 应用（.app）。"
        case .unreadableLibrary: return "收纳数据暂时无法读取，原文件已保留。请先修复或恢复数据，再重新打开窗匣。"
        }
    }
}

struct AppLibrary: Codable, Equatable {
    var version = 2
    var categories: [AppCategory] = [
        AppCategory(id: UUID(uuidString: "05BC6CB3-3D12-4300-8C22-000000000001")!, name: "工作", symbol: "briefcase"),
        AppCategory(id: UUID(uuidString: "05BC6CB3-3D12-4300-8C22-000000000002")!, name: "开发", symbol: "chevron.left.forwardslash.chevron.right"),
        AppCategory(id: UUID(uuidString: "05BC6CB3-3D12-4300-8C22-000000000003")!, name: "学习", symbol: "book"),
        AppCategory(id: UUID(uuidString: "05BC6CB3-3D12-4300-8C22-000000000004")!, name: "生活", symbol: "sparkles")
    ]
    var applications: [SavedApplication] = []
    var pinnedApplicationIDs: [UUID] = []

    init() {}
    private enum CodingKeys: String, CodingKey { case version, categories, applications, pinnedApplicationIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        guard [1, 2].contains(storedVersion) else { throw LibraryError.unsupportedVersion }
        version = 2
        categories = try values.decode([AppCategory].self, forKey: .categories)
        applications = try values.decode([SavedApplication].self, forKey: .applications)
        // Preserve the order users saw in v1, then allow explicit manual ordering.
        if storedVersion == 1 {
            applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let pins = try values.decodeIfPresent([UUID].self, forKey: .pinnedApplicationIDs) ?? []
        let valid = Set(applications.map(\.id))
        var seen = Set<UUID>()
        pinnedApplicationIDs = pins.filter { valid.contains($0) && seen.insert($0).inserted }
    }
    var pinnedApplications: [SavedApplication] {
        let byID = Dictionary(applications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pinnedApplicationIDs.compactMap { byID[$0] }
    }

    func applications(in scope: LibraryScope) -> [SavedApplication] {
        applications.filter { app in
            switch scope {
            case .all: return true
            case .uncategorized: return app.categoryID == nil
            case let .category(id): return app.categoryID == id
            }
        }
    }
    func preview(in scope: LibraryScope) -> [SavedApplication] { Array(applications(in: scope).prefix(4)) }
    func folderPreview(in scope: LibraryScope) -> AppFolderPreview { AppFolderPreview(applications: applications(in: scope)) }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    mutating func add(name: String, path: String, bundleID: String?, categoryID: UUID?) throws {
        try validateCategory(categoryID)
        let path = Self.canonicalPath(path)
        if let index = applications.firstIndex(where: { $0.path == path }) {
            applications[index].name = name
            if let categoryID, applications[index].categoryID != categoryID { try moveApplication(id: applications[index].id, categoryID: categoryID) }
        } else {
            applications.append(SavedApplication(id: UUID(), name: name, path: path, bundleID: bundleID, categoryID: categoryID))
        }
    }

    @discardableResult
    mutating func addCategory(name: String, symbol: String) throws -> UUID {
        let name = try validateName(name)
        let id = UUID()
        categories.append(AppCategory(id: id, name: name, symbol: symbol))
        return id
    }

    mutating func renameCategory(id: UUID, name: String) throws {
        let name = try validateName(name, excluding: id)
        guard let index = categories.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingCategory }
        categories[index].name = name
    }

    mutating func removeCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        for index in applications.indices where applications[index].categoryID == id { applications[index].categoryID = nil }
    }

    mutating func moveApplication(id: UUID, categoryID: UUID?) throws {
        try validateCategory(categoryID)
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        guard applications[index].categoryID != categoryID else { return }
        var app = applications.remove(at: index)
        app.categoryID = categoryID
        applications.append(app)
    }

    mutating func removeApplication(id: UUID) {
        applications.removeAll { $0.id == id }
        pinnedApplicationIDs.removeAll { $0 == id }
    }
    mutating func pinApplication(id: UUID, before target: UUID? = nil) {
        guard applications.contains(where: { $0.id == id }), id != target else { return }
        if let target {
            guard pinnedApplicationIDs.contains(target) else { return }
            pinnedApplicationIDs.removeAll { $0 == id }
            let destination = pinnedApplicationIDs.firstIndex(of: target)!
            pinnedApplicationIDs.insert(id, at: destination)
        } else if !pinnedApplicationIDs.contains(id) { pinnedApplicationIDs.append(id) }
    }
    mutating func unpinApplication(id: UUID) { pinnedApplicationIDs.removeAll { $0 == id } }
    mutating func movePinnedToEnd(id: UUID) {
        guard let index = pinnedApplicationIDs.firstIndex(of: id) else { return }
        pinnedApplicationIDs.append(pinnedApplicationIDs.remove(at: index))
    }
    mutating func moveApplicationToEnd(id: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        applications.append(applications.remove(at: index))
    }
    mutating func reorderPinned(id: UUID, offset: Int) {
        guard let index = pinnedApplicationIDs.firstIndex(of: id), pinnedApplicationIDs.indices.contains(index + offset) else { return }
        pinnedApplicationIDs.swapAt(index, index + offset)
    }
    mutating func placeApplication(id: UUID, before target: UUID) {
        guard id != target, let source = applications.firstIndex(where: { $0.id == id }),
              let targetApp = applications.first(where: { $0.id == target }) else { return }
        var app = applications.remove(at: source)
        app.categoryID = targetApp.categoryID
        let destination = applications.firstIndex(where: { $0.id == target })!
        applications.insert(app, at: destination)
    }
    mutating func reorderApplication(id: UUID, offset: Int) {
        guard let app = applications.first(where: { $0.id == id }) else { return }
        let indices = applications.indices.filter { applications[$0].categoryID == app.categoryID }
        guard let index = indices.firstIndex(where: { applications[$0].id == id }), indices.indices.contains(index + offset) else { return }
        applications.swapAt(indices[index], indices[index + offset])
    }
    mutating func sortApplications(in scope: LibraryScope) {
        let ids = Set(applications(in: scope).map(\.id))
        let indices = applications.indices.filter { ids.contains(applications[$0].id) }
        let sorted = indices.map { applications[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for (index, app) in zip(indices, sorted) { applications[index] = app }
    }

    mutating func reorderCategory(id: UUID, offset: Int) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard categories.indices.contains(destination) else { return }
        categories.swapAt(index, destination)
    }

    private func validateCategory(_ id: UUID?) throws {
        if let id, !categories.contains(where: { $0.id == id }) { throw LibraryError.missingCategory }
    }
    private func validateName(_ name: String, excluding: UUID? = nil) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 30 else { throw LibraryError.invalidName }
        guard !categories.contains(where: { $0.id != excluding && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw LibraryError.duplicateName }
        return clean
    }
}

struct LibraryRepository {
    let url: URL
    func load() throws -> AppLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppLibrary() }
        let data = try Data(contentsOf: url)
        var result = try JSONDecoder().decode(AppLibrary.self, from: data)
        guard result.version == 2 else { throw LibraryError.unsupportedVersion }
        // Invalid category references must not make applications disappear.
        let ids = Set(result.categories.map(\.id))
        for index in result.applications.indices {
            if let id = result.applications[index].categoryID, !ids.contains(id) { result.applications[index].categoryID = nil }
        }
        return result
    }
    func save(_ library: AppLibrary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try PrivateStorage.ensureDirectory(url.deletingLastPathComponent())
        if library.version == 2,
           let original = try? Data(contentsOf: url),
           let header = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
           header["version"] as? Int == 1 {
            let backups = url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
            try PrivateStorage.write(original, to: backups.appendingPathComponent("library-v1-\(UUID().uuidString).json"))
        }
        try PrivateStorage.write(data, to: url)
    }
}

/// Three direct launch targets and one aggregate expansion target.
struct AppFolderPreview {
    let direct: [SavedApplication]
    let stacked: [SavedApplication]
    let remainingCount: Int
    init(applications: [SavedApplication]) {
        direct = Array(applications.prefix(3))
        stacked = Array(applications.dropFirst(3).prefix(3))
        remainingCount = max(0, applications.count - 3)
    }
}
