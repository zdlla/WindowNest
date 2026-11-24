import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLook
private typealias DesktopBoxState<Value> = SwiftUI.State<Value>

struct DesktopBoxConfiguration: Codable, Identifiable, Equatable {
    var id = UUID()
    var folders: [QuickFolder] = []
    var selected: UUID?
    var theme = "system"
    var opacity = 0.88
    var list = true
    var visible = true
    var x: Double = 120
    var y: Double = 120
    var width: Double = 700
    var height: Double = 320
    var browsePaths:[String:[String]]? = nil
}
private struct DesktopBoxArchive: Codable {
    var enabled: Bool
    var boxes: [DesktopBoxConfiguration]
    var locked: [UUID]
    var collapsed:[UUID]? = nil
    var layouts:DesktopBoxLayoutMemory? = nil
    var showOnLaunch:Bool? = nil
}

private final class DesktopBoxWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private struct DesktopBoxDragHandle: NSViewRepresentable {
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) {
            if window?.isMovable == true { window?.performDrag(with:event) }
        }
    }
    func makeNSView(context:Context) -> Handle { Handle() }
    func updateNSView(_ nsView:Handle,context:Context) {}
}
private struct DesktopBoxResizeHandle: NSViewRepresentable {
    final class Handle: NSView {
        override func draw(_ dirtyRect:NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
            let p=NSBezierPath(); p.move(to:NSPoint(x:4,y:3));p.line(to:NSPoint(x:13,y:12));p.move(to:NSPoint(x:9,y:3));p.line(to:NSPoint(x:13,y:7));p.stroke()
        }
        override func mouseDown(with event:NSEvent) {
            guard let window, window.styleMask.contains(.resizable) else { return }
            let initial=window.frame, mouse=NSEvent.mouseLocation
            while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let now=NSEvent.mouseLocation
                let width=max(window.contentMinSize.width,initial.width+now.x-mouse.x)
                let height=max(window.contentMinSize.height,initial.height-now.y+mouse.y)
                window.setFrame(NSRect(x:initial.minX,y:initial.maxY-height,width:width,height:height),display:true)
            }
            (window.delegate as? DesktopFileBoxController)?.windowDidEndLiveResize(Notification(name:NSWindow.didEndLiveResizeNotification,object:window))
        }
    }
    func makeNSView(context:Context)->Handle { Handle() }
    func updateNSView(_ nsView:Handle,context:Context) {}
}

struct DesktopBoxItem: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let directory: Bool
    var package=false
    var symbolicLink=false
    var acceptsChildren:Bool { directory && !package && !symbolicLink }
}

/// Explicit, shallow directory listing. No indexing, content reads, thumbnails,
/// recursive traversal, telemetry or persisted file inventories.
enum DesktopBoxDirectory {
    static func read(_ url: URL) throws -> [DesktopBoxItem] {
        var failure: Error?
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: { _, error in failure = error; return false }) else { throw CocoaError(.fileReadNoPermission) }
        var result: [DesktopBoxItem] = []
        for case let child as URL in walker {
            if Task.isCancelled { throw CancellationError() }
            let values=try? child.resourceValues(forKeys:[.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey])
            result.append(DesktopBoxItem(url:child,directory:values?.isDirectory == true,package:values?.isPackage == true,symbolicLink:values?.isSymbolicLink == true))
            if result.count >= 2000 { break }
        }
        if let failure { throw failure }
        return result.sorted {
            if $0.directory != $1.directory { return $0.directory }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}

@MainActor final class DesktopBoxModel: ObservableObject {
    @Published var locked = false
    @Published var collapsed = false
    @Published var configuration: DesktopBoxConfiguration
    @Published private(set) var items: [DesktopBoxItem] = []
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var notice: String?
    @Published var selectedItem:URL?
    @Published var renameTarget:URL?
    @Published private(set) var fileOperationActive = false
    var changed: (() -> Void)?
    private var request: Task<Void, Never>?
    private var generation = UUID()
    init(_ configuration: DesktopBoxConfiguration) { self.configuration = configuration }
    var folder: QuickFolder? { configuration.folders.first { $0.id == configuration.selected } ?? configuration.folders.first }
    var pathComponents:[String] { folder.flatMap { configuration.browsePaths?[$0.id.uuidString] } ?? [] }
    func navigate(to components:[String]) {
        guard !fileOperationActive,let folder else { return }
        var paths=configuration.browsePaths ?? [:];paths[folder.id.uuidString]=components
        selectedItem=nil;renameTarget=nil
        configuration.browsePaths=paths;changed?();refresh()
    }
    func enter(_ item:DesktopBoxItem) {
        guard item.acceptsChildren,items.contains(where:{$0.id==item.id}) else { return }
        navigate(to:pathComponents+[item.url.lastPathComponent])
    }
    func createFolder() {
        guard !fileOperationActive,let folder else { return }
        let path=pathComponents;fileOperationActive=true;notice=nil
        Task { @MainActor in
            defer { self.fileOperationActive=false }
            do {
                let created=try await Task.detached(priority:.userInitiated) {
                    let root=try DesktopBoxNavigation.directory(root:folder.resolvedURL(),components:path)
                    return try DesktopBoxFileOperations.createFolder(in:root)
                }.value
                if self.folder?.id==folder.id && self.pathComponents==path {
                    self.selectedItem=created;self.renameTarget=created;self.refresh()
                }
            } catch { self.notice="新建文件夹失败：\(error.localizedDescription)" }
        }
    }
    func createTextFile(name:String,contents:String,completion:@escaping (String?)->Void) {
        createFile(kind:.text,name:name,contents:contents,completion:completion)
    }
    func createFile(kind:DesktopNewFileKind,name:String,contents:String,completion:@escaping (String?)->Void) {
        guard (name as NSString).pathExtension.lowercased()==kind.ext else { completion("\(kind.title) 文件需要保留 .\(kind.ext) 扩展名。");return }
        let templates=Bundle.main.resourceURL?.appendingPathComponent("NewFileTemplates")
        createFileData(name:name,load:{ try kind.data(contents:contents,templates:templates) },completion:completion)
    }
    func createFromTemplate(_ source:URL) {
        createFileData(name:"新建 "+source.lastPathComponent,uniqueName:true,load:{
            let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard values.isRegularFile == true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=50*1024*1024 else { throw CocoaError(.fileReadUnsupportedScheme) }
            let access=source.startAccessingSecurityScopedResource();defer { if access { source.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf:source,options:.mappedIfSafe)
        },completion:{ [weak self] error in if let error { self?.notice=error } })
    }
    private func createFileData(name:String,uniqueName:Bool=false,load:@escaping ()throws->Data,completion:@escaping (String?)->Void) {
        guard !fileOperationActive,let folder else { completion("请先选择可访问的文件夹。");return }
        let path=pathComponents;fileOperationActive=true;notice=nil
        Task { @MainActor in
            defer { self.fileOperationActive=false }
            do {
                let created=try await Task.detached(priority:.userInitiated) {
                    let root=try DesktopBoxNavigation.directory(root:folder.resolvedURL(),components:path)
                    let data=try load()
                    for index in 0..<10000 {
                        let ext=(name as NSString).pathExtension
                        let stem=ext.isEmpty ? name : (name as NSString).deletingPathExtension
                        let candidate=index==0 ? name : "\(stem) \(index+1)"+(ext.isEmpty ? "" : "."+ext)
                        do { return try DesktopBoxFileOperations.createFile(in:root,name:candidate,data:data) }
                        catch DesktopBoxFileError.collision where uniqueName { continue }
                    }
                    throw DesktopBoxFileError.collision
                }.value
                if self.folder?.id==folder.id && self.pathComponents==path { self.selectedItem=created;self.refresh() }
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }
    func requestRename(_ item:DesktopBoxItem) {
        guard !fileOperationActive,items.contains(where:{$0.id==item.id}) else { return }
        selectedItem=item.url;renameTarget=item.url
    }
    func select(_ folder: QuickFolder) { selectedItem=nil;renameTarget=nil;configuration.selected = folder.id; changed?(); refresh() }
    func stop(clearSelection:Bool=true) {
        generation = UUID(); request?.cancel(); request = nil; items = []; loading = false
        if clearSelection { selectedItem=nil;renameTarget=nil }
    }
    func refresh() {
        stop(clearSelection:false)
        guard let folder else { return }
        let token = generation,path=pathComponents; loading = true; error = nil
        request = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { try DesktopBoxDirectory.read(DesktopBoxNavigation.directory(root:folder.resolvedURL(),components:path)) }
            let result = await withTaskCancellationHandler(operation: { await worker.result }, onCancel: { worker.cancel() })
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.loading = false
            switch result {
            case .success(let items):
                self.items = items
                // Enumerator URLs can carry a base URL while newly created URLs
                // are absolute. Compare their normalized paths, not URL storage.
                if let selected=self.selectedItem,!items.contains(where:{$0.url.standardizedFileURL.path==selected.standardizedFileURL.path}) { self.selectedItem=nil;self.renameTarget=nil }
            case .failure: self.error = "无法访问所选文件夹，请连接磁盘或重新选择。"
            }
        }
    }
    func add(_ urls: [URL]) {
        do {
            var next = configuration
            for url in urls {
                let value = try QuickFolder(url: url)
                if !next.folders.contains(where: { $0.path == value.path }) { next.folders.append(value) }
                next.selected = next.folders.first(where: { $0.path == value.path })?.id
            }
            configuration = next; changed?(); refresh()
        } catch { self.error = "无法添加这个文件夹，请重新选择。" }
    }
    func remove(_ id: UUID) {
        configuration.folders.removeAll { $0.id == id }
        if configuration.selected == id { configuration.selected = configuration.folders.first?.id }
        changed?(); refresh()
    }
    func move(_ id: UUID, by offset: Int) {
        guard let index = configuration.folders.firstIndex(where: { $0.id == id }), configuration.folders.indices.contains(index + offset) else { return }
        let value = configuration.folders.remove(at: index); configuration.folders.insert(value, at: index + offset); changed?()
    }
    func receiveDrop(_ providers:[NSItemProvider], asTabs:Bool,intoChild:URL? = nil) -> Bool {
        guard !fileOperationActive, !providers.isEmpty else { return false }
        if let intoChild {
            // Normalize the parent only: directory URL slashes and /var aliases
            // must not prevent a drop, while a final symlink stays identifiable.
            let childPath=intoChild.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(intoChild.lastPathComponent).path
            guard !asTabs,folder != nil,items.contains(where:{
                $0.url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent($0.url.lastPathComponent).path == childPath && $0.acceptsChildren
            }) else { return false }
        }
        let destination = folder,destinationPath=pathComponents
        fileOperationActive = true; notice = nil
        Task { @MainActor in
            defer { self.fileOperationActive = false }
            do {
                var urls:[URL] = []
                for provider in providers {
                    let data:Data = try await withCheckedThrowingContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier) { data,error in
                            if let data { continuation.resume(returning:data) }
                            else { continuation.resume(throwing:error ?? CocoaError(.fileReadUnsupportedScheme)) }
                        }
                    }
                    guard let url=URL(dataRepresentation:data,relativeTo:nil),url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                    if !urls.contains(url) { urls.append(url) }
                }
                if asTabs || destination == nil {
                    guard urls.allSatisfy({ (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true }) else {
                        self.notice = "请先添加一个文件夹选项卡，再拖入文件。"; return
                    }
                    self.add(urls)
                } else if let destination {
                    let failures = await Task.detached(priority:.userInitiated) {
                        var failed=0
                        do {
                            let root=try DesktopBoxNavigation.directory(root:destination.resolvedURL(),components:destinationPath)
                            var target=root
                            if let intoChild {
                                guard intoChild.deletingLastPathComponent().resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path else { throw DesktopBoxFileError.outsideFolder }
                                let values=try intoChild.resourceValues(forKeys:[.isDirectoryKey,.isPackageKey,.isSymbolicLinkKey])
                                guard values.isDirectory == true,values.isPackage != true,values.isSymbolicLink != true else { throw DesktopBoxFileError.outsideFolder }
                                target=intoChild
                            }
                            for url in urls {
                                do { _ = try DesktopBoxFileOperations.move(url,into:target) }
                                catch { failed += 1 }
                            }
                        } catch { failed=urls.count }
                        return failed
                    }.value
                    if self.folder?.id == destination.id && self.pathComponents==destinationPath { self.refresh() }
                    self.notice = failures == 0 ? "已移动到目标文件夹" : "\(urls.count-failures) 项已移动，\(failures) 项未完成。未移除的源项目会保留，请在访达中检查。"
                }
            } catch { self.notice = "无法接收拖入项目，请从访达拖入本机文件或文件夹。" }
        }
        return true
    }

    func rename(_ source:URL, folder:QuickFolder, to name:String, tab:Bool) {
        guard !fileOperationActive else { return }
        let path=pathComponents
        fileOperationActive=true;notice=nil
        Task { @MainActor in
            defer { self.fileOperationActive=false }
            do {
                let updated=try await Task.detached(priority:.userInitiated) {
                    let root=try folder.resolvedURL()
                    let current=try DesktopBoxNavigation.directory(root:root,components:path)
                    return try DesktopBoxFileOperations.rename(tab ? root : source,in:tab ? root.deletingLastPathComponent() : current,to:name)
                }.value
                if tab, let index=self.configuration.folders.firstIndex(where:{$0.id==folder.id}) {
                    self.configuration.folders[index]=try QuickFolder(url:updated,id:folder.id);self.changed?()
                }
                if self.folder?.id == folder.id {
                    if !tab { self.selectedItem=updated;self.renameTarget=nil }
                    self.refresh()
                }
            } catch { self.notice = "重命名未完成：\(error.localizedDescription)" }
        }
    }
}

@MainActor final class DesktopFileBoxController: NSObject, NSWindowDelegate, ObservableObject {
    @Published private(set) var models: [DesktopBoxModel] = []
    @Published var error: String?
    @Published private(set) var enabled = true
    @Published private(set) var showOnLaunch=true
    @Published var workspaceSelection: UUID?
    private var workspaceVisible = false
    private var windows: [UUID: NSWindow] = [:]
    private let preferences: AppearanceStore
    private let configURL: URL
    private var writable = true
    private var pendingSave: Task<Void, Never>?
    private var screenObserver:NSObjectProtocol?
    private var screenTask:Task<Void,Never>?
    private var fittingScreens=false
    private var shuttingDown=false
    private var layouts=DesktopBoxLayoutMemory()
    private var environment:DesktopDisplayEnvironment
    private let displayEnvironment:()->DesktopDisplayEnvironment
    private var startupTask:Task<Void,Never>?
    private var resumeObservers:[NSObjectProtocol]=[]
    init(preferences: AppearanceStore, configURL: URL? = nil,displayEnvironment:(()->DesktopDisplayEnvironment)? = nil) {
        let provider=displayEnvironment ?? { DesktopDisplayEnvironment.current() }
        self.displayEnvironment=provider;environment=provider()
        self.preferences = preferences
        self.configURL = configURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowNest/desktop-boxes.json")
        super.init()
        do {
            if FileManager.default.fileExists(atPath: self.configURL.path) {
                let data = try Data(contentsOf:self.configURL)
                let archive = try? JSONDecoder().decode(DesktopBoxArchive.self,from:data)
                let values = try archive?.boxes ?? JSONDecoder().decode([DesktopBoxConfiguration].self, from:data)
                enabled = archive?.enabled ?? true
                showOnLaunch=archive?.showOnLaunch ?? true
                layouts=archive?.layouts ?? DesktopBoxLayoutMemory()
                guard Set(values.map(\.id)).count == values.count else { throw CocoaError(.coderReadCorrupt) }
                models = values.map { DesktopBoxModel($0) }
                models.forEach { $0.locked = archive?.locked.contains($0.configuration.id) == true }
                models.forEach { $0.collapsed = archive?.collapsed?.contains($0.configuration.id) == true }
            }
        } catch { writable = false; self.error = "无法读取桌面文件盒设置，原文件已保留。" }
        models.forEach(bind)
        workspaceSelection=models.first?.configuration.id
        screenObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        for name in [NSWorkspace.didWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            resumeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restore() }
            })
        }
    }
    var workspaceModel:DesktopBoxModel? { models.first { $0.configuration.id == workspaceSelection } ?? models.first }
    func selectWorkspace(_ model:DesktopBoxModel) {
        let previous=workspaceModel
        workspaceSelection=model.configuration.id
        if let previous,previous !== model,windows[previous.configuration.id]?.isVisible != true { previous.stop() }
        if workspaceVisible { model.refresh() }
    }
    func setWorkspaceVisible(_ visible:Bool) {
        guard workspaceVisible != visible else { return };workspaceVisible=visible
        if visible { workspaceModel?.refresh() }
        else if let model=workspaceModel,windows[model.configuration.id]?.isVisible != true { model.stop() }
    }
    private func screensChanged() {
        // Keep the outgoing model/profile intact. AppKit may already have
        // moved the NSWindow by the time this notification reaches us.
        fittingScreens=true;pendingSave?.cancel();pendingSave=nil
        screenTask?.cancel()
        screenTask=Task { @MainActor [weak self] in
            // AppKit may reposition windows after the screen notification.
            // Reconcile once after it settles, then once more; no polling.
            for delay in [150,450] {
                try? await Task.sleep(for:.milliseconds(delay))
                guard let self,!Task.isCancelled else { return };self.fitWindows()
            }
        }
    }
    private func fitWindows() {
        let nextEnvironment=displayEnvironment(),screens=nextEnvironment.screens
        guard !screens.isEmpty else { return }
        let changed=nextEnvironment.key != environment.key
        environment=nextEnvironment
        fittingScreens=true
        for model in models {
            let fallback=CGRect(x:model.configuration.x,y:model.configuration.y,width:model.configuration.width,height:model.configuration.height)
            let old=changed ? layouts.frame(for:model.configuration.id,in:environment) ?? fallback : fallback
            let rect=DesktopBoxLayout.fitted(old,screens:screens)
            let visible=DesktopBoxLayout.visibleFrame(rect,collapsed:model.collapsed)
            if let window=windows[model.configuration.id],window.frame != visible {
                window.contentMinSize=NSSize(width:min(360,visible.width),height:model.collapsed ? visible.height : min(180,visible.height))
                window.setFrame(visible,display:true)
            }
            var next=model.configuration
            next.x=rect.minX;next.y=rect.minY;next.width=rect.width;next.height=rect.height
            if next != model.configuration { model.configuration=next }
            layouts.remember(rect,for:model.configuration.id,in:environment)
        }
        fittingScreens=false;save()
    }
    func restore(atLaunch:Bool=false) {
        guard enabled,!shuttingDown else { return }
        // Load a saved profile on cold launch as well as hot-plug transitions.
        for model in models {
            if let rect=layouts.frame(for:model.configuration.id,in:displayEnvironment()) {
                model.configuration.x=rect.minX;model.configuration.y=rect.minY
                model.configuration.width=rect.width;model.configuration.height=rect.height
            }
            if atLaunch && showOnLaunch { model.configuration.visible=true }
        }
        fitWindows()
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        for model in models where model.configuration.visible { show(model) }
        if atLaunch {
            startupTask?.cancel()
            startupTask=Task { @MainActor [weak self] in
                for delay in [300,1200,3000] {
                    try? await Task.sleep(for:.milliseconds(delay))
                    guard let self,!Task.isCancelled,!self.shuttingDown,self.enabled else { return }
                    self.fitWindows()
                    for model in self.models where model.configuration.visible { self.windows[model.configuration.id]?.orderFrontRegardless() }
                }
            }
        }
    }
    func setShowOnLaunch(_ value:Bool) { showOnLaunch=value;save() }
    func setEnabled(_ value:Bool) {
        enabled=value
        if value { restore() } else { windows.values.forEach { $0.orderOut(nil) }; models.forEach { $0.stop() } }
        if !value && workspaceVisible { workspaceModel?.refresh() }
        save()
    }
    func setLocked(_ model:DesktopBoxModel,_ value:Bool) {
        model.locked=value
        if let window=windows[model.configuration.id] {
            window.isMovable = !value
            if value || model.collapsed { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
        }
        objectWillChange.send();save()
    }
    func setCollapsed(_ model:DesktopBoxModel,_ value:Bool) {
        guard model.collapsed != value else { return }
        if let window=windows[model.configuration.id] {
            let expanded=DesktopBoxLayout.expandedFrame(window.frame,rememberedHeight:model.configuration.height,collapsed:model.collapsed)
            fittingScreens=true
            model.configuration.x=expanded.minX;model.configuration.y=expanded.minY
            model.configuration.width=expanded.width;model.configuration.height=expanded.height
            model.collapsed=value
            let target=DesktopBoxLayout.visibleFrame(expanded,collapsed:value)
            window.contentMinSize=NSSize(width:min(360,target.width),height:value ? target.height : min(180,target.height))
            if value || model.locked { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
            window.setFrame(target,display:true)
            fittingScreens=false
            if !value { fitWindows() }
        } else { model.collapsed=value }
        objectWillChange.send();save()
    }
    func create() {
        guard writable else { return }
        enabled=true
        let model = DesktopBoxModel(DesktopBoxConfiguration())
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0,y: 0,width: 1280,height: 800)
        model.configuration.x = screen.minX + 60; model.configuration.y = screen.maxY - 390
        bind(model); models.append(model); save(); show(model)
        workspaceSelection=model.configuration.id
    }
    private func bind(_ model: DesktopBoxModel) {
        model.changed = { [weak self, weak model] in
            guard let self, let model else { return }; self.applyTheme(model); self.objectWillChange.send(); self.save()
        }
    }
    func show(_ model: DesktopBoxModel) {
        guard writable else { return }
        if displayEnvironment().key != environment.key { fitWindows() }
        enabled=true
        model.configuration.visible = true
        if let window = windows[model.configuration.id] { window.orderFrontRegardless(); model.refresh(); save(); return }
        let c = model.configuration
        let remembered=layouts.frame(for:c.id,in:environment) ?? CGRect(x:c.x,y:c.y,width:c.width,height:c.height)
        let expanded=DesktopBoxLayout.fitted(remembered,screens:environment.screens)
        var fitted=c;fitted.x=expanded.minX;fitted.y=expanded.minY;fitted.width=expanded.width;fitted.height=expanded.height
        if fitted != model.configuration { model.configuration=fitted }
        layouts.remember(expanded,for:model.configuration.id,in:environment)
        let rect=DesktopBoxLayout.visibleFrame(expanded,collapsed:model.collapsed)
        let window = DesktopBoxWindow(contentRect: rect, styleMask: [.borderless,.resizable], backing: .buffered, defer: false)
        window.title = "窗匣 · 桌面文件盒"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.delegate = self
        window.hidesOnDeactivate=false
        window.contentMinSize = NSSize(width:min(360,rect.width),height:model.collapsed ? rect.height : min(180,rect.height))
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        let view = DesktopFileBoxView(model: model,onCollapse:{[weak self,weak model] in if let self,let model { self.setCollapsed(model,!model.collapsed) }}, onAdd: { [weak self, weak model] in
            guard let self, let model else { return }; self.choose(model)
        }, onNew: { [weak self] in self?.create() }, onLock: { [weak self,weak model] in
            if let self,let model { self.setLocked(model,!model.locked) }
        }, onClose: { [weak window] in window?.close() },onRename:{ [weak self,weak model] item,tab in
            if let self,let model { self.rename(model,item:item,tab:tab) }
        })
        let host = NSHostingController(rootView: ThemedWorkspace(preferences: preferences, content: view)); host.sceneBridgingOptions = []
        window.contentViewController = host; windows[c.id] = window
        window.setFrame(window.frameRect(forContentRect:rect),display:false)
        window.isMovable = !model.locked
        if model.locked || model.collapsed { window.styleMask.remove(.resizable) }
        applyTheme(model); window.orderFrontRegardless(); model.refresh(); save()
    }
    private func applyTheme(_ model: DesktopBoxModel) {
        let name: NSAppearance.Name? = model.configuration.theme == "light" ? .aqua : model.configuration.theme == "dark" ? .darkAqua : nil
        windows[model.configuration.id]?.appearance = name.flatMap { NSAppearance(named: $0) }
    }
    func choose(_ model: DesktopBoxModel, parent:NSWindow? = nil) {
        guard let window = parent ?? windows[model.configuration.id] ?? NSApp.keyWindow else { return }
        let picker = NSOpenPanel(); picker.title = "选择要展示的文件夹"; picker.prompt = "添加选项卡"
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false
        // No directory is preselected, enumerated or inferred from Documents.
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        let level = window.level; window.level = .normal
        picker.beginSheetModal(for: window) { response in
            window.level = level
            if response == .OK { model.add(picker.urls) }
        }
    }
    private func rename(_ model:DesktopBoxModel,item:DesktopBoxItem?,tab:QuickFolder?,parent:NSWindow? = nil) {
        guard !model.fileOperationActive,let window=parent ?? windows[model.configuration.id] ?? NSApp.keyWindow,let folder=tab ?? model.folder else { return }
        let alert=NSAlert();alert.messageText="重命名";alert.informativeText="输入新的完整名称。文件扩展名会一并修改。"
        alert.addButton(withTitle:"重命名");alert.addButton(withTitle:"取消")
        let field=NSTextField(string:tab?.name ?? item?.url.lastPathComponent ?? "")
        field.frame=NSRect(x:0,y:0,width:320,height:24);alert.accessoryView=field
        let level=window.level;window.level = .normal;NSApp.activate();window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for:window) { response in
            window.level=level
            if response == .alertFirstButtonReturn {
                model.rename(item?.url ?? URL(fileURLWithPath:folder.path),folder:folder,to:field.stringValue,tab:tab != nil)
            }
        }
        alert.window.initialFirstResponder=field
    }
    func windowDidMove(_ notification: Notification) { capture(notification) }
    func windowDidEndLiveResize(_ notification: Notification) { capture(notification) }
    private func capture(_ notification: Notification) {
        guard !fittingScreens,!shuttingDown else { return }
        guard displayEnvironment().key == environment.key else { screensChanged();return }
        guard let window = notification.object as? NSWindow, let id = windows.first(where: { $0.value === window })?.key,
              let model = models.first(where: { $0.configuration.id == id }) else { return }
        let rect = DesktopBoxLayout.expandedFrame(window.contentRect(forFrameRect: window.frame),rememberedHeight:model.configuration.height,collapsed:model.collapsed)
        model.configuration.x = rect.minX; model.configuration.y = rect.minY
        model.configuration.width = rect.width; model.configuration.height = rect.height
        layouts.remember(rect,for:id,in:environment)
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }; self?.save()
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard !shuttingDown else { return }
        guard let window = notification.object as? NSWindow, let id = windows.first(where: { $0.value === window })?.key,
              let model = models.first(where: { $0.configuration.id == id }) else { return }
        model.stop(); model.configuration.visible = false; windows[id] = nil
        if workspaceVisible && workspaceModel === model { model.refresh() };save()
    }
    func save() {
        pendingSave?.cancel(); pendingSave = nil
        guard writable else { return }
        do { try PrivateStorage.write(JSONEncoder().encode(DesktopBoxArchive(enabled:enabled,boxes:models.map(\.configuration),locked:models.filter(\.locked).map { $0.configuration.id },collapsed:models.filter(\.collapsed).map { $0.configuration.id },layouts:layouts,showOnLaunch:showOnLaunch)), to: configURL) }
        catch { self.error = "无法保存桌面文件盒设置。" }
    }
    func embeddedView(_ model:DesktopBoxModel)->some View {
        DesktopFileBoxView(model:model,onCollapse:{[weak self] in self?.setCollapsed(model,!model.collapsed)},onAdd:{[weak self] in self?.choose(model,parent:NSApp.keyWindow)},onNew:{[weak self] in self?.create()},onLock:{[weak self] in self?.setLocked(model,!model.locked)},onClose:{[weak self] in self?.windows[model.configuration.id]?.close()},onRename:{[weak self] item,tab in self?.rename(model,item:item,tab:tab,parent:NSApp.keyWindow)},embedded:true)
    }
    func shutdown() {
        shuttingDown=true;startupTask?.cancel()
        for observer in resumeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) };resumeObservers=[]
        screenTask?.cancel();if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) };screenObserver=nil
        save();models.forEach { $0.stop() }
    }
}

private struct DesktopFileBoxView: View {
    @ObservedObject var model: DesktopBoxModel
    @Environment(\.workspaceAccent) private var accent
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onCollapse:()->Void
    let onAdd: () -> Void
    let onNew: () -> Void
    let onLock: () -> Void
    let onClose: () -> Void
    let onRename:(DesktopBoxItem?,QuickFolder?)->Void
    var embedded=false
    private var folded:Bool { model.collapsed && !embedded }
    @DesktopBoxState private var contentDropTargeted = false
    @DesktopBoxState private var tabsDropTargeted = false
    @DesktopBoxState private var childDropTarget:URL?
    @DesktopBoxState private var previewURL:URL?
    @DesktopBoxState private var creatingFile=false
    @DesktopBoxState private var newFileKind:DesktopNewFileKind = .text
    @DesktopBoxState private var createError:String?
    @StateObject private var hostingWindow=DesktopBoxWindowReference()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName:model.locked ? "lock.fill" : "circle.grid.2x2.fill")
                    .foregroundStyle(accent).frame(width:22,height:28)
                    .overlay { DesktopBoxDragHandle() }.help(model.locked ? "文件盒已固定" : "拖动这里移动文件盒")
                if folded {
                    Text(model.folder?.name ?? "文件盒").font(.system(size:12,weight:.semibold)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(Array(model.configuration.folders.enumerated()), id: \.element.id) { index, folder in
                            Button { model.select(folder) } label: {
                                Text(folder.name).lineLimit(1).padding(.horizontal,12).frame(height:28)
                                    .background(model.folder?.id == folder.id ? accent.opacity(0.16) : .clear, in: Capsule())
                            }.buttonStyle(NativePressStyle(scaleLabel:true)).nativeHoverFeedback(in:Capsule(),selected:model.folder?.id == folder.id).contextMenu {
                                Button("重命名文件夹…") { onRename(nil,folder) }
                                Button("向左移") { model.move(folder.id, by:-1) }.disabled(index == 0)
                                Button("向右移") { model.move(folder.id, by:1) }.disabled(index == model.configuration.folders.count-1)
                                Button("移除选项卡") { model.remove(folder.id) }
                            }
                        }
                    }
                }.scrollIndicators(.never)
                    .background(accent.opacity(tabsDropTargeted ? 0.16 : 0),in:Capsule())
                    .onDrop(of:[UTType.fileURL],isTargeted:$tabsDropTargeted) { providers in
                        tabsDropTargeted=false;contentDropTargeted=false
                        return model.receiveDrop(providers,asTabs:true)
                    }
                    .help("拖入文件夹可添加选项卡")
                }
                Button(action:onCollapse) { Image(systemName:model.collapsed ? "chevron.down" : "chevron.up") }
                    .help(model.collapsed ? "展开文件盒" : "折叠文件盒").accessibilityLabel(model.collapsed ? "展开文件盒" : "折叠文件盒")
                Button(action:onAdd) { Image(systemName:"folder.badge.plus") }.help("添加文件夹选项卡")
                Button { model.refresh() } label: { Image(systemName:"arrow.clockwise") }.help("刷新当前文件夹")
                Button(action:onLock) { Image(systemName:model.locked ? "pin.fill" : "pin") }.help(model.locked ? "解锁位置与尺寸" : "固定到桌面，锁住位置与尺寸")
                Menu {
                    Picker("主题", selection: $model.configuration.theme) {
                        Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }
                    Toggle("列表显示", isOn:$model.configuration.list)
                    Button("新建独立文件盒", action:onNew)
                    Divider()
                    Text("背景不透明度")
                    ForEach([0.55,0.75,0.88,1.0],id:\.self) { value in
                        Button("\(Int(value*100))%\(model.configuration.opacity == value ? " ✓" : "")") { model.configuration.opacity = value }
                    }
                } label: { Image(systemName:"slider.horizontal.3") }.menuStyle(.borderlessButton).fixedSize().help("文件盒主题与布局")
                Button(action:onClose) { Image(systemName:"xmark") }.help("收起文件盒，可从设置恢复")
            }.font(.system(size:12)).buttonStyle(.borderless).padding(10)
            if !folded {
            Divider()
            if let folder=model.folder {
                HStack(spacing:8) {
                    Button { model.navigate(to:Array(model.pathComponents.dropLast())) } label:{Image(systemName:"chevron.left")}
                        .disabled(model.pathComponents.isEmpty || model.fileOperationActive).help("返回上一级")
                    ScrollView(.horizontal) {
                        HStack(spacing:5) {
                            Button(folder.name) { model.navigate(to:[]) }
                            ForEach(Array(model.pathComponents.enumerated()),id:\.offset) { index,name in
                                Image(systemName:"chevron.right").font(.system(size:8)).foregroundStyle(.tertiary)
                                Button(name) { model.navigate(to:Array(model.pathComponents.prefix(index+1))) }
                            }
                        }
                    }.scrollIndicators(.never)
                    Menu {
                        Button("新建文件夹") { model.createFolder() }
                        newFileCommands
                    } label:{Image(systemName:"plus")}.menuStyle(.borderlessButton).fixedSize()
                        .disabled(model.fileOperationActive).help("在当前目录新建文件夹或文件")
                }.font(.system(size:11)).buttonStyle(.borderless).padding(.horizontal,12).padding(.vertical,6)
                Divider()
            }
            Group {
            if model.folder == nil {
                VStack(spacing:12) {
                    Image(systemName:"folder.badge.plus").font(.system(size:32)).foregroundStyle(accent)
                    Text("拖入文件夹，或选择文件夹").font(.system(size:16,weight:.semibold))
                    Button("选择文件夹…", action:onAdd).buttonStyle(.borderedProminent)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if model.loading { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if let error = model.error {
                Text(error).foregroundStyle(.secondary).padding().frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if model.items.isEmpty {
                VStack(spacing:10) {
                    Image(systemName:"folder").font(.system(size:30,weight:.light)).foregroundStyle(.tertiary)
                    Text("文件夹为空").font(.system(size:13)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(columns:model.configuration.list ? Array(repeating:GridItem(.flexible(),spacing:12,alignment:.leading),count:DesktopBoxLayout.columns(width:geometry.size.width,textWidth:(String(repeating:"文",count:15) as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:13)]).width,iconWidth:26)) : [GridItem(.adaptive(minimum:108,maximum:152),spacing:12)],alignment:.leading,spacing:model.configuration.list ? 4 : 10) {
                        ForEach(model.items) { item in
                            itemView(item)
                        }
                    }.padding(10)
                }
                }
            }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(nsColor:.textBackgroundColor).opacity(0.10))
            .background {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.selectedItem=nil;model.renameTarget=nil }
            }
            .contextMenu { directoryCommands }
            .onDrop(of:[UTType.fileURL],isTargeted:$contentDropTargeted) { providers in
                contentDropTargeted=false;tabsDropTargeted=false
                return model.receiveDrop(providers,asTabs:false)
            }
            .overlay {
                if contentDropTargeted && childDropTarget == nil {
                    RoundedRectangle(cornerRadius:10).fill(accent.opacity(0.10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(accent,lineWidth:2))
                        .overlay(Text(model.folder == nil ? "添加文件夹选项卡" : "移动到当前文件夹").padding(10).background(.regularMaterial,in:Capsule()))
                        .allowsHitTesting(false)
                }
            }
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background {
            Color.clear.workspacePanelSurface(radius:12)
                .opacity(reduceTransparency || preferences.settings.effects == .minimal ? 1 : min(1,max(0.45,model.configuration.opacity)))
        }
        .overlay(alignment:.top) { accent.opacity(0.14).frame(height:1).allowsHitTesting(false) }
        .background(DesktopBoxWindowCapture(reference:hostingWindow).frame(width:0,height:0))
        .clipShape(RoundedRectangle(cornerRadius:12,style:.continuous))
        .overlay(alignment:.bottomTrailing) {
            if !model.locked && !folded { DesktopBoxResizeHandle().frame(width:18,height:18).help("拖动调整大小") }
        }
        .overlay(alignment:.bottom) {
            if let notice=model.notice {
                HStack { Text(notice).font(.system(size:12)).lineLimit(3);Button { model.notice=nil } label:{Image(systemName:"xmark")} }
                    .padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:10)).padding(8)
            }
        }
        .overlay(alignment:.top) { if model.fileOperationActive { ProgressView().controlSize(.small).padding(8) } }
        .onChange(of: model.configuration.theme) { _,_ in model.changed?() }
        .onChange(of: model.configuration.opacity) { _,_ in model.changed?() }
        .onChange(of: model.configuration.list) { _,_ in model.changed?() }
        .onChange(of:model.configuration.selected) { _,_ in contentDropTargeted=false;tabsDropTargeted=false;childDropTarget=nil }
        .onChange(of:model.pathComponents) { _,_ in contentDropTargeted=false;childDropTarget=nil;previewURL=nil }
        .onChange(of:model.fileOperationActive) { _,_ in contentDropTargeted=false;tabsDropTargeted=false;childDropTarget=nil }
        .onDisappear { contentDropTargeted=false;tabsDropTargeted=false;childDropTarget=nil;previewURL=nil;hostingWindow.endModal() }
        .quickLookPreview($previewURL)
        .sheet(isPresented:$creatingFile,onDismiss:{ hostingWindow.endModal() }) {
            DesktopBoxNewFileSheet(kind:newFileKind,saving:model.fileOperationActive,error:createError,onCancel:{ creatingFile=false },onCreate:{ name,contents in
                createError=nil
                model.createFile(kind:newFileKind,name:name,contents:contents) { error in
                    if let error { createError=error } else { creatingFile=false }
                }
            })
        }
    }
    private func presentNewFile(_ kind:DesktopNewFileKind) {
        guard !model.fileOperationActive else { return }
        newFileKind=kind;createError=nil;hostingWindow.beginModal();creatingFile=true
    }
    private func chooseFileTemplate() {
        guard !model.fileOperationActive,let window=hostingWindow.window ?? NSApp.keyWindow else { return }
        let panel=NSOpenPanel();panel.title="选择用于新建的文件模板";panel.prompt="使用模板"
        panel.message="在当前文件夹创建模板的副本，原文件保持不变。";panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        let level=window.level;window.level = .normal;NSApp.activate();window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for:window) { response in
            window.level=level
            if response == .OK,let url=panel.url { model.createFromTemplate(url) }
        }
    }
    @ViewBuilder private var newFileCommands:some View {
        ForEach(DesktopNewFileKind.allCases) { kind in
            Button { presentNewFile(kind) } label: {
                Label { Text(kind.title) } icon: { Image(nsImage:FileTypeIcons.shared.menuImage(for:kind.ext)).resizable().scaledToFit().frame(width:16,height:16) }
            }
        }
        Divider()
        Button("从其他文件模板新建…") { chooseFileTemplate() }
    }
    @ViewBuilder private var directoryCommands:some View {
        Button("新建文件夹") { model.createFolder() }.disabled(model.folder == nil || model.fileOperationActive)
        Menu("新建文件") { newFileCommands }.disabled(model.folder == nil || model.fileOperationActive)
        Divider()
        Button("刷新") { model.refresh() }.disabled(model.fileOperationActive)
        Button("返回上一级") { model.navigate(to:Array(model.pathComponents.dropLast())) }.disabled(model.pathComponents.isEmpty || model.fileOperationActive)
    }
    private func itemView(_ item: DesktopBoxItem) -> some View {
        DesktopBoxItemCell(item:item,icon:FileTypeIcons.shared.image(for:item.url,directory:item.directory),large:!model.configuration.list,
            selected:model.selectedItem?.standardizedFileURL.path==item.url.standardizedFileURL.path,
            renameRequested:model.renameTarget?.standardizedFileURL.path==item.url.standardizedFileURL.path,disabled:model.fileOperationActive,
            accent:NSColor(accent),reducedMotion:reduceMotion || preferences.settings.effects == .minimal,
            onSelect:{ model.selectedItem=item.url },onDeselect:{ model.selectedItem=nil;model.renameTarget=nil },
            onOpen:{ if item.acceptsChildren { model.enter(item) } else { NSWorkspace.shared.open(item.url) } },
            onPreview:{ previewURL=item.url },onRenameStarted:{ model.renameTarget=nil },onRename:{ name in
                if let folder=model.folder { model.rename(item.url,folder:folder,to:name,tab:false) }
            },onNewFolder:{ model.createFolder() },onNewFile:{ presentNewFile($0) },onTemplate:{ chooseFileTemplate() })
        .frame(height:model.configuration.list ? 34 : 106)
        .modifier(DesktopBoxFolderDropTarget(model:model,item:item,onTarget:{ active in
            if active { childDropTarget=item.url }
            else if childDropTarget == item.url { childDropTarget=nil }
        }))
    }
}

@MainActor private struct DesktopBoxFolderDropDelegate:DropDelegate {
    let model:DesktopBoxModel
    let item:DesktopBoxItem
    let onTarget:(Bool)->Void
    func validateDrop(info:DropInfo)->Bool { item.acceptsChildren && !model.fileOperationActive && info.hasItemsConforming(to:[UTType.fileURL.identifier]) }
    func dropEntered(info:DropInfo) { onTarget(true) }
    func dropExited(info:DropInfo) { onTarget(false) }
    func dropUpdated(info:DropInfo)->DropProposal? { DropProposal(operation:.move) }
    func performDrop(info:DropInfo)->Bool {
        onTarget(false)
        guard item.acceptsChildren else { return false }
        return model.receiveDrop(info.itemProviders(for:[UTType.fileURL.identifier]),asTabs:false,intoChild:item.url)
    }
}
private struct DesktopBoxFolderDropTarget:ViewModifier {
    @ObservedObject var model:DesktopBoxModel
    let item:DesktopBoxItem
    let onTarget:(Bool)->Void
    @Environment(\.workspaceAccent) private var accent
    @DesktopBoxState private var targeted=false
    func body(content:Content)->some View {
        content
            .background(accent.opacity(targeted ? 0.14 : 0),in:RoundedRectangle(cornerRadius:7))
            .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(accent.opacity(targeted ? 0.8 : 0),lineWidth:1.5).allowsHitTesting(false))
            .onDrop(of:[UTType.fileURL],delegate:DesktopBoxFolderDropDelegate(model:model,item:item,onTarget:{ value in targeted=value;onTarget(value) }))
            .onChange(of:model.fileOperationActive) { _,_ in targeted=false;onTarget(false) }
            .onDisappear { targeted=false;onTarget(false) }
    }
}

struct DesktopBoxSettings: View {
    @ObservedObject var controller:DesktopFileBoxController
    var body:some View {
        Section {
            Toggle("显示桌面文件盒",isOn:Binding(get:{controller.enabled},set:{controller.setEnabled($0)}))
            Toggle("启动时显示桌面文件盒",isOn:Binding(get:{controller.showOnLaunch},set:{controller.setShowOnLaunch($0)}))
            HStack {
                Button("新建文件盒…") { controller.create() }
                Button("显示全部") { controller.models.forEach { controller.show($0) } }.disabled(controller.models.isEmpty)
            }
            ForEach(Array(controller.models.enumerated()),id:\.element.configuration.id) { index,model in
                HStack {
                    Text(model.folder?.name ?? "文件盒 \(index+1)").lineLimit(1)
                    Spacer()
                    Button(model.locked ? "解锁" : "固定") { controller.setLocked(model,!model.locked) }
                    Button(model.collapsed ? "展开" : "折叠") { controller.setCollapsed(model,!model.collapsed) }
                    Button("显示与设置") { controller.show(model) }
                }
            }
            if let error=controller.error { Text(error).foregroundStyle(.red) }
        } header:{ Text("桌面文件盒") } footer:{ Text("选择文件夹后才展示其内容。工具栏图钉锁定位置与尺寸；关闭只收起区域，不删除文件。") }
    }
}
