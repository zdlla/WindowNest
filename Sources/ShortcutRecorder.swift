import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var controller: GlobalShortcutController
    let shortcut: GlobalShortcut?
    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton(controller: controller) }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        if !controller.recording { button.title = shortcut?.display ?? "点击录制快捷键" }
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.cancelRecording() }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    private let controller: GlobalShortcutController
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    init(controller: GlobalShortcutController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 34))
        target = self; action = #selector(record)
        isBordered = false; wantsLayer = true
        font = .systemFont(ofSize: 13, weight: .medium)
        updateSurface()
        setAccessibilityLabel("录制窗匣全局呼出快捷键")
        toolTip = "点击后按新组合；Esc 取消，不会覆盖系统快捷键"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); updateSurface() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
    private func updateSurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = bounds.height / 2
            layer?.backgroundColor = WorkspaceColors.chrome.cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
            layer?.borderWidth = 0.5
        }
    }
    @objc private func record() {
        guard monitor == nil, let window else { return }
        controller.beginRecording()
        title = "请按快捷键…（Esc 取消）"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window, NSApp.isActive else { self.cancelRecording(); return event }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
            let labels: [UInt16: String] = [49:"空格",36:"↩",48:"⇥",51:"⌫",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",
                122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
            let label = labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
            let chord = GlobalShortcut(keyCode: event.keyCode, modifiers: GlobalShortcutController.carbonModifiers(event.modifierFlags), keyLabel: label)
            self.finishRecording()
            _ = self.controller.choose(chord)
            return nil
        }
        guard monitor != nil else { controller.endRecording(); title = "无法开始录制，请重试"; return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }
    private func finishRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        controller.endRecording()
    }
    func cancelRecording() { if monitor != nil { finishRecording() } }
}

struct GlobalShortcutSettings: View {
    @ObservedObject var preferences: AppearanceStore
    @ObservedObject var controller: GlobalShortcutController
    var body: some View {
        Section {
            Toggle("启用全局呼出快捷键", isOn: Binding(get: { preferences.settings.globalShortcutEnabled }, set: { controller.enable($0) }))
                .disabled(controller.recording)
            HStack {
                Text("单键呼出")
                Spacer()
                Button("右 ⌥ 单按") { _ = controller.chooseSingle(.rightOption) }.disabled(controller.recording)
                    .libraryButton(prominent: preferences.settings.shortcutSingleKey == .rightOption)
                Button("右 ⌘ 单按") { _ = controller.chooseSingle(.rightCommand) }.disabled(controller.recording)
                    .libraryButton(prominent: preferences.settings.shortcutSingleKey == .rightCommand)
            }
            Text("轻按松开即可；与其他键一起使用、鼠标点击或长按时不会呼出。").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
            Toggle("同时启用 ⌘ + ⌃ 呼出", isOn: Binding(get: { preferences.settings.commandControlShortcutEnabled }, set: { enabled in
                preferences.update { $0.commandControlShortcutEnabled = enabled; if enabled { $0.globalShortcutEnabled = true } }
            })).disabled(controller.recording)
            if preferences.settings.commandControlShortcutEnabled {
                Text(controller.commandControlStatus).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                Text("同时按下 Command 与 Control，再全部松开；加按其他键、点击鼠标或长按不触发。右侧 Option 仍可同时使用。")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
            }
            HStack {
                Text("自定义组合键")
                Spacer()
                ShortcutRecorder(controller: controller, shortcut: preferences.settings.globalShortcut).frame(width: 190, height: 34)
            }
            HStack {
                Text(preferences.settings.shortcutSingleKey == nil ? "可点击上方录制组合键" : "当前使用单键，自定义组合键已停用")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                Spacer()
                Button("清除") { controller.clear() }.disabled(controller.recording || (preferences.settings.globalShortcut == nil && preferences.settings.shortcutSingleKey == nil && !preferences.settings.commandControlShortcutEnabled))
            }
            Text(controller.status).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
        } header: { Text("快捷呼出") } footer: {
            Text("窗匣保持运行时生效，关闭主窗口后仍可呼出。单键使用已有的辅助功能权限，仅判断是否单按，不记录输入内容；密码等安全输入场景暂停单键。组合键会检查系统和已注册组合，第三方私有监听无法保证全部检测，若重合可更换。")
        }
    }
}
