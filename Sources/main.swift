import AppKit
import SwiftUI
import ApplicationServices
import Combine
import QuartzCore
import Darwin
import ServiceManagement

@MainActor
final class WorkspaceWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    private var window: WorkspaceWindow!
    private var store: WindowStore!
    private var library: AppLibraryStore!
    private var files: FileSearchStore!
    private var preferences: AppearanceStore!
    private var quickFolders: QuickFolderStore!
    private var desktopBoxes: DesktopFileBoxController!
    private var loginItem:LoginItemController!
    private var updates:UpdateController!
    private var topOverview: TopOverviewController?
    private var shortcuts: GlobalShortcutController?
    private var shortcutPreviousApplication: NSRunningApplication?
    private var settingsController: NSWindowController?
    private var pager: WorkspacePager!
    private var status: NSStatusItem?
    private var toolbar: NSToolbar!
    private var pageButtons: PageSwitcher?
    private var toolbarActions: WorkspaceToolbarActions?
    private var subscriptions = Set<AnyCancellable>()
    private var scrollMonitor: Any?
    private var gestureTimeout: Timer?
    private var workspaceSuspended = false
    private var fileSearchPresented = false
    private var launchedAtLogin=false
    private var swipe = PageSwipeTracker()
    private let navigationID = NSToolbarItem.Identifier("WindowNest.Pages")
    private let actionsID = NSToolbarItem.Identifier("WindowNest.Actions")

    func applicationWillFinishLaunching(_ notification:Notification) {
        launchedAtLogin=WorkspaceLaunchContext.isLogin(NSAppleEventManager.shared().currentAppleEvent)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAtLogin = launchedAtLogin || WorkspaceLaunchContext.isLogin(NSAppleEventManager.shared().currentAppleEvent)
        var storageError: Error?
        do { try PrivateStorage.prepareStandardFolder() } catch { storageError = error }
        preferences = AppearanceStore()
        loginItem=LoginItemController()
        quickFolders = QuickFolderStore()
        desktopBoxes = DesktopFileBoxController(preferences: preferences)
        updates=UpdateController()
        updates.mayInstall={ [weak self] in self?.desktopBoxes.models.contains(where:{$0.fileOperationActive}) == false }
        store = WindowStore(previewsEnabled: preferences.settings.previewsEnabled)
        library = AppLibraryStore()
        files = FileSearchStore()
        if let storageError { store.message = "未能限制本机数据目录权限，保存与索引启动时会再次检查：\(storageError.localizedDescription)" }
        window = WorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "窗匣"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WindowNest.Main")
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        let windows = NSHostingController(rootView: ThemedWorkspace(preferences: preferences, content: WindowBrowserView(store: store)))
        let applications = NSHostingController(rootView: ThemedWorkspace(preferences: preferences, content: AppLibraryPage(store: store, library: library)))
        let filePage = NSHostingController(rootView: ThemedWorkspace(preferences: preferences, content: DesktopFolderWorkspace(boxes:desktopBoxes,files:files,workspace:store,onSearchVisibility:{[weak self] visible in self?.fileSearchPresented=visible;self?.updateWorkspaceVisibility()},onReveal:{[weak self] in self?.hide()})))
        filePage.sceneBridgingOptions = []
        // AppKit owns navigation permanently; neither SwiftUI page may replace its toolbar.
        windows.sceneBridgingOptions = []
        applications.sceneBridgingOptions = []
        pager = WorkspacePager(windows: windows, applications: applications, files: filePage, selected: store.mode)
        window.contentViewController = pager
        pager.onTransition = { [weak self] position in
            self?.pageButtons?.move(to: position)
            self?.toolbarActions?.transition(to: position)
        }
        pager.onSelection = { [weak self] mode in self?.didSelectPage(mode) }
        window.center()
        store.onFocus = { [weak self] in self?.hide() }
        library.onLaunch = { [weak self] in self?.hide() }
        files.onOpen = { [weak self] in self?.hide() }
        window.onEscape = { [weak self] in self?.dismissCurrentLayer() }
        makeMenus()
        desktopBoxes.restore(atLaunch:true)
        shortcuts = GlobalShortcutController(preferences: preferences)
        shortcuts?.onTrigger = { [weak self] in
            guard let self else { return }
            let shouldHide = self.window.isKeyWindow && NSApp.isActive && self.window.isVisible
            self.settingsController?.window?.orderOut(nil)
            if shouldHide {
                let previous = self.shortcutPreviousApplication
                self.hide()
                if let previous, !previous.isTerminated { previous.activate(options: []) }
            } else {
                if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
                    self.shortcutPreviousApplication = app
                }
                self.show()
                self.window.orderFrontRegardless()
            }
        }
        topOverview = TopOverviewController(store: store, preferences: preferences, folders: quickFolders)
        topOverview?.onOpenWorkspace = { [weak self] in self?.showAllWindows() }
        toolbar = NSToolbar(identifier: "WindowNest.Navigation")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = navigationID
        window.toolbar = toolbar
        if toolbar.items.isEmpty {
            for id in toolbarIdentifiers { toolbar.insertItem(withItemIdentifier: id, at: toolbar.items.count) }
        }
        didSelectPage(store.mode)
        store.onPreviewPreferenceChange = { [weak self] value in self?.preferences.update { $0.previewsEnabled = value } }
        preferences.$settings.receive(on: RunLoop.main).sink { [weak self] value in self?.applyAppearance(value) }.store(in: &subscriptions)
        applyAppearance(preferences.settings)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.workspaceSuspended = true; self?.updateWorkspaceVisibility() }
                .store(in: &subscriptions)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.workspaceSuspended = false; self?.updateWorkspaceVisibility() }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }; self.applyAppearance(self.preferences.settings)
            }.store(in: &subscriptions)
        store.$query.receive(on: RunLoop.main).sink { [weak self] text in
            self?.toolbarActions?.searchField.stringValue = text
        }.store(in: &subscriptions)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }
        if launchedAtLogin { updateWorkspaceVisibility() } else { show() }
    }

    private func makeMenus() {
        let main = NSMenu()
        let application = NSMenuItem()
        main.addItem(application)
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle:"开源软件声明…",action:#selector(showOpenSourceNotices),keyEquivalent:"").target=self
        menu.addItem(withTitle:"检查更新…",action:#selector(checkForUpdates),keyEquivalent:"").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle: "显示窗匣", action: #selector(show), keyEquivalent: "0").target = self
        menu.addItem(withTitle: "刷新窗口", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "搜索…", action: #selector(search), keyEquivalent: "f").target = self
        menu.addItem(withTitle: "窗口收纳", action: #selector(showAllWindows), keyEquivalent: "1").target = self
        menu.addItem(withTitle: "应用收纳", action: #selector(showApplications), keyEquivalent: "2").target = self
        menu.addItem(withTitle: "桌面文件夹", action: #selector(showFiles), keyEquivalent: "3").target = self
        menu.addItem(withTitle: "全局文件查找…", action: #selector(showGlobalFileSearch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "桌面文件盒", action: #selector(showDesktopBoxes), keyEquivalent: "").target = self
        menu.addItem(withTitle: "新建桌面文件盒…", action: #selector(newDesktopBox), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "隐藏窗匣", action: #selector(hide), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "退出窗匣", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = menu
        let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        file.submenu = NSMenu(title: "文件")
        file.submenu?.addItem(withTitle: "打开文件 / 添加应用…", action: #selector(openOrAddApplications), keyEquivalent: "o").target = self
        let newCategory = file.submenu!.addItem(withTitle: "新建分类…", action: #selector(addCategory), keyEquivalent: "n")
        newCategory.keyEquivalentModifierMask = [.command, .shift]
        newCategory.target = self
        main.addItem(file)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "编辑")
        edit.submenu?.addItem(withTitle: "撤销收纳更改", action: #selector(undoLibrary), keyEquivalent: "z").target = self
        let redo = edit.submenu!.addItem(withTitle: "重做收纳更改", action: #selector(redoLibrary), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        edit.submenu?.addItem(.separator())
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        main.addItem(edit)
        NSApp.mainMenu = main

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "tray.2", accessibilityDescription: "窗匣")
        status?.button?.toolTip = "窗匣 · 窗口、应用与文件"
        status?.button?.target = self
        status?.button?.action = #selector(show)
    }


    @objc private func showOpenSourceNotices() { OpenSourceNotices.show() }
    @objc private func checkForUpdates() { updates.check() }
    private var toolbarIdentifiers: [NSToolbarItem.Identifier] { [navigationID, .flexibleSpace, actionsID] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarIdentifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let content: NSView
        let size: NSSize
        if id == navigationID {
            let buttons = PageSwitcher(selected: store.mode)
            buttons.onSelect = { [weak self] mode in self?.navigate(to: mode) }
            pageButtons = buttons
            content = buttons; size = PageSwitcher.size
            item.label = "切换页面"
        } else if id == actionsID {
            let actions = WorkspaceToolbarActions(target: self, search: #selector(filterWindows(_:)),
                refresh: #selector(refresh), add: #selector(addApplications), category: #selector(addCategory), settings: #selector(showSettings))
            actions.searchField.stringValue = store.query
            actions.show(store.mode)
            toolbarActions = actions
            content = actions; size = WorkspaceToolbarActions.size
            item.label = "页面操作"
        } else { return nil }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: size.width),
            content.heightAnchor.constraint(equalToConstant: size.height)
        ])
        item.view = content
        item.isBordered = false
        return item
    }
    private func didSelectPage(_ mode: WorkspaceMode) {
        let changed = store.mode != mode
        if changed { store.mode = mode }
        let subtitle = mode.subtitle
        if window.subtitle != subtitle { window.subtitle = subtitle }
        if pageButtons?.selectedMode != mode { pageButtons?.updateSelection(mode) }
        toolbarActions?.show(mode)
        updateWorkspaceVisibility()
    }
    private func navigate(to mode: WorkspaceMode, completion: (() -> Void)? = nil) {
        if mode == .windows { store.refresh() }
        pager.navigate(to: mode, animated: window.isVisible, completion: completion)
    }
    @objc private func filterWindows(_ sender: CapsuleSearchField) { store.query = sender.stringValue }
    @objc private func search() {
        if store.mode == .windows { toolbarActions?.searchField.focus() }
        else if store.mode == .applications { NotificationCenter.default.post(name: Notification.Name("WindowNest.FocusSearch"), object: nil) }
        else { NotificationCenter.default.post(name: Notification.Name("WindowNest.FocusFileSearch"), object: nil) }
    }
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window.attachedSheet == nil, NSApp.modalWindow == nil,
              window.contentLayoutRect.contains(event.locationInWindow) else { return event }
        if !swipe.isTracking && PageGestureExclusion.contains(event.locationInWindow, in: window) { return event }
        var hit = swipe.isTracking ? nil : window.contentView?.hitTest(event.locationInWindow)
        while let current = hit {
            if let text = current as? NSTextView, text.isEditable { return event }
            if let field = current as? NSTextField, field.isEditable { return event }
            hit = current.superview
        }
        let phase: PageGesturePhase
        if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.changed) { phase = .changed }
        else { phase = .unphased }
        let result = swipe.handle(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, phase: phase,
            precise: event.hasPreciseScrollingDeltas, momentum: !event.momentumPhase.isEmpty,
            timestamp: event.timestamp, mode: pager.selectedMode, width: pager.view.bounds.width,
            startingPosition: Double(pager.position))
        switch result {
        case .pass: return event
        case .swallow: return nil
        case let .track(mode, amount):
            pager.track(to: mode, progress: amount)
            gestureTimeout?.invalidate()
            gestureTimeout = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.cancelInterruptedSwipe() }
            }
            return nil
        case let .finish(_, commit):
            gestureTimeout?.invalidate(); gestureTimeout = nil
            pager.finishGesture(commit: commit, velocity: swipe.releaseVelocity)
            return nil
        }
    }
    private func cancelInterruptedSwipe() {
        guard swipe.isTracking else { return }
        swipe = PageSwipeTracker()
        gestureTimeout?.invalidate(); gestureTimeout = nil
        pager.finishGesture(commit: false)
    }
    private func dismissCurrentLayer() {
        if pager.isBusy { pager.cancelTransition(); return }
        if store.mode == .applications {
            if library.showAddApplications { library.showAddApplications = false }
            else if library.scope != .all { library.scope = .all }
            else if !library.query.isEmpty { library.query = "" }
            else { hide() }
        } else if store.mode == .files {
            if !fileSearchPresented { hide();return }
            if files.previewURL != nil { files.previewURL = nil }
            else if !files.query.isEmpty { files.query = "" }
            else if files.kind != .all { files.kind = .all }
            else { hide() }
        } else if !store.query.isEmpty { store.query = "" }
        else { hide() }
    }
    private func applyAppearance(_ value: AppearanceSettings) {
        switch value.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        window?.backgroundColor = WorkspaceColors.canvas
        settingsController?.window?.backgroundColor = WorkspaceColors.canvas
        pager?.minimalEffects = value.effects == .minimal
        pageButtons?.accent = value.accent == .system ? nil : value.accent.nsColor
        pageButtons?.minimalEffects = value.effects == .minimal
        pageButtons?.liquidFeedbackEnabled = value.effects.usesGlass
        pageButtons?.clearGlassEnabled = value.effects == .clearGlass
        toolbarActions?.accent = value.accent.nsColor
        toolbarActions?.liquidFeedbackEnabled = value.effects.usesGlass
        if store.previewsEnabled != value.previewsEnabled { store.setPreviewsEnabled(value.previewsEnabled) }
        topOverview?.setEnabled(value.topOverviewEnabled)
        shortcuts?.apply()
    }
    @objc private func showSettings() {
        if settingsController == nil {
            let host = NSHostingController(rootView: ThemedWorkspace(preferences: preferences,
                content: WorkspaceSettingsView(preferences: preferences, windows: store, shortcuts: shortcuts, quickFolders: quickFolders, desktopBoxes: desktopBoxes, loginItem:loginItem,updates:updates,
                    onPreviewTopOverview: { [weak self] in self?.topOverview?.preview() },
                    onShowTriggerRegion: { [weak self] in self?.topOverview?.showTriggerRegion() })))
            host.sceneBridgingOptions = []
            let settingsWindow = NSWindow(contentViewController: host)
            settingsWindow.title = "窗匣设置"
            settingsWindow.backgroundColor = WorkspaceColors.canvas
            settingsWindow.styleMask = [.titled, .closable]
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.acceptsMouseMovedEvents = true
            settingsWindow.center()
            settingsController = NSWindowController(window: settingsWindow)
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    @objc private func newDesktopBox() { desktopBoxes.create() }
    @objc private func showDesktopBoxes() {
        if desktopBoxes.models.isEmpty { desktopBoxes.create() }
        else { desktopBoxes.models.forEach { desktopBoxes.show($0) } }
    }
    @objc private func openOrAddApplications() {
        if store.mode == .files {
            if fileSearchPresented { files.open() }
            else if let model=desktopBoxes.workspaceModel { desktopBoxes.choose(model,parent:window) }
            else { desktopBoxes.create() }
        } else { addApplications() }
    }
    @objc private func addApplications() { navigate(to: .applications) { [weak self] in self?.library.beginAdding() } }
    @objc private func addCategory() { navigate(to: .applications) { [weak self] in self?.library.categoryDialog() } }
    @objc private func undoLibrary() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { text.undoManager?.undo() }
        else { library.undoManager.undo() }
    }
    @objc private func redoLibrary() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { text.undoManager?.redo() }
        else { library.undoManager.redo() }
    }
    @objc func show() {
        topOverview?.dismiss(immediate: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updateWorkspaceVisibility()
    }
    @objc func hide() {
        shortcutPreviousApplication = nil
        topOverview?.dismiss(immediate: true)
        pager.finishImmediately()
        store.saveCurrentPage()
        window.orderOut(nil)
        store.setVisible(false)
        files.setVisible(false)
        desktopBoxes.setWorkspaceVisible(false)
    }
    @objc func refresh() {
        if store.mode == .windows { store.refresh() }
        else if store.mode == .applications { library.refreshApplications() }
        else if fileSearchPresented { files.refresh() }
        else { desktopBoxes.workspaceModel?.refresh() }
    }
    @objc func showFinder() { store.query = ""; store.selectedApp = "com.apple.finder"; navigate(to: .windows); show() }
    @objc func showAllWindows() { store.query = ""; store.selectedApp = nil; navigate(to: .windows); show() }
    @objc func showFiles() { navigate(to: .files); show() }
    @objc func showGlobalFileSearch() {
        show()
        navigate(to:.files) { NotificationCenter.default.post(name:Notification.Name("WindowNest.FocusFileSearch"),object:nil) }
    }
    @objc func showApplications() { navigate(to: .applications); show() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard store != nil, preferences != nil else { return }
        loginItem?.refresh()
        updates?.checkIfDue()
        store.setPreviewsEnabled(preferences.settings.previewsEnabled)
        shortcuts?.apply()
    }
    func windowDidMiniaturize(_ notification: Notification) { pager.finishImmediately(); store.setVisible(false); files.setVisible(false);desktopBoxes.setWorkspaceVisible(false) }
    private func updateWorkspaceVisibility() {
        guard let window, let store, let files else { return }
        let active = WorkspaceActivityPolicy.allowsWork(visible: window.isVisible, miniaturized: window.isMiniaturized,
            occluded: !window.occlusionState.contains(.visible), suspended: workspaceSuspended)
        store.setVisible(active)
        desktopBoxes.setWorkspaceVisible(active && store.mode == .files)
        files.setVisible(active && store.mode == .files && fileSearchPresented)
    }
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let target = notification.object as? NSWindow, target === window else { return }
        updateWorkspaceVisibility()
    }
    func windowDidDeminiaturize(_ notification: Notification) { updateWorkspaceVisibility() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        let busy=desktopBoxes.models.filter(\.fileOperationActive)
        guard busy.isEmpty else {
            busy.forEach { $0.notice="文件操作正在进行，请完成后再退出。" };return .terminateCancel
        }
        return .terminateNow
    }
    func applicationDidResignActive(_ notification: Notification) { cancelInterruptedSwipe() }
    func applicationWillTerminate(_ notification: Notification) {
        desktopBoxes.shutdown()
        preferences.flush()
        topOverview?.stop()
        shortcuts?.stop()
        pager.finishImmediately()
        files.stop()
        store.saveCurrentPage()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "应用收纳", action: #selector(showApplications), keyEquivalent: "").target = self
        menu.addItem(withTitle: "桌面文件夹", action: #selector(showFiles), keyEquivalent: "").target = self
        menu.addItem(withTitle: "全局文件查找", action: #selector(showGlobalFileSearch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "查看全部窗口", action: #selector(showAllWindows), keyEquivalent: "").target = self
        menu.addItem(withTitle: "查看访达文件夹", action: #selector(showFinder), keyEquivalent: "").target = self
        return menu
    }
}

umask(0o077)
if CommandLine.arguments.contains("--check-updates") {
    Task {
        do { let update=try await UpdateFeed.latest();print("Latest verified release: \(update.manifest.version), \(update.manifest.artifact)");exit(0) }
        catch { fputs(error.localizedDescription+"\n",stderr);exit(2) }
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--enable-login-item") || CommandLine.arguments.contains("--login-item-status") {
    MainActor.assumeIsolated {
        let controller=LoginItemController()
        if CommandLine.arguments.contains("--enable-login-item") { controller.setEnabled(true) }
        if let error=controller.error { fputs(error+"\n",stderr);exit(2) }
        print("Login item status: \(controller.status.rawValue)")
        if controller.status != .enabled && controller.status != .requiresApproval { exit(3) }
    }
} else if CommandLine.arguments.contains("--diagnose") {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let trusted = AXIsProcessTrusted()
    print("Accessibility: \(trusted ? "granted" : "not granted")")
    print("Screen capture: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")")
    if trusted {
        let service = WindowService()
        service.scan { records, unavailable in
            print("Readable windows: \(records.count)")
            print("Finder windows: \(records.filter { $0.bundleID == "com.apple.finder" }.count)")
            print("Unresponsive applications: \(unavailable.count)")
            app.stop(nil)
        }
        app.run()
    }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
