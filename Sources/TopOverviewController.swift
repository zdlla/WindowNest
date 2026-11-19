import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class TopOverviewPresentation: ObservableObject {
    @Published var visible = false
    @Published var selectedApp: String?
    @Published var notice: String?
    @Published var layout: TopOverviewLayout
    init(layout: TopOverviewLayout) { self.layout = layout }
}

@MainActor
final class TopOverviewController {
    let presentation: TopOverviewPresentation
    private let store: WindowStore
    private let preferences: AppearanceStore
    private let panel: TopOverviewPanel
    private let folders: QuickFolderStore
    private var timer: Timer?
    private var clockInterval: TimeInterval?
    private var pointerMonitors: [Any] = []
    private var dismissalMonitors: [Any] = []
    private var hideTask: Task<Void, Never>?
    private var hover = TopOverviewHover()
    private var activeScreen: String?
    private var closing = false
    private var resumeDuringClose = false
    private var enabled = false
    private var sleeping = false
    private var trackingMenus = Set<ObjectIdentifier>()
    private var phaseGeneration: UInt64 = 0
    private let triggerHighlight = TopTriggerHighlight()
    private var previousSettings: AppearanceSettings
    private var screenCache: [(screen: NSScreen, id: String, layout: TopOverviewLayout)] = []
    private var interactionGraceUntil: TimeInterval = 0
    private var previewPointerOrigin: CGPoint?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var focusGeneration: UInt64 = 0
    private var motionBudget = OverviewMotionBudget()
    var onOpenWorkspace: (() -> Void)?

    init(store: WindowStore, preferences: AppearanceStore, folders: QuickFolderStore) {
        self.store = store
        self.preferences = preferences
        self.folders = folders
        previousSettings = preferences.settings
        let screen = NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let inset = max(screen?.safeAreaInsets.top ?? 0, frame.maxY - (screen?.visibleFrame.maxY ?? frame.maxY))
        presentation = TopOverviewPresentation(layout: TopOverviewLayout(screen: frame, topInset: inset,
            notchInset: screen?.safeAreaInsets.top ?? 0, position: preferences.settings.topOverviewPosition,
            widthPercent: preferences.settings.topOverviewWidthPercent, triggerDepth: preferences.settings.topOverviewDepth,
            heightPercent: preferences.settings.topOverviewHeightPercent))
        panel = TopOverviewPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "顶部窗口速览"
        panel.identifier = NSUserInterfaceItemIdentifier("WindowNest.TopOverview")
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let content = TopOverviewView(store: store, presentation: presentation, folders: folders,
            onDismiss: { [weak self] in self?.dismiss() },
            onOpenWorkspace: { [weak self] in self?.dismiss(immediate: true); self?.onOpenWorkspace?() },
            onAddFolder: { [weak self] in self?.addFolders() },
            onOpenFolder: { [weak self] folder in self?.openFolder(folder) },
            onPerform: { [weak self] action, record in self?.perform(action, on: record) },
            onFocus: { [weak self] record in self?.focus(record) },
            onAuthorize: { [weak self] capture in
                guard let self else { return }
                self.dismiss(immediate: true)
                if capture { self.store.requestPreviewPermission() } else { self.store.authorize() }
            })
        let host = NSHostingController(rootView: ThemedWorkspace(preferences: preferences, content: content))
        host.sceneBridgingOptions = []
        panel.contentViewController = host
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in
            self?.refreshScreens(); self?.dismiss(immediate: true)
        }
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.dismiss(immediate: true)
        }
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.sleeping = true; self?.dismiss(immediate: true)
        }
        observe(NSWorkspace.sessionDidResignActiveNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.sleeping = true; self?.dismiss(immediate: true)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(name, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.sleeping = false; self?.hover.dismiss(); self?.tick() }
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let menu = note.object as? NSMenu else { return }
                MainActor.assumeIsolated {
                    if name == NSMenu.didBeginTrackingNotification { self?.trackingMenus.insert(ObjectIdentifier(menu)) }
                    else { self?.trackingMenus.remove(ObjectIdentifier(menu)); self?.tick() }
                }
            }
            observers.append((.default, token))
        }
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    func setEnabled(_ value: Bool) {
        let settings = preferences.settings
        let sizeChanged = previousSettings.topOverviewHeightPercent != settings.topOverviewHeightPercent
        let regionChanged = previousSettings.topOverviewPosition != settings.topOverviewPosition ||
            previousSettings.topOverviewWidthPercent != settings.topOverviewWidthPercent ||
            previousSettings.topOverviewDepth != settings.topOverviewDepth || previousSettings.topOverviewDelay != settings.topOverviewDelay
        previousSettings = settings
        if screenCache.isEmpty || regionChanged || sizeChanged { refreshScreens() }
        if sizeChanged, panel.isVisible, !closing,
           let screen = screenCache.first(where: { $0.id == activeScreen })?.screen {
            // Keep the top edge anchored and preserve hover/filter state.
            presentation.layout = layout(for: screen)
            store.setOverviewVisible(true, previews: !presentation.layout.iconsOnly)
            panel.setFrame(presentation.layout.panel, display: true)
        }
        if value && regionChanged { showTriggerRegion() }
        if hover.dwellDuration != preferences.settings.topOverviewDelay {
            let screen = hover.screenID
            hover = TopOverviewHover(dwell: preferences.settings.topOverviewDelay)
            if let screen { hover.reveal(on: screen) }
        }
        guard enabled != value else { return }
        enabled = value
        timer?.invalidate(); timer = nil; clockInterval = nil
        pointerMonitors.forEach(NSEvent.removeMonitor); pointerMonitors.removeAll()
        if value {
            hover.reset()
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerEvent(event) }
            }) { pointerMonitors.append(monitor) }
            if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerEvent(event) }
                return event
            }) { pointerMonitors.append(monitor) }
            tick()
        } else { triggerHighlight.hide(); dismiss(immediate: true) }
    }

    func showTriggerRegion() {
        let settings = preferences.settings
        let label = "触发区域 · \(settings.topOverviewPosition.title) · \(Int(settings.topOverviewWidthPercent))% · \(Int(settings.topOverviewDepth)) 点 · \(String(format: "%.2f", settings.topOverviewDelay)) 秒"
        let regions = NSScreen.screens.flatMap { screen -> [CGRect] in
            let value = layout(for: screen)
            return [value.trigger]
        }
        triggerHighlight.show(regions: regions, accent: settings.accent.nsColor, label: label)
    }

    func preview() {
        guard enabled, !sleeping else { return }
        interactionGraceUntil = ProcessInfo.processInfo.systemUptime + 20
        let point = NSEvent.mouseLocation
        previewPointerOrigin = point
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            show(on: screen)
            reconcileClock()
        }
    }

    private func screenID(_ screen: NSScreen) -> String {
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] { return String(describing: id) }
        return NSStringFromRect(screen.frame)
    }

    private func layout(for screen: NSScreen) -> TopOverviewLayout {
        let menuInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return TopOverviewLayout(screen: screen.frame, topInset: max(screen.safeAreaInsets.top, menuInset),
            notchInset: screen.safeAreaInsets.top, position: preferences.settings.topOverviewPosition,
            widthPercent: preferences.settings.topOverviewWidthPercent, triggerDepth: preferences.settings.topOverviewDepth,
            heightPercent: preferences.settings.topOverviewHeightPercent)
    }

    private func refreshScreens() {
        screenCache = NSScreen.screens.map { ($0, screenID($0), layout(for: $0)) }
    }

    private func pointerEvent(_ event: NSEvent) {
        guard motionBudget.accept(time: event.timestamp, motion: event.type == .mouseMoved) else { return }
        tick()
    }

    private func tick() {
        guard enabled, !sleeping else { return }
        defer { reconcileClock() }
        if hover.screenID != nil && !panel.isVisible && !closing {
            hover.reset(); activeScreen = nil; presentation.visible = false
            stopObservingDismissalKey()
            trackingMenus.removeAll()
            store.setOverviewVisible(false)
        }
        let mouse = NSEvent.mouseLocation
        if let origin = previewPointerOrigin, hypot(mouse.x - origin.x, mouse.y - origin.y) > 6 {
            previewPointerOrigin = nil
            interactionGraceUntil = 0
        }
        let trigger = screenCache.first { $0.layout.containsTrigger(mouse) }?.id
        let inside = panel.isVisible && panel.frame.insetBy(dx: -6, dy: -10).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons != 0
        if closing, resumeDuringClose, inside, !dragging,
           let screen = screenCache.first(where: { $0.id == activeScreen })?.screen {
            show(on: screen, resetSelection: false)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let event = hover.update(trigger: trigger, insidePanel: inside, dragging: dragging,
            interacting: panel.isVisible && (!trackingMenus.isEmpty || now < interactionGraceUntil), time: now)
        switch event {
        case .none: break
        case .hide: dismiss(automatic: true)
        case .show(let id):
            if let screen = screenCache.first(where: { $0.id == id })?.screen { show(on: screen) }
        }
    }

    private func reconcileClock() {
        let interval: TimeInterval?
        if !enabled || sleeping { interval = nil }
        else if hover.needsClock { interval = 0.04 }
        else if panel.isVisible && ProcessInfo.processInfo.systemUptime < interactionGraceUntil { interval = 0.5 }
        else { interval = 0.20 }
        // A lightweight fallback covers coalesced/missing events at menu-bar
        // and screen boundaries. It reads cached geometry, never scans windows
        // or captures previews while hidden; disabled/sleeping still stop it.
        guard interval != clockInterval else { return }
        timer?.invalidate(); timer = nil; clockInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = min(0.02, interval / 8)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func show(on screen: NSScreen, resetSelection: Bool = true) {
        phaseGeneration &+= 1
        let token = phaseGeneration
        hideTask?.cancel(); hideTask = nil
        closing = false; resumeDuringClose = false
        activeScreen = screenID(screen)
        hover.reveal(on: activeScreen!)
        let nextLayout = layout(for: screen)
        if presentation.layout != nextLayout { presentation.layout = nextLayout }
        if resetSelection {
            if presentation.selectedApp != nil { presentation.selectedApp = nil }
            if presentation.notice != nil { presentation.notice = nil }
        }
        if panel.frame != nextLayout.panel { panel.setFrame(nextLayout.panel, display: true) }
        panel.ignoresMouseEvents = false
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        observeDismissalKey()
        store.setOverviewVisible(true, previews: !presentation.layout.iconsOnly)
        // Mount at the final bounds first. Only local opacity/scale animates.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.phaseGeneration == token, !self.closing, self.enabled, self.panel.isVisible else { return }
            if !self.presentation.visible { self.presentation.visible = true }
            self.fade(to: 1, duration: self.simpleMotion ? 0.12 : 0.22)
        }
    }

    func dismiss(immediate: Bool = false, automatic: Bool = false) {
        phaseGeneration &+= 1
        let token = phaseGeneration
        interactionGraceUntil = 0
        previewPointerOrigin = nil
        hover.dismiss(suppressReentry: !automatic)
        hideTask?.cancel(); hideTask = nil
        if presentation.visible { presentation.visible = false }
        panel.ignoresMouseEvents = true
        stopObservingDismissalKey()
        guard panel.isVisible else { store.setOverviewVisible(false); reconcileClock(); return }
        closing = true; resumeDuringClose = automatic
        if immediate { finishDismissal(); return }
        let simple = simpleMotion
        fade(to: 0, duration: simple ? 0.10 : 0.18)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(simple ? 140 : 300))
            guard !Task.isCancelled, let self, self.phaseGeneration == token, self.closing else { return }
            self.finishDismissal()
        }
    }

    private func finishDismissal() {
        panel.orderOut(nil)
        fade(to: 1, duration: 0)
        stopObservingDismissalKey()
        closing = false; resumeDuringClose = false; activeScreen = nil
        trackingMenus.removeAll()
        store.setOverviewVisible(false)
        reconcileClock()
    }

    private func addFolders() {
        dismiss(immediate: true)
        folders.chooseFolders { [weak self] in
            guard let self, self.enabled else { return }
            self.preview()
            self.presentation.notice = self.folders.error
        }
    }

    private func openFolder(_ folder: QuickFolder) {
        focusGeneration &+= 1
        let token = focusGeneration
        let screen = screenCache.first(where: { $0.id == activeScreen })?.screen
        dismiss(immediate: true)
        folders.open(folder) { [weak self] error in
            guard let self, self.focusGeneration == token, let error else { return }
            if let screen, self.enabled { self.show(on: screen, resetSelection: false) }
            self.presentation.notice = error
        }
    }

    private var simpleMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || preferences.settings.effects == .minimal
    }
    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    private func observeDismissalKey() {
        guard dismissalMonitors.isEmpty else { return }
        // Observe Escape only while visible. Never redirect/replay input or
        // change the first responder; typing belongs to the underlying app.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.dismiss() }
        }) { dismissalMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }
            return event
        }) { dismissalMonitors.append(monitor) }
    }

    private func stopObservingDismissalKey() {
        dismissalMonitors.forEach(NSEvent.removeMonitor)
        dismissalMonitors.removeAll()
    }

    private func perform(_ action: WindowControlAction, on record: WindowRecord) {
        presentation.notice = nil
        store.perform(action, on: record) { [weak self] error in
            guard let self else { return }
            if let error { self.presentation.notice = error }
            else if action == .zoom || action == .fullscreen { self.dismiss() }
        }
    }

    private func focus(_ record: WindowRecord) {
        focusGeneration &+= 1
        let token = focusGeneration
        let screen = screenCache.first(where: { $0.id == activeScreen })?.screen
        // Remove this status-level, nonactivating panel before handing focus
        // to another application, including a window in another Space.
        dismiss(immediate: true)
        store.focus(record) { [weak self] error in
            guard let self, self.focusGeneration == token, let error,
                  !WindowFocusInterruption.contains(error) else { return }
            if let screen, self.enabled { self.show(on: screen, resetSelection: false) }
            self.presentation.notice = error
        }
    }

    func stop() {
        triggerHighlight.hide()
        setEnabled(false)
        stopObservingDismissalKey()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }
}
