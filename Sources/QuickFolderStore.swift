import AppKit
import Combine

@MainActor final class QuickFolderStore: ObservableObject {
    @Published private(set) var folders: [QuickFolder] = []
    @Published var error: String?
    private let repository: QuickFolderRepository
    private var writable = true
    private var choosing = false

    init(repository: QuickFolderRepository = .standard) {
        self.repository = repository
        do { folders = try repository.load() }
        catch { writable = false; self.error = "未能读取固定文件夹，原文件已保留。\(error.localizedDescription)" }
    }

    func chooseFolders(completion: (() -> Void)? = nil) {
        guard !choosing, writable else { completion?(); return }
        choosing = true
        let picker = NSOpenPanel()
        picker.title = "固定到顶部速览"
        picker.message = "选择常用文件夹，之后可以从顶部速览直接用访达打开。"
        picker.prompt = "固定文件夹"
        picker.canChooseFiles = false; picker.canChooseDirectories = true
        picker.canCreateDirectories = false; picker.allowsMultipleSelection = true
        picker.treatsFilePackagesAsDirectories = false
        let parent = NSApp.keyWindow.flatMap { $0.isVisible ? $0 : nil }
        NSApp.activate()
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.choosing = false
                if response == .OK { self.add(picker.urls) }
                completion?()
            }
        }
        if let parent { picker.beginSheetModal(for: parent, completionHandler: finish) }
        else { finish(picker.runModal()) }
    }

    func add(_ urls: [URL]) {
        guard writable else { return }
        do {
            var next = folders
            var paths = Set(folders.map { (try? $0.resolvedURL().path) ?? $0.path })
            for url in urls {
                let folder = try QuickFolder(url: url)
                if paths.insert(folder.path).inserted { next.append(folder) }
            }
            persist(next)
        } catch { self.error = "无法固定文件夹：\(error.localizedDescription)" }
    }

    func remove(_ id: UUID) { persist(folders.filter { $0.id != id }) }
    func move(_ id: UUID, by offset: Int) {
        guard let index = folders.firstIndex(where: { $0.id == id }), folders.indices.contains(index + offset) else { return }
        var next = folders; let folder = next.remove(at: index); next.insert(folder, at: index + offset); persist(next)
    }

    func open(_ folder: QuickFolder, completion: @escaping (String?) -> Void) {
        do {
            let url = try folder.resolvedURL()
            // Refresh moved/renamed bookmarks without changing their position.
            if let index = folders.firstIndex(where: { $0.id == folder.id }),
               url.path != folder.path, let refreshed = try? QuickFolder(url: url, id: folder.id) {
                var next = folders; next[index] = refreshed; persist(next)
            }
            guard let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                completion("当前系统无法找到访达。"); return
            }
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: finder, configuration: configuration) { _, error in
                Task { @MainActor in completion(error.map { "无法用访达打开文件夹：\($0.localizedDescription)" }) }
            }
        } catch {
            completion("找不到“\(folder.name)”或当前无法访问，请连接所在磁盘，或重新固定这个文件夹。")
        }
    }

    private func persist(_ next: [QuickFolder]) {
        guard writable, next != folders else { return }
        do { try repository.save(next); folders = next; error = nil }
        catch { self.error = "未能保存固定文件夹：\(error.localizedDescription)" }
    }
}
