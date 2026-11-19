import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstalledApplication: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let bundleID: String?
    static func read(_ url: URL) throws -> InstalledApplication {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let executable = bundle.executableURL, FileManager.default.fileExists(atPath: executable.path) else { throw LibraryError.invalidApplication }
        let display = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(name: display, path: url.path, bundleID: bundle.bundleIdentifier)
    }
}

@MainActor
final class AppLibraryStore: ObservableObject {
    @Published private(set) var library: AppLibrary
    @Published var scope: LibraryScope = .all
    @Published var query = ""
    @Published var showAddApplications = false
    @Published var catalog: [InstalledApplication] = []
    @Published var catalogLoading = false
    @Published var message: String?
    @Published var notice: String?
    @Published var runningBundleIDs: Set<String> = []
    @Published var pickerQuery = ""
    @Published var pickerSelection: Set<String> = []
    @Published var pickerCategory: UUID?
    @Published var pickerPins = false
    var onLaunch: (() -> Void)?
    let repository: LibraryRepository
    let undoManager = UndoManager()
    private var writable = true
    private var icons: [String: NSImage] = [:]
    private var observers: [NSObjectProtocol] = []

    init(repository: LibraryRepository? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowNest", isDirectory: true)
        self.repository = repository ?? LibraryRepository(url: folder.appendingPathComponent("library.json"))
        do { library = try self.repository.load() }
        catch { library = AppLibrary(); writable = false; message = "\(LibraryError.unreadableLibrary.localizedDescription)\n\(error.localizedDescription)" }
        refreshRunning()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunning() }
            })
        }
    }

    var title: String {
        switch scope {
        case .all: return "全部应用"
        case .uncategorized: return "未分类"
        case let .category(id): return library.categories.first { $0.id == id }?.name ?? "应用收纳"
        }
    }
    var filtered: [SavedApplication] {
        library.applications(in: scope).filter { app in
            WindowNaming.matches(query: query, fields: [app.name, categoryName(app.categoryID), app.path])
        }
    }
    var filteredCatalog: [InstalledApplication] {
        catalog.filter { WindowNaming.matches(query: pickerQuery, fields: [$0.name, $0.path]) }
    }
    func categoryName(_ id: UUID?) -> String { library.categories.first { $0.id == id }?.name ?? "未分类" }
    func count(_ scope: LibraryScope) -> Int {
        library.applications.filter {
            switch scope { case .all: return true; case .uncategorized: return $0.categoryID == nil; case let .category(id): return $0.categoryID == id }
        }.count
    }
    func icon(_ path: String) -> NSImage {
        if let image = icons[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image
        return image
    }
    func available(_ app: SavedApplication) -> Bool { FileManager.default.fileExists(atPath: app.path) }

    private func transact(_ mutation: (inout AppLibrary) throws -> Void) {
        guard writable else { message = LibraryError.unreadableLibrary.localizedDescription; return }
        do {
            var next = library
            try mutation(&next)
            try install(next)
        } catch { message = "未能保存收纳更改：\(error.localizedDescription)" }
    }
    private func install(_ next: AppLibrary) throws {
        guard next != library else { return }
        try repository.save(next)
        let previous = library
        library = next
        undoManager.registerUndo(withTarget: self) { target in
            do { try target.install(previous) }
            catch { target.message = "无法撤销更改：\(error.localizedDescription)" }
        }
        undoManager.setActionName("收纳更改")
        if case let .category(id) = scope, !next.categories.contains(where: { $0.id == id }) { scope = .uncategorized }
    }
    func refreshApplications() {
        icons.removeAll()
        refreshRunning()
        objectWillChange.send()
    }
    func add(_ urls: [URL], category: UUID?, pin: Bool = false, before: UUID? = nil) {
        do {
            let apps = try urls.map(InstalledApplication.read)
            transact { data in
                for app in apps {
                    try data.add(name: app.name, path: app.path, bundleID: app.bundleID, categoryID: pin ? nil : category)
                    guard let id = data.applications.first(where: { $0.path == app.path })?.id else { continue }
                    if pin { data.pinApplication(id: id, before: before) }
                    else if let before { data.placeApplication(id: id, before: before) }
                }
            }
        } catch { message = error.localizedDescription }
    }
    func move(_ id: UUID, to category: UUID?) { transact { try $0.moveApplication(id: id, categoryID: category) } }
    func remove(_ app: SavedApplication) { transact { $0.removeApplication(id: app.id) } }
    func reorder(_ category: AppCategory, offset: Int) { transact { $0.reorderCategory(id: category.id, offset: offset) } }

    func isPinned(_ app: SavedApplication) -> Bool { library.pinnedApplicationIDs.contains(app.id) }
    func pin(_ app: SavedApplication) { transact { $0.pinApplication(id: app.id) } }
    func unpin(_ app: SavedApplication) { transact { $0.unpinApplication(id: app.id) } }
    func reorderApp(_ app: SavedApplication, offset: Int, pinned: Bool = false) {
        transact { data in
            if pinned { data.reorderPinned(id: app.id, offset: offset) }
            else { data.reorderApplication(id: app.id, offset: offset) }
        }
    }
    func orderIndex(_ app: SavedApplication, pinned: Bool = false) -> Int {
        let apps = pinned ? library.pinnedApplications : library.applications(in: app.categoryID.map(LibraryScope.category) ?? .uncategorized)
        return apps.firstIndex(where: { $0.id == app.id }) ?? 0
    }
    func canMove(_ app: SavedApplication, offset: Int, pinned: Bool = false) -> Bool {
        let apps = pinned ? library.pinnedApplications : library.applications(in: app.categoryID.map(LibraryScope.category) ?? .uncategorized)
        return apps.indices.contains(orderIndex(app, pinned: pinned) + offset)
    }
    func sortFolder() { transact { $0.sortApplications(in: scope) } }
    func categoryDialog(editing category: AppCategory? = nil) {
        let alert = NSAlert()
        alert.messageText = category == nil ? "新建应用分类" : "重命名分类"
        alert.informativeText = "按你的使用习惯整理应用。分类和应用图标会自动保存。"
        alert.addButton(withTitle: category == nil ? "创建" : "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: category?.name ?? "")
        field.placeholderString = "例如：科研绘图、办公、常用工具"
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var createdID: UUID?
        transact { data in
            if let category { try data.renameCategory(id: category.id, name: field.stringValue) }
            else { createdID = try data.addCategory(name: field.stringValue, symbol: "folder") }
        }
        if let createdID, library.categories.contains(where: { $0.id == createdID }) { scope = .category(createdID) }
    }
    func deleteCategory(_ category: AppCategory) {
        // Removing a category keeps every app and moves its references to Uncategorized.
        transact { $0.removeCategory(id: category.id) }
        if scope == .category(category.id) { scope = .uncategorized }
    }

    func beginAdding() {
        pickerPins = false
        pickerSelection = []
        pickerQuery = ""
        pickerCategory = scope.categoryID
        showAddApplications = true
        loadCatalog()
    }
    func beginPinning() { beginAdding(); pickerPins = true; pickerCategory = nil }
    func chooseFiles(category: UUID?, pin: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "选择要收纳的应用"
        panel.prompt = "添加应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { add(panel.urls, category: category, pin: pin) }
    }
    func addPickerSelection() {
        add(catalog.filter { pickerSelection.contains($0.path) }.map { URL(fileURLWithPath: $0.path) }, category: pickerCategory, pin: pickerPins)
        showAddApplications = false
    }
    func loadCatalog() {
        guard !catalogLoading else { return }
        catalogLoading = true
        let roots = ["/Applications", "/System/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [String: InstalledApplication] = [:]
            for path in roots {
                let root = URL(fileURLWithPath: path)
                guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in walker {
                    if url.pathExtension.lowercased() == "app" {
                        walker.skipDescendants()
                        if let app = try? InstalledApplication.read(url) { found[app.path] = app }
                    } else if url.pathComponents.count - root.pathComponents.count >= 3 { walker.skipDescendants() }
                }
            }
            let result = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self?.catalog = result
                self?.catalogLoading = false
            }
        }
    }

    func launch(_ app: SavedApplication) {
        guard available(app) else { message = "找不到“\(app.name)”。应用可能被移动或移除了，请重新添加它。"; return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.message = "无法打开“\(app.name)”：\(error.localizedDescription)" }
                else { self.onLaunch?() }
            }
        }
    }
    func reveal(_ app: SavedApplication) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
    private func refreshRunning() { runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }

    func acceptDrop(_ providers: [NSItemProvider], category: UUID?, pin: Bool = false, before: UUID? = nil) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.canLoadObject(ofClass: NSString.self) }
        for provider in supported {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? URL { url = value }
                    else if let string = item as? String { url = URL(string: string) }
                    else { url = nil }
                    if let url { Task { @MainActor in self?.add([url], category: category, pin: pin, before: before) } }
                }
            } else {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                    guard let text = value as? String, text.hasPrefix("windownest-app:"),
                          let id = UUID(uuidString: String(text.dropFirst("windownest-app:".count))) else { return }
                    Task { @MainActor in
                        guard let self else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.transact { data in
                                if pin {
                                    data.pinApplication(id: id, before: before)
                                    if before == nil { data.movePinnedToEnd(id: id) }
                                }
                                else if let before { data.placeApplication(id: id, before: before) }
                                else { try data.moveApplication(id: id, categoryID: category); data.moveApplicationToEnd(id: id) }
                            }
                        }
                    }
                }
            }
        }
        return !supported.isEmpty
    }
}
