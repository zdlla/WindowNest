import AppKit
import SwiftUI
import ApplicationServices
import ScreenCaptureKit

@MainActor
final class WindowStore: ObservableObject {
    @Published var mode: WorkspaceMode {
        didSet { if oldValue != mode { saveCurrentPage(); updateActiveSurfaces() } }
    }
    @Published var windows: [WindowRecord] = [] {
        didSet {
            appGroups = Dictionary(grouping: windows, by: \.bundleID).compactMap { key, values in
                guard let first = values.first else { return nil }
                return (key, first.appName, first.icon, values.count)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    @Published var query = ""
    @Published var selectedApp: String?
    @Published var trusted = AXIsProcessTrusted()
    @Published var refreshing = false
    @Published var unavailable: [String] = []
    @Published var message: String?
    @Published var aliases: [UUID: String] = [:]
    let previewUpdates = WindowPreviewUpdates()
    private(set) var thumbnailRevision: Int {
        get { previewUpdates.revision }
        set { previewUpdates.revision = newValue }
    }
    @Published private(set) var previewsEnabled = true
    @Published private(set) var previewPermissionGranted = CGPreflightScreenCaptureAccess()
    @Published var previewStatus = "缩略图已开启"
    var onPreviewPreferenceChange: ((Bool) -> Void)?
    private(set) var refreshedAt: Date?
    @Published private(set) var pendingControls: Set<UUID> = []
    @Published private(set) var closingApplications: Set<String> = []
    @Published var controlStatus: String?
    let service = WindowService()
    var onFocus: (() -> Void)?
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var captureDebounce: Task<Void, Never>?
    private let thumbnailCache = LRUCache<UUID, NSImage>(totalCostLimit: WindowPreviewBudget.maxBytes, countLimit: WindowPreviewBudget.maxCount)
    private var attemptedCapture: [UUID: TimeInterval] = [:]
    private var mainPreviewDemand = Set<UUID>()
    private var overviewPreviewDemand = Set<UUID>()
    private var generation = 0
    private var visible = false
    private var overviewVisible = false
    private var overviewAllowsPreviews = true
    private var windowModeVisible: Bool { visible && mode == .windows }
    private var previewSurfaceVisible: Bool { windowModeVisible || overviewVisible }
    private let pageState: WorkspaceStateRepository
    private var catalogRevision = 0
    private var refreshAgain = false
    private var scanning = false
    private var lastScanCompleted: TimeInterval?
    private var deferredRefresh: Task<Void, Never>?
    private var overviewPreviewNotBefore: TimeInterval = 0
    private var appGroups: [(id: String, name: String, icon: NSImage, count: Int)] = []
    private var applicationObservers: [NSObjectProtocol] = []

    init(pageState: WorkspaceStateRepository = .standard, previewsEnabled: Bool = true) {
        self.previewsEnabled = previewsEnabled
        self.pageState = pageState
        do { mode = try pageState.load() }
        catch { mode = .windows; message = "未能读取上次页面，已打开窗口收纳。\(error.localizedDescription)" }
        updatePreviewAvailability()
        service.onWindowsChanged = { [weak self] in
            guard let self, self.previewSurfaceVisible else { return }
            self.refresh(showProgress: false)
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            applicationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.previewSurfaceVisible else { return }
                    self.refresh(showProgress: false)
                }
            })
        }
        // Seed the metadata catalog once; subsequent hidden-time additions are
        // remembered by AX notifications, without a screenshot or polling loop.
        if trusted { refresh(showProgress: false) }
    }

    deinit { applicationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    func saveCurrentPage() {
        do { try pageState.save(mode) }
        catch { message = "未能保存上次页面：\(error.localizedDescription)" }
    }

    var filtered: [WindowRecord] {
        matchingWindows(app: selectedApp)
    }
    func matchingWindows(app: String?) -> [WindowRecord] {
        windows.filter { window in
            (app == nil || window.bundleID == app) &&
            WindowNaming.matches(query: query, fields: [window.appName, window.label, window.title, window.document ?? "", aliases[window.id] ?? ""])
        }
    }
    var apps: [(id: String, name: String, icon: NSImage, count: Int)] {
        appGroups
    }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        updateActiveSurfaces()
    }

    func setOverviewVisible(_ value: Bool, previews: Bool = true) {
        guard overviewVisible != value || overviewAllowsPreviews != previews else { return }
        overviewVisible = value
        overviewAllowsPreviews = previews
        if value { overviewPreviewNotBefore = ProcessInfo.processInfo.systemUptime + 0.45 }
        if !previews {
            overviewPreviewDemand.removeAll()
            let keep = previewDemand
            var removedImages = false
            for id in thumbnailCache.keys where !keep.contains(id) {
                thumbnailCache.removeValue(forKey: id)
                attemptedCapture[id] = nil
                removedImages = true
            }
            if keep.isEmpty {
                captureTask?.cancel(); generation += 1
                clearPreviews()
            } else if removedImages { thumbnailRevision &+= 1 }
        }
        updateActiveSurfaces()
    }

    private func updateActiveSurfaces() {
        timer?.invalidate()
        timer = nil
        if previewSurfaceVisible {
            refresh(showProgress: false)
            let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(showProgress: false) }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            deferredRefresh?.cancel(); deferredRefresh = nil
            captureTask?.cancel()
            generation += 1
            clearPreviews()
        }
    }

    func refresh(showProgress: Bool = true) {
        if !showProgress, let lastScanCompleted {
            let delay = 0.75 - (ProcessInfo.processInfo.systemUptime - lastScanCompleted)
            if delay > 0 {
                guard previewSurfaceVisible, deferredRefresh == nil else { return }
                deferredRefresh = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self else { return }
                    self.deferredRefresh = nil
                    if self.previewSurfaceVisible { self.refresh(showProgress: false) }
                }
                return
            }
        }
        deferredRefresh?.cancel(); deferredRefresh = nil
        let permission = AXIsProcessTrusted()
        if trusted != permission { trusted = permission }
        guard trusted else { windows = []; return }
        guard !scanning else { refreshAgain = true; return }
        scanning = true
        if showProgress || windows.isEmpty { refreshing = true }
        let revision = catalogRevision
        service.scan { [weak self] rows, failed in
            guard let self else { return }
            if revision != self.catalogRevision {
                self.scanning = false
                if self.refreshing { self.refreshing = false }
                self.refreshAgain = false; self.refresh(showProgress: false); return
            }
            let previous = Dictionary(uniqueKeysWithValues: self.windows.map { ($0.id, $0) })
            for row in rows {
                if let old = previous[row.id], old.title != row.title || old.document != row.document || old.minimized != row.minimized {
                    self.attemptedCapture[row.id] = nil
                    self.thumbnailCache.removeValue(forKey: row.id)
                }
            }
            if !WindowRecord.sameCatalog(self.windows, rows) { self.windows = rows }
            if self.unavailable != failed { self.unavailable = failed }
            self.scanning = false
            self.lastScanCompleted = ProcessInfo.processInfo.systemUptime
            if self.refreshing { self.refreshing = false }
            self.refreshedAt = .now
            let ids = Set(rows.map(\.id))
            let aliases = self.aliases.filter { ids.contains($0.key) }
            if aliases != self.aliases { self.aliases = aliases }
            for key in self.thumbnailCache.keys where !ids.contains(key) { self.thumbnailCache.removeValue(forKey: key) }
            self.attemptedCapture = self.attemptedCapture.filter { ids.contains($0.key) }
            self.mainPreviewDemand.formIntersection(ids)
            self.overviewPreviewDemand.formIntersection(ids)
            if let selected = self.selectedApp, !rows.contains(where: { $0.bundleID == selected }) { self.selectedApp = nil }
            if self.previewSurfaceVisible && self.previewsEnabled { self.capturePreviews() }
            if self.refreshAgain {
                self.refreshAgain = false
                if self.previewSurfaceVisible { self.refresh(showProgress: false) }
            }
        }
    }

    func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibility()
    }

    func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func focus(_ record: WindowRecord, completion: ((String?) -> Void)? = nil) {
        guard !pendingControls.contains(record.id) else { return }
        service.focus(record) { [weak self] error in
            guard let self else { return }
            if let error {
                if error == WindowFocusUnavailable.message {
                    self.catalogRevision += 1
                    self.windows.removeAll { $0.id == record.id }
                    self.thumbnailCache.removeValue(forKey: record.id)
                    self.attemptedCapture[record.id] = nil
                    self.mainPreviewDemand.remove(record.id); self.overviewPreviewDemand.remove(record.id)
                    self.thumbnailRevision &+= 1
                    if let selected = self.selectedApp, !self.windows.contains(where: { $0.bundleID == selected }) { self.selectedApp = nil }
                    self.controlStatus = error
                    self.refresh()
                    completion?(error)
                    return
                }
                if !WindowFocusInterruption.contains(error) {
                    if completion == nil { self.message = error }
                    self.refresh()
                }
            }
            else { self.onFocus?() }
            completion?(error)
        }
    }

    func perform(_ action: WindowControlAction, on record: WindowRecord, completion: ((String?) -> Void)? = nil) {
        guard !pendingControls.contains(record.id), record.controls.supports(action) else { return }
        pendingControls.insert(record.id)
        controlStatus = nil
        service.perform(action, on: record) { [weak self] error in
            guard let self else { return }
            if let error, completion == nil { self.message = error }
            completion?(error)
            // Never optimistically remove a card: the owning app may be asking
            // to save, or the user may cancel. Scanning is the source of truth.
            self.refresh()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(850))
                guard let self else { return }
                self.pendingControls.remove(record.id)
                self.refresh()
            }
        }
    }

    func closeAllWindows(for bundleID: String) {
        let targets = windows.filter { $0.bundleID == bundleID }
        let ids = Set(targets.map(\.id))
        guard !targets.isEmpty, !closingApplications.contains(bundleID), pendingControls.isDisjoint(with: ids) else { return }
        closingApplications.insert(bundleID)
        pendingControls.formUnion(ids)
        controlStatus = "正在关闭 \(targets[0].appName) 的 \(targets.count) 个窗口…"
        service.closeAll(targets) { [weak self] report in
            guard let self else { return }
            self.controlStatus = report.message
            self.refresh()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(850))
                guard let self else { return }
                self.pendingControls.subtract(ids)
                self.closingApplications.remove(bundleID)
                self.refresh()
            }
        }
    }

    func editAlias(_ record: WindowRecord) {
        let alert = NSAlert()
        alert.messageText = "这个窗口用来做什么？"
        alert.informativeText = "\(record.label)\n备注会显示在卡片下方；留空可恢复原标题。本次运行有效，关闭窗口后清除。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: aliases[record.id] ?? "")
        field.placeholderString = "例如：论文资料、项目代码、待处理文件"
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 26)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            aliases[record.id] = value.isEmpty ? nil : value
        }
    }

    func togglePreviews() {
        if let onPreviewPreferenceChange { onPreviewPreferenceChange(!previewsEnabled) }
        else { setPreviewsEnabled(!previewsEnabled) }
    }
    func setPreviewsEnabled(_ enabled: Bool) {
        guard previewsEnabled != enabled else { updatePreviewAvailability(); return }
        previewsEnabled = enabled
        updatePreviewAvailability()
        if enabled { capturePreviews() }
        else {
            captureTask?.cancel(); generation += 1
            clearPreviews()
        }
    }
    private func updatePreviewAvailability() {
        let granted = CGPreflightScreenCaptureAccess()
        if previewPermissionGranted != granted { previewPermissionGranted = granted }
        let status = !previewsEnabled ? "缩略图已关闭" : granted
            ? "缩略图仅保存在内存中" : "缩略图已开启，等待屏幕录制授权"
        if previewStatus != status { previewStatus = status }
    }
    func requestPreviewPermission() {
        _ = CGRequestScreenCaptureAccess()
        updatePreviewAvailability()
        if previewPermissionGranted { if previewsEnabled { capturePreviews() } }
        else {
            previewStatus = "授权屏幕录制后返回窗匣；必要时退出重开"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func capturePreviews() {
        // A slow capture must not be restarted by the next refresh tick.
        guard captureTask == nil, previewSurfaceVisible, previewsEnabled else { return }
        if !windowModeVisible && overviewVisible && ProcessInfo.processInfo.systemUptime < overviewPreviewNotBefore {
            scheduleCapture(); return
        }
        updatePreviewAvailability()
        // Default-on never silently opens a permission prompt or captures without permission.
        guard previewPermissionGranted else { return }
        let demand = previewDemand
        let now = ProcessInfo.processInfo.systemUptime
        let due = Set(WindowPreviewBudget.due(windows.map(\.id), demand: demand, attempted: attemptedCapture, now: now))
        let records = windows.filter { due.contains($0.id) }
        guard !records.isEmpty else { return }
        generation += 1
        let token = generation
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.captureTask = nil
                if self.previewSurfaceVisible && self.previewsEnabled && self.previewDemand.contains(where: { self.attemptedCapture[$0] == nil }) {
                    self.scheduleCapture()
                }
            }
            var updates: [(UUID, NSImage, Int)] = []
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                for record in records {
                    guard !Task.isCancelled, self.generation == token, self.previewSurfaceVisible, self.previewsEnabled else { return }
                    guard self.previewDemand.contains(record.id) else { continue }
                    self.attemptedCapture[record.id] = ProcessInfo.processInfo.systemUptime
                    guard let id = record.cgID, let window = content.windows.first(where: { $0.windowID == id }) else { continue }
                    let config = SCStreamConfiguration()
                    let scale = min(WindowPreviewBudget.maxWidth / max(1, window.frame.width), WindowPreviewBudget.maxHeight / max(1, window.frame.height))
                    config.width = max(1, Int(window.frame.width * scale))
                    config.height = max(1, Int(window.frame.height * scale))
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    do {
                        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        guard !Task.isCancelled, self.generation == token else { return }
                        if self.windows.contains(where: { $0.id == record.id }) {
                            updates.append((record.id, NSImage(cgImage: image, size: .zero), image.bytesPerRow * image.height))
                        }
                    } catch {
                        // Minimized, protected and unshareable windows keep their application icon.
                    }
                }
                guard !Task.isCancelled, self.generation == token else { return }
                let currentDemand = self.previewDemand
                for (id, image, cost) in updates where currentDemand.contains(id) {
                    self.thumbnailCache.setValue(image, forKey: id, cost: cost)
                }
                if !updates.isEmpty { self.thumbnailRevision &+= 1 }
            } catch {
                guard self.generation == token else { return }
                self.previewStatus = "缩略图不可用：请检查屏幕录制权限，必要时重启窗匣"
                for record in records { self.attemptedCapture[record.id] = ProcessInfo.processInfo.systemUptime }
            }
        }
    }

    func thumbnail(for id: UUID) -> NSImage? { thumbnailCache.value(forKey: id) }

    func requestPreview(_ id: UUID, surface: WindowPreviewSurface, visible: Bool) {
        switch surface {
        case .main:
            if visible { mainPreviewDemand.insert(id) } else { mainPreviewDemand.remove(id) }
        case .overview:
            if visible && overviewAllowsPreviews { overviewPreviewDemand.insert(id) } else { overviewPreviewDemand.remove(id) }
        }
        if visible && previewSurfaceVisible && previewsEnabled { scheduleCapture() }
    }

    private var previewDemand: Set<UUID> {
        WindowPreviewBudget.requested(windows.map(\.id), main: mainPreviewDemand, overview: overviewPreviewDemand,
            mainVisible: windowModeVisible, overviewVisible: overviewVisible, overviewAllowsPreviews: overviewAllowsPreviews)
    }

    private func scheduleCapture() {
        captureDebounce?.cancel()
        let delay = !windowModeVisible && overviewVisible
            ? max(0.1, overviewPreviewNotBefore - ProcessInfo.processInfo.systemUptime) : 0.1
        captureDebounce = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.capturePreviews()
        }
    }

    private func clearPreviews() {
        captureDebounce?.cancel(); captureDebounce = nil
        let hadImages = thumbnailCache.count > 0
        thumbnailCache.removeAll()
        attemptedCapture.removeAll()
        if hadImages { thumbnailRevision &+= 1 }
    }
}
