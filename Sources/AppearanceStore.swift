import SwiftUI
import AppKit

extension ThemeAccent {
    var nsColor: NSColor {
        guard self != .system else { return .controlAccentColor }
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex: UInt32
            switch self {
            case .system: return .controlAccentColor
            case .blue: hex = dark ? 0x419CFF : 0x0068DA
            case .purple: hex = dark ? 0xBB93FF : 0x7040BE
            case .pink: hex = dark ? 0xFF80B5 : 0xB42E68
            case .orange: hex = dark ? 0xFFB264 : 0xA34D00
            case .green: hex = dark ? 0x73D9A1 : 0x187548
            }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}
private struct WorkspaceAccentKey: EnvironmentKey {
    static let defaultValue = Color(nsColor: .controlAccentColor)
}
extension EnvironmentValues {
    var workspaceAccent: Color {
        get { self[WorkspaceAccentKey.self] }
        set { self[WorkspaceAccentKey.self] = newValue }
    }
}
@MainActor
final class AppearanceStore: ObservableObject {
    @Published private(set) var settings: AppearanceSettings
    @Published var error: String?
    private let repository: AppearanceRepository
    private var writable = true
    private var pendingSave: Task<Void, Never>?
    init(repository: AppearanceRepository = .standard) {
        self.repository = repository
        do { settings = try repository.load() }
        catch { settings = AppearanceSettings(); writable = false; self.error = "未能读取外观设置，原文件已保留。\(error.localizedDescription)" }
    }
    func update(_ mutation: (inout AppearanceSettings) -> Void) {
        guard writable else { return }
        var next = settings; mutation(&next)
        guard next != settings else { return }
        pendingSave?.cancel(); pendingSave = nil
        do { try repository.save(next); settings = next }
        catch { self.error = "未能保存设置：\(error.localizedDescription)" }
    }

    func updateLive(_ mutation: (inout AppearanceSettings) -> Void) {
        guard writable else { return }
        var next = settings; mutation(&next)
        guard next != settings else { return }
        settings = next
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        guard writable, pendingSave != nil else { return }
        pendingSave?.cancel(); pendingSave = nil
        do { try repository.save(settings) }
        catch { self.error = "未能保存设置：\(error.localizedDescription)" }
    }
}
struct ThemedWorkspace<Content: View>: View {
    @ObservedObject var preferences: AppearanceStore
    let content: Content
    var body: some View {
        content.environmentObject(preferences).environment(\.workspaceAccent, preferences.settings.accent.color)
            .tint(preferences.settings.accent.color).accentColor(preferences.settings.accent.color)
    }
}
struct WorkspaceSettingsView: View {
    @ObservedObject var preferences: AppearanceStore
    @ObservedObject var windows: WindowStore
    var shortcuts: GlobalShortcutController? = nil
    var quickFolders: QuickFolderStore? = nil
    var desktopBoxes: DesktopFileBoxController? = nil
    var loginItem:LoginItemController? = nil
    var updates:UpdateController? = nil
    var onPreviewTopOverview: (() -> Void)? = nil
    var onShowTriggerRegion: (() -> Void)? = nil
    private func binding<Value>(_ key: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        Binding(get: { preferences.settings[keyPath: key] }, set: { value in preferences.update { $0[keyPath: key] = value } })
    }
    private func liveBinding(_ key: WritableKeyPath<AppearanceSettings, Double>) -> Binding<Double> {
        Binding(get: { preferences.settings[keyPath: key] }, set: { value in preferences.updateLive { $0[keyPath: key] = value } })
    }
    var body: some View {
        Form {
            if let loginItem { LoginItemSettings(controller:loginItem) }
            if let updates { UpdateSettings(controller:updates) }
            if let shortcuts { GlobalShortcutSettings(preferences: preferences, controller: shortcuts) }
            Section {
                Picker("外观", selection: binding(\.appearance)) {
                    ForEach(ThemeAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("主题颜色", selection: binding(\.accent)) {
                    ForEach(ThemeAccent.allCases) { accent in
                        Label { Text(accent.title) } icon: { Circle().fill(accent.color).frame(width: 12, height: 12) }.tag(accent)
                    }
                }
            } header: { Text("外观") }
            Section {
                Picker("整体特效", selection: binding(\.effects)) {
                    ForEach(WorkspaceEffects.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(preferences.settings.effects.detail).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 26)).foregroundStyle(preferences.settings.accent.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("让每次展开，都有条理").font(.system(size: 13, weight: .medium))
                        Text("图标按排列顺序缩放，关闭时反向收拢。").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                    }
                }.padding(.vertical, 6)
            } header: { Text("动态与材质") } footer: {
                Text("始终尊重系统的“减少动态效果”和“减少透明度”设置。")
            }
            Section {
                Toggle("显示窗口缩略图", isOn: binding(\.previewsEnabled))
                Text(windows.previewStatus).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                if !windows.previewPermissionGranted {
                    Button("授权屏幕录制…") { windows.requestPreviewPermission() }.libraryButton()
                }
            } header: { Text("窗口") } footer: { Text("默认开启。缩略图仅在窗口页或顶部速览可见时生成，保存在内存中。") }
            Section {
                Toggle("启用顶部窗口速览", isOn: binding(\.topOverviewEnabled))
                if preferences.settings.topOverviewEnabled {
                    adjustment("窗格高度", value: liveBinding(\.topOverviewHeightPercent), range: 5...55, step: 1,
                        display: "\(Int(preferences.settings.topOverviewHeightPercent))%")
                    Text("低于 10% 自动显示图标与窗口名称，不生成顶部缩略图；空间不足时也会采用紧凑布局。最低保留 44 点点击空间。")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                    Text("仅在所选区域内触发；鼠标可以直接顶到该区域的屏幕上沿。").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                    Picker("触发位置", selection: binding(\.topOverviewPosition)) {
                        ForEach(TopOverviewPosition.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    adjustment("区域宽度", value: liveBinding(\.topOverviewWidthPercent), range: 10...100, step: 5,
                        display: "\(Int(preferences.settings.topOverviewWidthPercent))%")
                    adjustment("区域高度", value: liveBinding(\.topOverviewDepth), range: 4...64, step: 2,
                        display: "\(Int(preferences.settings.topOverviewDepth)) 点")
                    adjustment("停留时间", value: liveBinding(\.topOverviewDelay), range: 0...1.5, step: 0.05,
                        display: preferences.settings.topOverviewDelay == 0 ? "立即" : String(format: "%.2f 秒", preferences.settings.topOverviewDelay))
                    Text("区域高度从屏幕顶边向下计算，高亮范围就是实际触发范围。需要整个顶边触发时，将区域宽度设为 100%。设置会自动保存。")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                }
                HStack {
                    Text("范围清楚，随时呼出").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                    Spacer()
                    Button("显示区域") { onShowTriggerRegion?() }
                        .disabled(!preferences.settings.topOverviewEnabled).libraryButton()
                    Button("立即预览") { onPreviewTopOverview?() }
                        .disabled(!preferences.settings.topOverviewEnabled).libraryButton()
                }
            } header: { Text("顶部速览") } footer: {
                Text("调整触发位置、宽度或高度时，屏幕会高亮实际触发区域，4 秒后自动消失；也可点击“显示区域”再次查看。默认中央 20%、停留 0.2 秒。窗口多时横向浏览，移出自动收起，拖动时不触发。")
            }
            if let quickFolders { QuickFolderSettings(store: quickFolders) }
            if let desktopBoxes { DesktopBoxSettings(controller:desktopBoxes) }
            if let error = preferences.error { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
            .background(WorkspaceStyle.canvas).padding(8)
            .frame(width: 520, height: min(760, max(500, (NSScreen.main?.visibleFrame.height ?? 840) - 80)))
            .onDisappear { preferences.flush() }
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
            Text(display).monospacedDigit().foregroundStyle(WorkspaceStyle.secondary).frame(width: 64, alignment: .trailing)
        }
    }
}
