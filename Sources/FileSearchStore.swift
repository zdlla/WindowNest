import AppKit
import SwiftUI
import CryptoKit

@MainActor
final class FileSearchStore: ObservableObject {
    @Published var query = "" { didSet { schedule() } }
    @Published var kind = FileSearchKind.all { didSet { schedule() } }
    @Published var rows: [IndexedFile] = []
    @Published var selection = Set<String>()
    @Published var previewURL: URL?
    @Published var settings: FileSearchSettings
    @Published var ready = false
    @Published var running = false
    @Published var watching = false
    @Published var searching = false
    @Published var count = 0
    @Published var total = 0
    @Published var milliseconds: Double?
    @Published var status = "搜索引擎将在打开全局查找时启动"
    @Published var failure: String?
    @Published var warning: String?
    @Published var message: String?
    var onOpen: (() -> Void)?
    private let client = CardinalClient()
    private var debounce: Task<Void, Never>?
    private var liveRefresh: Task<Void, Never>?
    private var idleStop: Task<Void, Never>?
    private var requestID: UInt64 = 0
    private var visible = false
    private let folder: URL
    private var settingsURL: URL { folder.appendingPathComponent("files.json") }
    private var cacheURL: URL {
        let digest = SHA256.hash(data: Data(settings.root.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("FileSearch/\(digest.prefix(16)).zstd")
    }
    var rootName: String {
        if settings.root == "/" { return "整个 Mac" }
        if settings.root == FileManager.default.homeDirectoryForCurrentUser.path { return "个人目录" }
        return URL(fileURLWithPath: settings.root).lastPathComponent
    }
    var hasSearch: Bool { !kind.query(query).isEmpty }
    var selectedFile: IndexedFile? { rows.first(where: { selection.contains($0.id) }) }

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("WindowNest")
        settings = FileSearchSettings()
        if let data = try? Data(contentsOf: settingsURL) {
            do { settings = try JSONDecoder().decode(FileSearchSettings.self, from: data) }
            catch { warning = "搜索设置读取失败，暂用默认范围；原文件未覆盖。" }
        }
        client.onEvent = { [weak self] event in self?.receive(event) }
        client.onFailure = { [weak self] text in
            self?.failure = text; self?.ready = false; self?.running = false; self?.searching = false
        }
    }
    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value {
            idleStop?.cancel(); idleStop = nil
            if !running { start() }
            else if ready { schedule() }
        } else {
            debounce?.cancel(); liveRefresh?.cancel(); liveRefresh = nil; requestID += 1
            client.send(id: requestID, query: "", hidden: settings.showHidden, cancel: true)
            searching = false; previewURL = nil
            if running && idleStop == nil {
                idleStop = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, !self.visible else { return }
                    self.client.stop()
                    self.running = false; self.ready = false; self.watching = false
                    self.rows = []; self.selection = []
                    self.status = "文件索引已休眠，打开全局查找时从缓存恢复"
                    self.idleStop = nil
                }
            }
        }
    }
    func start(rebuild: Bool = false) {
        debounce?.cancel(); liveRefresh?.cancel(); liveRefresh = nil; requestID += 1
        ready = false; running = true; searching = false; count = 0; total = 0
        failure = nil; warning = nil; rows = []; selection = []; milliseconds = nil
        status = "正在加载文件索引…"
        client.start(root: settings.root, cache: cacheURL, rebuild: rebuild)
    }
    func refresh() {
        if ready && watching { schedule() }
        else if ready {
            debounce?.cancel(); requestID += 1; ready = false; searching = false
            status = "正在刷新文件索引…"
            client.send(id: requestID, query: "", hidden: settings.showHidden, refresh: true)
        } else { start() }
    }
    func stop() { visible = false; running = false; ready = false; searching = false; debounce?.cancel(); liveRefresh?.cancel(); idleStop?.cancel(); idleStop = nil; client.stop() }
    private func saveSettings() {
        do {
            try PrivateStorage.write(JSONEncoder().encode(settings), to: settingsURL)
        } catch { message = "搜索设置未能保存：\(error.localizedDescription)" }
    }
    func changeRoot(_ root: String) {
        guard root != settings.root else { return }
        settings.root = root; saveSettings(); start()
    }
    func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "选择文件搜索范围"; picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.allowsMultipleSelection = false; picker.prompt = "搜索此文件夹"
        if picker.runModal() == .OK, let url = picker.url { changeRoot(url.path) }
    }
    func toggleHidden() { settings.showHidden.toggle(); saveSettings(); schedule() }
    private func schedule(background: Bool = false) {
        if !background { liveRefresh?.cancel(); liveRefresh = nil }
        debounce?.cancel(); requestID += 1
        if ready { failure = nil }
        let id = requestID
        client.send(id: id, query: "", hidden: settings.showHidden, cancel: true)
        guard visible && ready && hasSearch else {
            searching = false
            if !hasSearch { rows = []; selection = []; total = 0; milliseconds = nil }
            return
        }
        if !background { searching = true }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            guard let self, !Task.isCancelled, self.requestID == id else { return }
            self.client.send(id: id, query: self.kind.query(self.query), hidden: self.settings.showHidden)
        }
    }
    private func receive(_ event: CardinalEvent) {
        if let value = event.count { count = value }
        switch event.event {
        case "loading": status = "正在加载文件索引…"
        case "indexing": ready = false; status = "正在建立索引，已发现 \(count.formatted()) 个项目…"
        case "saving": status = "正在保存索引，\(count.formatted()) 个项目…"
        case "ready":
            ready = true; watching = event.watching ?? false
            status = "\(count.formatted()) 个项目已索引 · " + (watching ? "实时跟踪文件变化" : "点击刷新以更新文件变化")
            schedule()
        case "watchUnavailable": watching = false; warning = "系统暂未允许实时监听；刷新可重新扫描当前范围。"
        case "updated":
            status = "\(count.formatted()) 个项目已索引 · 实时跟踪文件变化"
            if visible && hasSearch && !searching && liveRefresh == nil {
                liveRefresh = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    self.liveRefresh = nil
                    if self.visible && self.ready && !self.searching { self.schedule(background: true) }
                }
            }
        case "results":
            guard event.id == requestID else { return }
            rows = event.rows ?? []; total = event.total ?? rows.count; milliseconds = event.milliseconds
            searching = false; failure = nil
            selection = selection.intersection(Set(rows.map(\.id)))
        case "queryError":
            guard event.id == requestID else { return }
            searching = false; rows = []; selection = []; total = 0
            failure = "查询语法需要调整：\(event.message ?? "请检查括号、引号或筛选条件")"
        case "warning": warning = "索引缓存暂时无法保存，本次仍可搜索。"
        case "error": failure = event.message ?? "无法建立索引"; ready = false; running = false; searching = false
        default: break
        }
    }
    func open(_ file: IndexedFile? = nil) {
        guard ready && !searching else { return }
        guard let file = file ?? selectedFile ?? rows.first else { return }
        guard FileManager.default.fileExists(atPath: file.path) else { message = "文件已移动或删除，请刷新搜索结果。"; refresh(); return }
        if NSWorkspace.shared.open(file.url) { onOpen?() }
        else { message = "无法打开这个文件，请在访达中检查它的访问权限。" }
    }
    func reveal(_ file: IndexedFile? = nil) {
        guard let file = file ?? selectedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    func preview(_ file: IndexedFile? = nil) {
        guard let file = file ?? selectedFile ?? rows.first else { return }
        if FileManager.default.fileExists(atPath: file.path) { previewURL = file.url }
        else { message = "文件已移动或删除，请刷新搜索结果。"; refresh() }
    }
    func copyPath(_ file: IndexedFile? = nil) {
        guard let file = file ?? selectedFile else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string)
    }
}
