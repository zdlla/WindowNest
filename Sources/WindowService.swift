import AppKit
import ApplicationServices


private struct CGEntry {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
    let onScreen: Bool
}

struct WindowBatchCloseReport {
    var requested = 0
    var failures: [String] = []
    var awaitingConfirmation = false

    var message: String {
        if awaitingConfirmation { return "原应用有窗口需要确认，请处理保存提示后再点“关闭全部窗口”。" }
        if let first = failures.first { return "\(failures.count) 个窗口未能关闭。\(first)" }
        return "已向原应用发送 \(requested) 个关闭请求，窗口列表会随实际状态更新。"
    }
}

/// All AX IPC is serialized off the main thread, with a timeout per application.
final class WindowService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.windownest.accessibility", qos: .userInitiated)
    private var identities: [(pid_t, AXUIElement, UUID)] = []
    private var lastRows: [WindowRecord] = []
    private let controlAccess = AXWindowControlAccess()
    private let focusTicket = WindowFocusTicket()
    private let nativeFocus = NativeWindowFocus()
    private var observedWindows: [pid_t: [AXUIElement]] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private let crossSpace = CrossSpaceWindowAccess()
    private var discoveryRotation = 0
    private var destroyedWindowIDs: [CGWindowID: pid_t] = [:]
    private let presence = WindowPresenceAccess()
    private var discoveryBudget = WindowDiscoveryBudget()
    private let icons = WindowIconCache()
    var onWindowsChanged: (() -> Void)?
    private var changeGeneration: UInt64 = 0

    func scan(completion: @escaping ([WindowRecord], [String]) -> Void) {
        let screens = Self.visibleScreenFrames()
        // NSWorkspace / NSImage are read on the main thread.
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
        }.map { app in
            let bundle = app.bundleIdentifier ?? ""
            return (app.processIdentifier, app.localizedName ?? "应用", bundle,
                icons.cached(pid: app.processIdentifier, bundleID: bundle) ?? app.icon ?? NSImage(), app.isHidden)
        }
        queue.async { [self] in
            controlAccess.visibleScreens = screens
            let cgEntries = Self.cgEntries()
            presence.beginSnapshot()
            let livePids = Set(apps.map { $0.0 })
            icons.prune(pids: livePids)
            destroyedWindowIDs = destroyedWindowIDs.filter { livePids.contains($0.value) }
            reconcileObservers(pids: Set(apps.map { $0.0 }))
            crossSpace.prune(pids: Set(apps.map { $0.0 }))
            discoveryBudget.prune(pids: livePids)
            // One shared discovery budget for the whole inventory, never per
            // window. Hidden mode does not schedule inventory polling.
            var discoveryRemaining: TimeInterval = 0.04
            var fresh: [(pid_t, AXUIElement, UUID)] = []
            var rows: [WindowRecord] = []
            var unavailable: [String] = []
            let start = apps.isEmpty ? 0 : discoveryRotation % apps.count
            discoveryRotation = apps.isEmpty ? 0 : (start + 1) % apps.count
            let orderedApps = Array(apps.dropFirst(start)) + Array(apps.prefix(start))
            for (pid, name, bundleID, sourceIcon, hidden) in orderedApps {
                let icon = icons.image(pid: pid, bundleID: bundleID, source: sourceIcon)
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.25)
                var raw: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
                if result != .success && result != .noValue && result != .attributeUnsupported { unavailable.append(name) }
                let listedWindows = raw as? [AXUIElement] ?? []
                let remembered = identities.filter { $0.0 == pid }.map { $0.1 } + (observedWindows[pid] ?? [])
                let published = PublishedWindowMerge.unique([
                    listedWindows,
                    Self.windowAttribute(app, kAXFocusedWindowAttribute),
                    Self.windowAttribute(app, kAXMainWindowAttribute)
                ], equal: { CFEqual($0, $1) })
                var windows = PublishedWindowMerge.unique([published, remembered], equal: { CFEqual($0, $1) })
                let metadata = cgEntries.filter { entry in
                    guard entry.pid == pid, destroyedWindowIDs[entry.id] != pid,
                          !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          entry.bounds.width >= 80, entry.bounds.height >= 50 else { return false }
                    return WindowAvailabilityPolicy.includes(WindowAvailabilityEvidence(
                        server: presence.state(id: entry.id, exists: true, onScreen: entry.onScreen), hidden: hidden))
                }
                let knownIDs = Set(windows.compactMap { crossSpace.identifier(of: $0) })
                let publishedGeometry = windows.filter { crossSpace.identifier(of: $0) == nil }.compactMap { element -> (CGRect, String)? in
                    AXUIElementSetMessagingTimeout(element, 0.2)
                    guard let bounds = Self.bounds(element) else { return nil }
                    return (bounds, Self.string(element, kAXTitleAttribute))
                }
                // Existing published windows come first. Only fill concrete
                // gaps; don't sweep already known applications on every scan.
                let missing = Set(metadata.filter { entry in
                    !knownIDs.contains(entry.id) && !publishedGeometry.contains { bounds, title in
                        WindowGeometry.same(bounds, entry.bounds) && title == entry.title
                    }
                }.map(\.id))
                let now = ProcessInfo.processInfo.systemUptime
                let eligible = discoveryBudget.eligible(pid: pid, candidates: missing, now: now)
                let budget = min(0.012, discoveryRemaining)
                var resolvedByID: [CGWindowID: AXUIElement] = [:]
                if budget > 0 && !eligible.isEmpty {
                    resolvedByID = crossSpace.resolve(pid: pid, requested: eligible, seconds: budget, maxAttempts: 256)
                    discoveryRemaining -= ProcessInfo.processInfo.systemUptime - now
                    discoveryBudget.attempted(pid: pid, requested: eligible, resolved: Set(resolvedByID.keys), now: now)
                    windows = PublishedWindowMerge.unique([windows, Array(resolvedByID.values)], equal: { CFEqual($0, $1) })
                }
                var covered = Set<CGWindowID>()
                var axBounds: [(CGRect, String)] = []
                for element in windows {
                    AXUIElementSetMessagingTimeout(element, 0.20)
                    if Self.isDestroyed(element) {
                        retire(element)
                        continue
                    }
                    let role = Self.string(element, kAXRoleAttribute)
                    let subrole = Self.string(element, kAXSubroleAttribute)
                    // Finder's desktop and transient utility panels are not task windows.
                    guard role == kAXWindowRole as String,
                          subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { continue }
                    let title = Self.string(element, kAXTitleAttribute)
                    let document = Self.string(element, kAXDocumentAttribute)
                    let bounds = Self.bounds(element)
                    let minimized = Self.bool(element, kAXMinimizedAttribute)
                    let fullScreen = Self.bool(element, "AXFullScreen")
                    if let bounds, (bounds.width < 80 || bounds.height < 50) { continue }
                    let candidates = cgEntries.filter { entry in
                        entry.pid == pid && bounds.map { WindowGeometry.same($0, entry.bounds) } == true
                    }
                    // Never guess a preview when more than one window has the same geometry.
                    let titled = candidates.filter { !$0.title.isEmpty && $0.title == title }
                    let directID = resolvedByID.first { CFEqual($0.value, element) }?.key ?? crossSpace.identifier(of: element)
                    let direct = directID.flatMap { id in cgEntries.first { $0.pid == pid && $0.id == id } }
                    let match = direct ?? (titled.count == 1 ? titled.first : (candidates.count == 1 ? candidates.first : nil))
                    if let match { covered.insert(match.id) }
                    let serverID = match?.id ?? directID
                    let server = presence.state(id: serverID, exists: match != nil, onScreen: match?.onScreen ?? false)
                    if server.onScreen, let serverID { destroyedWindowIDs[serverID] = nil }
                    let evidence = WindowAvailabilityEvidence(server: server, axAlive: true,
                        axListed: listedWindows.contains(where: { CFEqual($0, element) }), minimized: minimized,
                        hidden: hidden, fullScreen: fullScreen,
                        retired: serverID.map { destroyedWindowIDs[$0] == pid } ?? false)
                    guard WindowAvailabilityPolicy.includes(evidence) else { continue }
                    if let bounds { axBounds.append((bounds, title)) }
                    let id = identities.first { $0.0 == pid && CFEqual($0.1, element) }?.2 ??
                        lastRows.first { $0.pid == pid && $0.cgID != nil && $0.cgID == match?.id }?.id ?? UUID()
                    fresh.append((pid, element, id))
                    rows.append(WindowRecord(id: id, pid: pid, appName: name, bundleID: bundleID,
                        icon: icon, title: title, document: document.isEmpty ? nil : document,
                        label: WindowNaming.label(app: name, title: title, document: document,
                            isFinder: bundleID == "com.apple.finder"),
                        minimized: minimized, fullScreen: fullScreen, hidden: hidden,
                        element: element, cgID: serverID,
                        controls: WindowControlDriver(access: controlAccess).capabilities(of: element)))
                }
                // WindowServer's all-window metadata fills gaps before an AX
                // handle has been observed in another Space. Such entries have
                // no invented AX element and destructive controls stay disabled.
                // Untitled WindowServer surfaces often belong to internal web
                // views and transitions. Real untitled AX task windows above
                // remain supported; metadata alone is not enough to add one.
                for entry in cgEntries where entry.pid == pid && !covered.contains(entry.id) &&
                    destroyedWindowIDs[entry.id] != pid &&
                    !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    entry.bounds.width >= 80 && entry.bounds.height >= 50 {
                    let server = presence.state(id: entry.id, exists: true, onScreen: entry.onScreen)
                    guard nativeFocus.available, WindowAvailabilityPolicy.includes(WindowAvailabilityEvidence(server: server, hidden: hidden)) else { continue }
                    if axBounds.contains(where: { WindowGeometry.same($0.0, entry.bounds) && ($0.1 == entry.title || entry.title.isEmpty) }) { continue }
                    let id = lastRows.first { $0.pid == pid && $0.cgID == entry.id }?.id ?? UUID()
                    rows.append(WindowRecord(id: id, pid: pid, appName: name, bundleID: bundleID, icon: icon,
                        title: entry.title, document: nil,
                        label: WindowNaming.label(app: name, title: entry.title, document: nil, isFinder: bundleID == "com.apple.finder"),
                        minimized: false, fullScreen: false, hidden: hidden, element: nil, cgID: entry.id,
                        controls: WindowControlCapabilities()))
                }
                let liveElements = fresh.filter { $0.0 == pid }.map { $0.1 }
                for element in liveElements { remember(element, pid: pid) }
                observedWindows[pid] = liveElements
            }
            identities = fresh
            controlAccess.prune(keeping: fresh.map { $0.1 })
            rows.sort {
                if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
                if $0.label != $1.label { return $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
            let resultRows = rows
            lastRows = rows
            let failed = unavailable
            DispatchQueue.main.async { completion(resultRows, failed) }
        }
    }

    func focus(_ window: WindowRecord, completion: @escaping (String?) -> Void) {
        guard let running = NSRunningApplication(processIdentifier: window.pid), !running.isTerminated else {
            completion("这个应用已退出，请刷新窗口列表。"); return
        }
        let token = focusTicket.issue()
        let diagnostics = Self.needsWPSHandoff(window) ? WindowFocusDiagnostics(pid: window.pid, windowID: window.cgID,
            minimized: window.minimized, fullScreen: window.fullScreen) : nil
        let complete: (String?) -> Void = { error in diagnostics?.finish(error: error); completion(error) }
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let appHidden = running.isHidden
        // A click on a nonactivating panel is still explicit user intent. Take
        // activation, then yield it using the public macOS 14+ handoff API.
        let exactOnly=WindowFocusRouting.targetsOnlyOneWindow(bundleID:window.bundleID)
        if !exactOnly { NSApp.activate() }
        queue.async { [self] in
            let app = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            let element = resolve(window, app: app)
            guard isAvailable(window, element: element, app: app, hidden: appHidden) else {
                if let old = window.element, Self.isDestroyed(old) { retire(old) }
                DispatchQueue.main.async { complete(WindowFocusUnavailable.message) }
                return
            }
            if let element { prepareExactWindow(element, app: app, usesWPSHandoff: Self.needsWPSHandoff(window)) }
            if exactOnly {
                guard self.focusTicket.isCurrent(token) else { DispatchQueue.main.async { complete(WindowFocusInterruption.superseded) };return }
                // Never unhide/activate the entire Finder, even on failure.
                let activated=element != nil && self.nativeFocus.activateFrontWindowOnly(pid:window.pid) { self.focusTicket.isCurrent(token) }
                let targeted=activated || (window.cgID.map { id in self.nativeFocus.request(pid:window.pid,windowID:id) { self.focusTicket.isCurrent(token) } } ?? false)
                guard targeted else { DispatchQueue.main.async { complete("未能单独切换到这个访达窗口，请重试。") };return }
                let deadline=ProcessInfo.processInfo.systemUptime+1.6
                self.queue.asyncAfter(deadline:.now()+0.1) {
                    self.verifyFocus(window,running:running,app:app,token:token,previousPID:previousPID,deadline:deadline,attempt:0,compatibilityAttempted:false,diagnostics:diagnostics,completion:complete)
                }
                return
            }
            DispatchQueue.main.async {
                guard self.focusTicket.isCurrent(token) else { complete(WindowFocusInterruption.superseded); return }
                running.unhide()
                NSApp.yieldActivation(to: running)
                let activated = running.activate(from: .current, options: [])
                diagnostics?.add(["activationRequested": activated])
                let deadline = ProcessInfo.processInfo.systemUptime + (Self.needsWPSHandoff(window) ? 2.2 : 1.6)
                self.queue.asyncAfter(deadline: .now() + 0.10) {
                    self.verifyFocus(window, running: running, app: app, token: token,
                        previousPID: previousPID, deadline: deadline, attempt: 0, compatibilityAttempted: false,
                        diagnostics: diagnostics, completion: complete)
                }
            }
        }
    }

    private func verifyFocus(_ window: WindowRecord, running: NSRunningApplication, app: AXUIElement,
                             token: UInt64, previousPID: pid_t?, deadline: TimeInterval, attempt: Int,
                             compatibilityAttempted: Bool,
                             diagnostics: WindowFocusDiagnostics?,
                             completion: @escaping (String?) -> Void) {
        guard focusTicket.isCurrent(token) else {
            DispatchQueue.main.async { completion(WindowFocusInterruption.superseded) }; return
        }
        let exactOnly=WindowFocusRouting.targetsOnlyOneWindow(bundleID:window.bundleID)
        if attempt == 0 && !exactOnly { AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) }
        let element = resolve(window, app: app)
        if let element { prepareExactWindow(element, app: app, usesWPSHandoff: Self.needsWPSHandoff(window)) }
        let focused = Self.windowAttribute(app, kAXFocusedWindowAttribute)
        let main = Self.windowAttribute(app, kAXMainWindowAttribute)
        let exact = element.map { target in
            (focused.isEmpty ? main : focused).contains { candidate in
                CFEqual(target, candidate) || (window.cgID != nil && crossSpace.identifier(of: candidate) == window.cgID)
            }
        } ?? false
        let requiresForegroundWindow = (Self.needsWPSHandoff(window) || exactOnly) && window.cgID != nil
        let frontWindows = (compatibilityAttempted || requiresForegroundWindow) ? Self.cgEntries(onScreenOnly: true) : []
        let knownIDs = Set(lastRows.compactMap(\.cgID))
        let frontWindowID = WindowForegroundPolicy.frontmostTask(targetID: window.cgID, surfaces: frontWindows.map {
            WindowForegroundSurface(id: $0.id, bounds: $0.bounds,
                hasTitle: !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, knownTask: knownIDs.contains($0.id))
        })
        let focusedIDs = focused.compactMap { crossSpace.identifier(of: $0) }
        let mainIDs = main.compactMap { crossSpace.identifier(of: $0) }
        let nativeStatus = nativeFocus.status
        let currentFullScreen = element.map { Self.bool($0, "AXFullScreen") } ?? false
        let currentMinimized = element.map { Self.bool($0, kAXMinimizedAttribute) } ?? false
        DispatchQueue.main.async { [self] in
            guard focusTicket.isCurrent(token) else { completion(WindowFocusInterruption.superseded); return }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            diagnostics?.add(["attempt": attempt, "frontPID": front ?? -1, "AXExact": exact,
                "AXResolved": element != nil, "focusedWindowIDs": focusedIDs, "mainWindowIDs": mainIDs,
                "AXFullScreen": currentFullScreen, "AXMinimized": currentMinimized,
                "frontTaskWindowID": frontWindowID ?? 0,
                "foregroundWindows": frontWindows.prefix(4).map { ["pid": $0.pid, "id": $0.id,
                    "hasTitle": !$0.title.isEmpty, "width": $0.bounds.width, "height": $0.bounds.height] as [String: Any] },
                "compatibilityAttempted": compatibilityAttempted, "nativeStatus": nativeStatus])
            if WindowFocusVerification.succeeded(targetPID: window.pid, frontPID: front, exactAccessibility: exact,
                compatibilityAttempted: compatibilityAttempted, targetID: window.cgID, frontWindowID: frontWindowID,
                requiresForegroundWindow: requiresForegroundWindow) {
                completion(nil); return
            }
            if let front, front != getpid(), front != window.pid, front != previousPID {
                _ = focusTicket.issue(); completion(WindowFocusInterruption.userChangedApplication); return
            }
            guard attempt < 8 && ProcessInfo.processInfo.systemUptime < deadline && !running.isTerminated else {
                completion(element == nil ? "未能取得这个文档窗口的操作接口，兼容切换也未完成。请先在原应用中激活该窗口后重试。" :
                    "已找到指定窗口，但原应用尚未完成前台切换，请重试。"); return
            }
            queue.asyncAfter(deadline: .now() + 0.12) {
                var usedCompatibility = compatibilityAttempted
                if !usedCompatibility && (Self.needsWPSHandoff(window) || exactOnly || window.element == nil), let id = window.cgID,
                   self.focusTicket.isCurrent(token), Self.cgEntries().contains(where: { $0.pid == window.pid && $0.id == id }) {
                    usedCompatibility = true
                    self.nativeFocus.request(pid: window.pid, windowID: id) { self.focusTicket.isCurrent(token) }
                }
                self.verifyFocus(window, running: running, app: app, token: token,
                    previousPID: previousPID, deadline: deadline, attempt: attempt + 1,
                    compatibilityAttempted: usedCompatibility, diagnostics: diagnostics, completion: completion)
            }
        }
    }

    private static func needsWPSHandoff(_ window: WindowRecord) -> Bool {
        window.bundleID == "com.kingsoft.wpsoffice.mac"
    }

    private func isAvailable(_ record: WindowRecord, element: AXUIElement?, app: AXUIElement, hidden: Bool) -> Bool {
        if let original = record.element, Self.isDestroyed(original) { return false }
        let serverID = record.cgID ?? element.flatMap { crossSpace.identifier(of: $0) }
        let entry = Self.cgEntries().first { $0.pid == record.pid && $0.id == serverID }
        presence.beginSnapshot()
        let server = presence.state(id: serverID, exists: entry != nil, onScreen: entry?.onScreen ?? false)
        let listed = Self.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let alive = element.map { Self.string($0, kAXRoleAttribute) == kAXWindowRole as String } ?? false
        return WindowAvailabilityPolicy.includes(WindowAvailabilityEvidence(server: server, axAlive: alive,
            axListed: element.map { target in listed.contains { CFEqual($0, target) } } ?? false,
            minimized: element.map { Self.bool($0, kAXMinimizedAttribute) } ?? false, hidden: hidden,
            fullScreen: element.map { Self.bool($0, "AXFullScreen") } ?? false,
            retired: serverID.map { destroyedWindowIDs[$0] == record.pid } ?? false))
    }

    private func prepareExactWindow(_ element: AXUIElement, app: AXUIElement, usesWPSHandoff: Bool) {
        AXUIElementSetMessagingTimeout(element, 0.2)
        if Self.bool(element, kAXMinimizedAttribute) && !Self.bool(element, "AXFullScreen") {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        // WPS/Qt can normalize a fullscreen document when these generic AX
        // focus setters are used. Its exact-window path uses WindowServer's
        // key-window handoff after application activation instead.
        guard !usesWPSHandoff else { return }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func resolve(_ record: WindowRecord, app: AXUIElement) -> AXUIElement? {
        if let element = record.element, Self.string(element, kAXRoleAttribute) == kAXWindowRole as String { return element }
        let candidates = PublishedWindowMerge.unique([
            Self.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [],
            Self.windowAttribute(app, kAXFocusedWindowAttribute), Self.windowAttribute(app, kAXMainWindowAttribute),
            observedWindows[record.pid] ?? []
        ], equal: { CFEqual($0, $1) })
        guard let entry = Self.cgEntries().first(where: { $0.pid == record.pid && $0.id == record.cgID }) else { return nil }
        if let exact = PublishedWindowMerge.onlyMatch(candidates, where: { element in
            Self.string(element, kAXRoleAttribute) == kAXWindowRole as String && crossSpace.identifier(of: element) == entry.id
        }) { return exact }
        let published = PublishedWindowMerge.onlyMatch(candidates) { element in
            guard Self.string(element, kAXRoleAttribute) == kAXWindowRole as String,
                  let bounds = Self.bounds(element), WindowGeometry.same(bounds, entry.bounds) else { return false }
            return entry.title.isEmpty || Self.string(element, kAXTitleAttribute) == entry.title
        }
        if let published { return published }
        if let exact = crossSpace.resolve(pid: record.pid, requested: [entry.id], seconds: 0.12)[entry.id] {
            remember(exact, pid: record.pid)
            return exact
        }
        return nil
    }

    func perform(_ action: WindowControlAction, on window: WindowRecord, completion: @escaping (String?) -> Void) {
        let screens = Self.visibleScreenFrames()
        guard let element = window.element else { completion("请先切换到此窗口，待窗口信息更新后再操作。"); return }
        guard let running = NSRunningApplication(processIdentifier: window.pid), !running.isTerminated else {
            completion("这个应用已退出，请刷新窗口列表。")
            return
        }
        let execute = { [self] in queue.async { [self] in
            if action == .close {
                WindowControlDriver(access: controlAccess).requestClose(on: element,
                    schedule: { delay, work in self.queue.asyncAfter(deadline: .now() + delay, execute: work) }) { result in
                    switch result {
                    case .success:
                        self.observeClose(window, running: running)
                        DispatchQueue.main.async { completion(nil) }
                    case .failure(let error):
                        if Self.hasSheet(element) { self.revealConfirmation(window, running: running) }
                        let message = (error as? WindowControlFailure)?.message ?? error.localizedDescription
                        DispatchQueue.main.async { completion(message) }
                    }
                }
                return
            }
            do {
                controlAccess.visibleScreens = screens
                try WindowControlDriver(access: controlAccess).perform(action, on: element)
                if action == .zoom && controlAccess.hasPendingZoom(element) {
                    finishZoom(window, completion: completion)
                } else { DispatchQueue.main.async { completion(nil) } }

            } catch {
                let message = (error as? WindowControlFailure)?.message ?? error.localizedDescription
                DispatchQueue.main.async { completion(message) }
            }
        } }
        if action == .zoom || action == .fullscreen {
            // Some apps accept AX geometry writes while inactive but silently
            // constrain them using the previous window origin. Make this exact
            // window main before resizing; the card's action remains separate.
            focus(window) { [self] error in
                if let error { completion(error) }
                else { queue.asyncAfter(deadline: .now() + 0.18) { execute() } }
            }
        } else { execute() }
    }

    private func observeClose(_ window: WindowRecord, running: NSRunningApplication?) {
        guard let element = window.element else { return }
        // AXPress accepts the request; it never answers a save confirmation.
        for delay in [0.18, 0.65] {
            queue.asyncAfter(deadline: .now() + delay) {
                if Self.hasSheet(element), let running { self.revealConfirmation(window, running: running) }
                else if Self.isDestroyed(element), let id = window.cgID { self.destroyedWindowIDs[id] = window.pid }
            }
        }
    }

    private func finishZoom(_ window: WindowRecord, completion: @escaping (String?) -> Void) {
        guard let element = window.element else { completion("窗口信息尚未就绪。"); return }
        // AppKit may defer AX geometry writes until its next display frame.
        // Position first, then size after settling, without blocking the AX queue.
        queue.asyncAfter(deadline: .now() + 0.18) { [self] in
            do {
                try controlAccess.finishZoom(element)
                queue.asyncAfter(deadline: .now() + 0.22) { [self] in
                    do {
                        try controlAccess.verifyZoom(element)
                        DispatchQueue.main.async { completion(nil) }
                    } catch {
                        let message = (error as? WindowControlFailure)?.message ?? error.localizedDescription
                        DispatchQueue.main.async { completion(message) }
                    }
                }
            } catch {
                controlAccess.cancelZoom(element)
                let message = (error as? WindowControlFailure)?.message ?? error.localizedDescription
                DispatchQueue.main.async { completion(message) }
            }
        }
    }

    func closeAll(_ windows: [WindowRecord], completion: @escaping (WindowBatchCloseReport) -> Void) {
        // Snapshot only this app's existing AX windows. Newly opened windows
        // cannot accidentally join an operation already in progress.
        queue.async { [self] in
            func finish(_ report: WindowBatchCloseReport) {
                DispatchQueue.main.async { completion(report) }
            }
            func next(_ index: Int, _ report: WindowBatchCloseReport) {
                guard index < windows.count else { finish(report); return }
                let window = windows[index]
                guard let element = window.element else {
                    var skipped = report; skipped.failures.append("有窗口尚未取得操作权限，已保留。"); next(index + 1, skipped); return
                }
                if Self.hasSheet(element) {
                    var checked = report; checked.awaitingConfirmation = true
                    if let running = NSRunningApplication(processIdentifier: window.pid) { revealConfirmation(window, running: running) }
                    finish(checked)
                    return
                }
                WindowControlDriver(access: controlAccess).requestClose(on: element,
                    schedule: { delay, work in self.queue.asyncAfter(deadline: .now() + delay, execute: work) }) { result in
                    var updated = report
                    switch result {
                    case .success:
                        updated.requested += 1
                        self.observeClose(window, running: NSRunningApplication(processIdentifier: window.pid))
                    case .failure(let error):
                        switch error {
                        case WindowControlFailure.stale: break
                        case WindowControlFailure.unavailable, WindowControlFailure.permission:
                            updated.failures.append((error as! WindowControlFailure).message)
                            finish(updated); return
                        default: updated.failures.append((error as? WindowControlFailure)?.message ?? error.localizedDescription)
                        }
                    }
                    let current = updated
                    self.queue.asyncAfter(deadline: .now() + 0.25) {
                        var checked = current
                        if Self.hasSheet(element) {
                            checked.awaitingConfirmation = true
                            if let running = NSRunningApplication(processIdentifier: window.pid) {
                                self.revealConfirmation(window, running: running)
                            }
                            finish(checked)
                        } else { next(index + 1, checked) }
                    }
                }
            }
            next(0, WindowBatchCloseReport())
        }
    }

    private func revealConfirmation(_ window: WindowRecord, running: NSRunningApplication) {
        if let element = window.element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
        DispatchQueue.main.async { running.unhide(); running.activate(options: []) }
    }

    private func reconcileObservers(pids: Set<pid_t>) {
        for pid in Array(observers.keys) where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
            observedWindows[pid] = nil
        }
        for pid in pids where observers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, { _, element, notification, context in
                guard let context else { return }
                let service = Unmanaged<WindowService>.fromOpaque(context).takeUnretainedValue()
                service.queue.async {
                    var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
                    if notification as String == kAXUIElementDestroyedNotification as String {
                        // A destroyed element may no longer answer GetPid.
                        // CFEqual still identifies the exact remembered node.
                        service.retire(element)
                        service.notifyWindowsChanged()
                        return
                    }
                    let windows = WindowService.string(element, kAXRoleAttribute) == kAXWindowRole as String ? [element] :
                        WindowService.windowAttribute(element, kAXFocusedWindowAttribute) + WindowService.windowAttribute(element, kAXMainWindowAttribute)
                    for window in windows {
                        if notification as String == kAXWindowCreatedNotification as String,
                           let id = service.crossSpace.identifier(of: window) { service.destroyedWindowIDs[id] = nil }
                        service.remember(window, pid: pid)
                    }
                    service.notifyWindowsChanged()
                }
            }, &observer) == .success, let observer else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            let context = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                AXObserverAddNotification(observer, app, notification as CFString, context)
            }
            observers[pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
    private func remember(_ element: AXUIElement, pid: pid_t) {
        guard !(observedWindows[pid] ?? []).contains(where: { CFEqual($0, element) }) else { return }
        observedWindows[pid, default: []].append(element)
        if let observer = observers[pid] {
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
    }
    private func retire(_ element: AXUIElement) {
        for row in lastRows where row.element.map({ CFEqual($0, element) }) == true {
            if let id = row.cgID { destroyedWindowIDs[id] = row.pid }
        }
        for key in Array(observedWindows.keys) { observedWindows[key]?.removeAll { CFEqual($0, element) } }
        identities.removeAll { CFEqual($0.1, element) }
    }
    private func notifyWindowsChanged() {
        changeGeneration &+= 1
        let token = changeGeneration
        queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.changeGeneration == token else { return }
            DispatchQueue.main.async { self.onWindowsChanged?() }
        }
    }
    deinit {
        for observer in observers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
    private static func windowAttribute(_ app: AXUIElement, _ key: String) -> [AXUIElement] {
        guard let item = value(app, key), CFGetTypeID(item) == AXUIElementGetTypeID() else { return [] }
        return [item as! AXUIElement]
    }

    private static func hasSheet(_ window: AXUIElement) -> Bool {
        let children = value(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children.contains { string($0, kAXRoleAttribute) == kAXSheetRole as String }
    }

    private static func isDestroyed(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .invalidUIElement
    }

    private static func visibleScreenFrames() -> [CGRect] {
        let screens = NSScreen.screens
        let top = screens.first?.frame.maxY ?? 0
        return screens.map { screen in
            let frame = screen.visibleFrame
            return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        }
    }

    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private static func string(_ element: AXUIElement, _ key: String) -> String {
        if let result = value(element, key) as? String { return result }
        if let result = value(element, key) as? URL { return result.absoluteString }
        return ""
    }
    private static func bool(_ element: AXUIElement, _ key: String) -> Bool {
        (value(element, key) as? NSNumber)?.boolValue ?? false
    }
    private static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
    private static func cgEntries(onScreenOnly: Bool = false) -> [CGEntry] {
        let scope: CGWindowListOption = onScreenOnly ? .optionOnScreenOnly : .optionAll
        let entries = CGWindowListCopyWindowInfo([scope, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return CGEntry(id: id, pid: pid, title: entry[kCGWindowName as String] as? String ?? "", bounds: bounds,
                onScreen: (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
        }
    }
}
