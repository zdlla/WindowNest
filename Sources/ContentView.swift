import SwiftUI
import AppKit

// Qualify the property-wrapper type to avoid the macOS 27 SDK's same-named macro,
// whose implementation is unavailable in Command Line Tools installations.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct WindowBrowserView: View {
    @Environment(\.workspaceAccent) private var accent
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WindowStore
    @StateObject private var appTransition = WindowFilterTransition()
    private var visibleRecords: [WindowRecord] { store.matchingWindows(app: appTransition.displayedApp) }
    private var simple: Bool { reduceMotion || preferences.settings.effects == .minimal }

    var body: some View {
        // A navigation split registers its sidebar with the window titlebar. When
        // this page slides in/out, AppKit changes the toolbar's centering region.
        // A plain resizable split keeps sidebar layout local to the window page.
        HSplitView {
            sidebar.frame(minWidth: 192, idealWidth: 216, maxWidth: 256)
            VStack(alignment: .leading, spacing: 0) {
                header
                if !store.trusted { onboarding }
                else { collection }
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkspaceStyle.canvas)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: store.selectedApp, initial: true) { _, app in
            appTransition.select(app, animated: store.mode == .windows, simple: simple,
                order: ["com.apple.finder"] + store.apps.filter { $0.id != "com.apple.finder" }.map(\.id))
        }
        .onChange(of: store.mode) { _, mode in
            if mode != .windows { appTransition.select(store.selectedApp, animated: false, simple: simple) }
        }
        .onExitCommand { NSApp.keyWindow?.close() }
        .alert("窗匣", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("好") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private var sidebar: some View {
        // Separate selection and close-all controls. macOS List's sidebar cell
        // can flatten accessory buttons into the row's selection accessibility.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sidebarHeading("窗口收纳")
                sidebarRow("全部窗口", symbol: "rectangle.on.rectangle", count: store.windows.count, bundleID: nil)
                sidebarRow("访达文件夹", symbol: "folder", count: store.windows.filter { $0.bundleID == "com.apple.finder" }.count, bundleID: "com.apple.finder")
                if !store.apps.isEmpty {
                    sidebarHeading("按应用查看").padding(.top, 16)
                    ForEach(store.apps.filter { $0.id != "com.apple.finder" }, id: \.id) { app in
                        sidebarRow(app.name, icon: app.icon, count: app.count, bundleID: app.id)
                    }
                }
            }.padding(.horizontal, 10).padding(.vertical, 14)
        }.background(WorkspaceStyle.chrome)
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(WorkspaceStyle.secondary)
            .padding(.horizontal, 10).padding(.bottom, 5)
    }

    private func sidebarRow(_ title: String, symbol: String? = nil, icon: NSImage? = nil, count: Int, bundleID: String?) -> some View {
        HStack(spacing: 2) {
            Button { store.selectedApp = bundleID } label: {
                HStack(spacing: 9) {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: symbol ?? "app").foregroundStyle(accent) }
                    }.frame(width: 20, height: 20)
                    Text(title).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(count)").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                }.padding(.leading, 10).frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(title)，\(count) 个窗口")
                .accessibilityAddTraits(store.selectedApp == bundleID ? .isSelected : [])
            if let bundleID { closeAllButton(bundleID: bundleID, appName: title, count: count).padding(.trailing, 4) }
            else { Color.clear.frame(width: 32, height: 28).accessibilityHidden(true) }
        }
        .background(store.selectedApp == bundleID ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func closeAllButton(bundleID: String, appName: String, count: Int) -> some View {
        let busy = store.closingApplications.contains(bundleID)
        let targets = store.windows.filter { $0.bundleID == bundleID }
        return Button { store.closeAllWindows(for: bundleID) } label: {
            Group {
                if busy { ProgressView().controlSize(.mini) }
                else { Image(systemName: "xmark.square").font(.system(size: 14, weight: .medium)) }
            }.frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(WorkspaceStyle.secondary)
        .disabled(count == 0 || busy || !targets.contains { $0.controls.close } || targets.contains { store.pendingControls.contains($0.id) })
        .help("关闭 \(appName) 的全部 \(count) 个窗口；未保存的文档由原应用确认")
        .accessibilityLabel("关闭 \(appName) 的全部窗口")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.selectedApp == nil ? "全部窗口" : (store.selectedApp == "com.apple.finder" ? "访达文件夹" : store.apps.first { $0.id == store.selectedApp }?.name ?? "窗口收纳"))
                .font(WorkspaceStyle.title)
            Text("按文件夹、文档或窗口名称，找回正在做的事。")
                .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 28).padding(.bottom, 12)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 21) {
            Spacer(minLength: 5)
            HStack(spacing: 7) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("只差一步，就能收纳窗口").font(.system(size: 11, weight: .medium)).foregroundStyle(WorkspaceStyle.secondary)
            }
            Text("让每个窗口，\n都有一个清楚的名字。")
                .font(.system(size: 29, weight: .bold)).lineSpacing(6)
            Text("窗匣需要辅助功能权限，来读取窗口名称并切换窗口。\n访达显示当前文件夹名称，其他应用显示自己的窗口标题。")
                .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary).lineSpacing(6)
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "hand.raised.fill").font(.system(size: 23)).foregroundStyle(accent).padding(.top, 4)
                VStack(alignment: .leading, spacing: 9) {
                    Text("开启辅助功能").font(.system(size: 14, weight: .semibold))
                    Text("在系统设置中找到“窗匣”并打开开关。\n若未列出，点 ＋ 添加当前的窗匣.app。")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("前往授权") { store.authorize() }.libraryButton(prominent: true)
                        Button("我已开启，重新检测") { store.refresh() }.buttonStyle(.borderless)
                    }.padding(.top, 3)
                }
                Spacer(minLength: 0)
            }.padding(19).frame(maxWidth: 530, alignment: .leading)
                .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(accent.opacity(0.12)))
            Label("缩略图可稍后开启；读取名称无需屏幕录制。", systemImage: "photo.on.rectangle")
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
            Spacer(minLength: 10)
        }.padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(visibleRecords.count) 个窗口").font(.system(size: 18, weight: .semibold))
                if store.refreshing { ProgressView().controlSize(.mini) }
                Spacer()
            }.padding(.horizontal, WorkspaceStyle.gutter).padding(.vertical, 16)
            if visibleRecords.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: store.query.isEmpty ? "rectangle.stack" : "magnifyingglass").font(.system(size: 38, weight: .light)).foregroundStyle(WorkspaceStyle.secondary)
                    Text(store.query.isEmpty ? "还没有可读取的窗口" : "没有找到匹配的窗口").font(.system(size: 16, weight: .semibold))
                    Text(store.query.isEmpty ? "打开访达或其他应用窗口，再点击刷新。" : "试试文件夹名、应用名或用途备注。")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 360), spacing: 24)], spacing: 24) {
                        ForEach(visibleRecords) { record in WindowCard(store: store, previewUpdates: store.previewUpdates, record: record) }
                    }.padding(.horizontal, WorkspaceStyle.gutter).padding(.bottom, 24)
                }
            }
            if !store.unavailable.isEmpty {
                Text("部分应用暂未响应：\(store.unavailable.joined(separator: "、"))。列表可能不完整，请稍后刷新。")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, WorkspaceStyle.gutter).padding(.bottom, 8)
            }
        }
        .opacity(appTransition.contentVisible ? 1 : 0)
        .offset(x: simple ? 0 : appTransition.offset)
        .animation(simple ? .easeOut(duration: 0.08) : appTransition.contentVisible
            ? .smooth(duration: 0.18) : .easeOut(duration: 0.085), value: appTransition.contentVisible)
        .allowsHitTesting(appTransition.contentVisible && appTransition.displayedApp == store.selectedApp)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                Circle().fill(store.trusted ? .green : .orange).frame(width: 5, height: 5)
                Text(store.trusted ? "窗口名称随列表刷新" : "等待辅助功能授权").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                Spacer()
                if store.trusted {
                    if store.previewsEnabled && !store.previewPermissionGranted {
                        Button("授权缩略图…") { store.requestPreviewPermission() }.buttonStyle(.borderless).font(.system(size: 11))
                    }
                    Button { store.togglePreviews() } label: {
                        Label(store.previewsEnabled ? "关闭缩略图" : "开启缩略图", systemImage: store.previewsEnabled ? "photo.fill" : "photo")
                    }.buttonStyle(.borderless).font(.system(size: 11)).help(store.previewStatus)
                }
                Menu {
                    Button("辅助功能设置…") { store.openAccessibility() }
                    Button("退出窗匣") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape").font(.system(size: 13)) }.menuStyle(.borderlessButton).fixedSize().help("设置与退出")
            }.padding(.horizontal, WorkspaceStyle.gutter).padding(.vertical, 12)
            if let status = store.controlStatus {
                HStack(spacing: 8) {
                    Text(status).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.controlStatus = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("收起窗口操作提示")
                }.padding(.horizontal, WorkspaceStyle.gutter).padding(.bottom, 8)
            }
            if store.previewStatus.contains("授权") || store.previewStatus.contains("不可用") {
                Text(store.previewStatus).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).padding(.bottom, 8)
            }
        }
    }
}

private struct WindowCard: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var store: WindowStore
    @ObservedObject var previewUpdates: WindowPreviewUpdates
    let record: WindowRecord
    @ViewState private var hovered = false

    var body: some View {
        let _ = previewUpdates.revision
        ZStack(alignment: .topLeading) {
          Button { store.focus(record) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(WorkspaceStyle.canvas)
                    if let image = store.thumbnail(for: record.id) {
                        Image(nsImage: image).resizable().scaledToFit().nativeIconFeedback(hovered: hovered, role: .preview).padding(8)
                    } else {
                        VStack(spacing: 10) {
                            Image(nsImage: record.icon).resizable().frame(width: 52, height: 52).nativeIconFeedback(hovered: hovered)
                            Text(record.bundleID == "com.apple.finder" ? "访达文件夹" : record.appName)
                                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                        }
                    }
                    VStack { HStack { Spacer(); if record.minimized || record.hidden {
                        Text(record.minimized ? "已最小化" : "应用已隐藏").font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 4).background(.regularMaterial, in: Capsule())
                    } }; Spacer() }.padding(12)
                }.frame(height: 156)
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.aliases[record.id] ?? record.label).font(.system(size: 14, weight: .medium)).lineLimit(2).frame(height: 38, alignment: .topLeading)
                    HStack(spacing: 5) {
                        Image(nsImage: record.icon).resizable().frame(width: 14, height: 14)
                        Text(record.appName).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if store.aliases[record.id] != nil { Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(WorkspaceStyle.secondary) }
                        Image(systemName: "arrow.up.forward").font(.system(size: 11)).foregroundStyle(hovered ? accent : .secondary)
                    }
                }.padding(12)
            }
            .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hovered ? accent.opacity(0.6) : .primary.opacity(0.07), lineWidth: hovered ? 1.5 : 1))
            .shadow(color: .black.opacity(hovered ? 0.06 : 0), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 14))
          }.buttonStyle(NativePressStyle()).disabled(store.pendingControls.contains(record.id))
            .help([record.label, record.document ?? record.title].joined(separator: "\n"))
            .accessibilityLabel("\(store.aliases[record.id] ?? record.label)，\(record.appName)")
          WindowTrafficLights(store: store, record: record).padding(8)
        }
            .onAppear { store.requestPreview(record.id, surface: .main, visible: true) }
            .onDisappear { store.requestPreview(record.id, surface: .main, visible: false) }
            .onHover { hovered = $0 }
            .contextMenu {
                Button("切换到此窗口") { store.focus(record) }
                Button("添加或修改用途备注…") { store.editAlias(record) }
                if store.aliases[record.id] != nil { Button("恢复窗口名称") { store.aliases[record.id] = nil } }
                Divider()
                ForEach(WindowControlAction.allCases, id: \.self) { action in
                    Button(action.title(minimized: record.minimized, fullScreen: record.fullScreen)) { store.perform(action, on: record) }
                        .disabled(!record.controls.supports(action) || store.pendingControls.contains(record.id))
                }
            }
    }
}

struct WindowTrafficLights: View {
    @ObservedObject var store: WindowStore
    let record: WindowRecord
    var onAction: ((WindowControlAction) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach([WindowControlAction.close, .minimize, .zoom], id: \.self) { action in
                WindowTrafficLight(action: action, minimized: record.minimized,
                    enabled: record.controls.supports(action), busy: store.pendingControls.contains(record.id),
                    windowName: record.label) {
                        if let onAction { onAction(action) } else { store.perform(action, on: record) }
                    }
            }
        }
        .padding(1)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct WindowTrafficLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let action: WindowControlAction
    let minimized: Bool
    let enabled: Bool
    let busy: Bool
    let windowName: String
    var hitSize: CGFloat = 24
    var alwaysShowsSymbol = false
    let perform: () -> Void
    @ViewState private var hovered = false

    private var color: Color {
        guard enabled else { return Color(nsColor: .disabledControlTextColor) }
        switch action {
        case .close: return Color(red: 1, green: 0.37, blue: 0.34)
        case .minimize: return Color(red: 1, green: 0.74, blue: 0.18)
        case .zoom, .fullscreen: return Color(red: 0.16, green: 0.79, blue: 0.25)
        }
    }
    private var symbol: String {
        switch action {
        case .close: return "xmark"
        case .minimize: return minimized ? "arrow.up.right" : "minus"
        case .zoom: return "plus"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        }
    }
    var body: some View {
        Button(action: perform) {
            ZStack {
                Circle().fill(color.gradient)
                Circle().strokeBorder(.black.opacity(contrast == .increased ? 0.55 : 0.16), lineWidth: 0.75)
                Image(systemName: symbol).font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.70))
                    .opacity(alwaysShowsSymbol || hovered || contrast == .increased ? 1 : 0)
            }
            .frame(width: 12, height: 12)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(busy ? 0.55 : 1)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: hovered)
        .help(enabled ? action.title(minimized: minimized) : "原应用暂不支持\(action.title(minimized: minimized))")
        .accessibilityLabel("\(action.title(minimized: minimized))：\(windowName)")
    }
}
