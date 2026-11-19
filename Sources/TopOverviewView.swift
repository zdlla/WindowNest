import SwiftUI
import AppKit

private typealias TopViewState<Value> = SwiftUI.State<Value>

struct TopOverviewView: View {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.workspaceAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WindowStore
    @ObservedObject var presentation: TopOverviewPresentation
    @ObservedObject var folders: QuickFolderStore
    @StateObject private var filterTransition = WindowFilterTransition()
    @Namespace private var tabHighlight
    let onDismiss: () -> Void
    let onOpenWorkspace: () -> Void
    let onAddFolder: () -> Void
    let onOpenFolder: (QuickFolder) -> Void
    let onPerform: (WindowControlAction, WindowRecord) -> Void
    let onFocus: (WindowRecord) -> Void
    let onAuthorize: (Bool) -> Void
    private var simple: Bool { reduceMotion || preferences.settings.effects == .minimal }
    private var records: [WindowRecord] {
        store.windows.filter { filterTransition.displayedApp == nil || $0.bundleID == filterTransition.displayedApp }
    }

    var body: some View {
        Group {
        if presentation.layout.iconsOnly { compactBar }
        else {
        VStack(alignment: .leading, spacing: 8) {
            header
            Group {
            if !store.trusted {
                placeholder("开启辅助功能后，即可在这里查看和管理窗口", symbol: "rectangle.on.rectangle") {
                    Button("前往授权") { onAuthorize(false) }.libraryButton(prominent: true)
                }
            } else if records.isEmpty {
                placeholder(store.refreshing ? "正在读取窗口…" : "暂时没有可显示的窗口", symbol: "rectangle.stack") {
                    Button("刷新窗口") { store.refresh() }.libraryButton()
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            TopOverviewCard(store: store, previewUpdates: store.previewUpdates, record: record,
                                previewHeight: presentation.layout.previewHeight,
                                onFocus: { onFocus(record) },
                                onPerform: { onPerform($0, record) })
                                .frame(width: presentation.layout.cardWidth)
                                .opacity(presentation.visible ? 1 : 0)
                                .scaleEffect(presentation.visible || simple ? 1 : 0.97, anchor: .top)
                                .animation(simple ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.90)
                                    .delay(presentation.visible ? Double(min(index, 8)) * 0.018 : 0), value: presentation.visible)
                        }
                    }.padding(.horizontal, 2).padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .id(filterTransition.displayedApp ?? "__all_windows")
            }
            }
            .opacity(filterTransition.contentVisible ? 1 : 0)
            .offset(x: simple ? 0 : filterTransition.offset)
            .animation(simple ? .easeOut(duration: 0.08) : filterTransition.contentVisible
                ? .smooth(duration: 0.18) : .easeOut(duration: 0.085), value: filterTransition.contentVisible)
            .allowsHitTesting(filterTransition.contentVisible && filterTransition.displayedApp == presentation.selectedApp)
        }
        }
        }
        .padding(.horizontal, presentation.layout.iconsOnly ? 12 : 16)
        .padding(.vertical, presentation.layout.iconsOnly ? 6 : 12)
        .frame(width: presentation.layout.panel.width, height: presentation.layout.panel.height,
            alignment: presentation.layout.iconsOnly ? .center : .topLeading)
        .topOverviewPanelSurface(radius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
            if let notice = presentation.notice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(notice).font(.system(size: 12)).lineLimit(2)
                    Button { presentation.notice = nil } label: {
                        Image(systemName: "xmark").frame(width: 24, height: 24)
                    }.buttonStyle(.plain).accessibilityLabel("关闭提示")
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(12).accessibilityElement(children: .contain)
            }
        }
        .allowsHitTesting(presentation.visible)
        .onChange(of: store.windows.map(\.bundleID)) { _, ids in
            if let selected = presentation.selectedApp, !ids.contains(selected) { presentation.selectedApp = nil }
        }
        .onChange(of: presentation.selectedApp, initial: true) { _, app in
            filterTransition.select(app, animated: presentation.visible, simple: simple, order: store.apps.map(\.id))
        }
        .onChange(of: presentation.visible) { _, visible in
            if !visible { filterTransition.select(presentation.selectedApp, animated: false, simple: simple) }
        }
        .onChange(of: folders.error) { _, error in
            if let error { presentation.notice = error }
        }
    }

    private var compactBar: some View {
        VStack(spacing: 4) {
            if presentation.layout.panel.height >= 72 { header }
            HStack(spacing: 10) {
                if presentation.layout.panel.height < 72 {
                    appFilters.frame(width: min(600, presentation.layout.panel.width * 0.36))
                }
                if !store.trusted {
                    Button("开启辅助功能") { onAuthorize(false) }.libraryButton()
                    Spacer(minLength: 0)
                } else if records.isEmpty {
                    Text(store.refreshing ? "正在读取窗口…" : "暂无窗口").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                    Spacer(minLength: 0)
                } else {
                    GeometryReader { geometry in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                ForEach(records) { record in
                                    TopOverviewIconCard(store: store, record: record, height: compactRowHeight,
                                        onFocus: { onFocus(record) },
                                        onPerform: { onPerform($0, record) })
                                        .frame(width: TopOverviewLayout.iconCardWidth(available: geometry.size.width - 4, count: records.count))
                                }
                            }.padding(.horizontal, 2)
                        }.scrollIndicators(.never)
                    }.frame(height: compactRowHeight)
                    .opacity(filterTransition.contentVisible ? 1 : 0)
                    .offset(x: simple ? 0 : filterTransition.offset)
                    .allowsHitTesting(filterTransition.contentVisible && filterTransition.displayedApp == presentation.selectedApp)
                }
                if presentation.layout.panel.height < 72 {
                    HStack(spacing: 6) {
                        compactButton("chevron.up", title: "收起顶部速览", action: onDismiss)
                        folderShortcuts
                    }.fixedSize()
                }
            }
        }
    }
    private var compactRowHeight: CGFloat {
        min(44, max(28, presentation.layout.panel.height - (presentation.layout.panel.height >= 72 ? 44 : 12)))
    }
    private var appFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                filter("全部", id: nil, icon: nil, count: store.windows.count)
                ForEach(store.apps, id: \.id) { app in
                    filter(app.name, id: app.id, icon: app.icon, count: app.count)
                }
            }.animation(simple ? .easeOut(duration: 0.1) : .smooth(duration: 0.24), value: presentation.selectedApp)
        }.scrollIndicators(.never).frame(height: 28)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(accent)
                Text("窗口速览").font(.system(size: 13, weight: .semibold))
            }.fixedSize()
            appFilters
            HStack(spacing: 4) {
                if !presentation.layout.iconsOnly && store.previewsEnabled && !store.previewPermissionGranted {
                    Button("授权预览…") { onAuthorize(true) }.buttonStyle(.borderless).font(.system(size: 11))
                }
                compactButton("arrow.clockwise", title: "刷新窗口", action: { store.refresh() })
                compactButton("arrow.up.forward.app", title: "打开窗匣", action: onOpenWorkspace)
                compactButton("chevron.up", title: "收起顶部速览", action: onDismiss)
                Divider().frame(height: 16).padding(.horizontal, 5)
                folderShortcuts
            }.fixedSize()
        }.frame(height: 28)
    }

    private func filter(_ title: String, id: String?, icon: NSImage?, count: Int) -> some View {
        let selected = presentation.selectedApp == id
        return Button { presentation.selectedApp = id; presentation.notice = nil } label: {
            HStack(spacing: 5) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                Text(title).lineLimit(1)
                Text("\(count)").foregroundStyle(WorkspaceStyle.secondary).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).frame(height: 28)
            .background {
                if selected {
                    if simple { Capsule().fill(accent.opacity(0.13)) }
                    else { Capsule().fill(accent.opacity(0.13)).matchedGeometryEffect(id: "selected-application", in: tabHighlight) }
                }
            }
            .overlay(Capsule().strokeBorder(selected ? accent.opacity(0.25) : .clear, lineWidth: 0.5))
            .contentShape(Capsule())
        }.buttonStyle(NativePressStyle()).nativeHoverFeedback(in: Capsule(), selected: selected).accessibilityLabel("筛选\(title)，\(count) 个窗口")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Separate from the application filters and window cards. Folder count
    /// only widens this strip up to its budget; it never expands the panel.
    private var folderShortcuts: some View {
        QuickFolderShortcuts(store: folders,
            width: min(400, presentation.layout.panel.width * (presentation.layout.panel.height < 72 ? 0.24 : 0.32)),
            onAdd: onAddFolder, onOpen: onOpenFolder)
    }

    private func compactButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Circle())
        }.buttonStyle(NativePressStyle(scaleLabel: true)).nativeHoverFeedback(in: Circle()).help(title).accessibilityLabel(title)
    }

    private func placeholder<Actions: View>(_ title: String, symbol: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(WorkspaceStyle.secondary)
            Text(title).font(.system(size: 13))
            actions()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TopOverviewCard: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var store: WindowStore
    @ObservedObject var previewUpdates: WindowPreviewUpdates
    let record: WindowRecord
    let previewHeight: CGFloat
    let onFocus: () -> Void
    let onPerform: (WindowControlAction) -> Void
    @TopViewState private var hovered = false

    var body: some View {
        let _ = previewUpdates.revision
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Button(action: onFocus) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WorkspaceStyle.canvas.opacity(0.8))
                        if let preview = store.thumbnail(for: record.id) {
                            Image(nsImage: preview).resizable().scaledToFit().nativeIconFeedback(hovered: hovered, role: .preview).padding(3)
                        } else {
                            Image(nsImage: record.icon).resizable().scaledToFit()
                                .frame(width: min(42, previewHeight * 0.5), height: min(42, previewHeight * 0.5))
                                .nativeIconFeedback(hovered: hovered)
                        }
                    }.frame(height: previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(hovered ? accent.opacity(0.7) : .primary.opacity(0.10), lineWidth: hovered ? 1.5 : 0.5))
                }.buttonStyle(NativePressStyle()).disabled(store.pendingControls.contains(record.id))
                    .help("切换到 \(record.label)").accessibilityLabel("切换到\(record.label)，\(record.appName)")
                HStack(alignment: .top) {
                    WindowTrafficLights(store: store, record: record, onAction: onPerform)
                    Spacer(minLength: 4)
                    Button { onPerform(.fullscreen) } label: {
                        Image(systemName: record.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28)
                            .background(.regularMaterial, in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).disabled(!record.controls.fullscreen || store.pendingControls.contains(record.id))
                        .help(record.fullScreen ? "退出全屏" : "全屏显示")
                        .accessibilityLabel("\(record.fullScreen ? "退出全屏" : "全屏显示")：\(record.label)")
                }.padding(5)
            }
            HStack(spacing: 5) {
                Image(nsImage: record.icon).resizable().frame(width: 14, height: 14)
                Text(store.aliases[record.id] ?? record.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if record.minimized || record.hidden {
                    Image(systemName: record.minimized ? "minus.circle" : "eye.slash").font(.system(size: 10))
                        .foregroundStyle(WorkspaceStyle.secondary)
                }
            }.frame(height: 18).help("\(record.label)\n\(record.appName)")
        }
        .onAppear { store.requestPreview(record.id, surface: .overview, visible: true) }
        .onDisappear { store.requestPreview(record.id, surface: .overview, visible: false) }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("切换到此窗口", action: onFocus)
            Divider()
            ForEach(WindowControlAction.allCases, id: \.self) { action in
                Button(action.title(minimized: record.minimized, fullScreen: record.fullScreen)) { onPerform(action) }
                    .disabled(!record.controls.supports(action) || store.pendingControls.contains(record.id))
            }
        }
    }
}

/// Icon-only mode deliberately has no preview request or thumbnail lookup.
private struct TopOverviewIconCard: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var store: WindowStore
    let record: WindowRecord
    let height: CGFloat
    let onFocus: () -> Void
    let onPerform: (WindowControlAction) -> Void
    @TopViewState private var hovered = false
    var body: some View {
        HStack(spacing: 2) {
            Button(action: onFocus) {
                HStack(spacing: 7) {
                    Image(nsImage: record.icon).resizable().scaledToFit().frame(width: 24, height: 24)
                        .nativeIconFeedback(hovered: hovered)
                    Text(store.aliases[record.id] ?? record.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 8).frame(maxWidth: .infinity, minHeight: height)
                    .contentShape(Rectangle())
            }.buttonStyle(NativePressStyle()).disabled(store.pendingControls.contains(record.id))
                .accessibilityLabel("切换到\(record.label)，\(record.appName)")
            WindowTrafficLight(action: .close, minimized: record.minimized,
                enabled: record.controls.close, busy: store.pendingControls.contains(record.id),
                windowName: record.label, hitSize: 28, alwaysShowsSymbol: true) { onPerform(.close) }
            Menu {
                ForEach(WindowControlAction.allCases, id: \.self) { action in
                    Button(action.title(minimized: record.minimized, fullScreen: record.fullScreen)) { onPerform(action) }
                        .disabled(!record.controls.supports(action) || store.pendingControls.contains(record.id))
                }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("管理窗口：\(record.label)")
        }
        .padding(.trailing, 4).frame(height: height)
        .background(WorkspaceStyle.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovered ? accent.opacity(0.6) : .primary.opacity(0.10), lineWidth: 0.5))
        .onHover { hovered = $0 }
        .help("\(record.label)\n\(record.appName)")
        .contextMenu {
            Button("切换到此窗口", action: onFocus)
            ForEach(WindowControlAction.allCases, id: \.self) { action in
                Button(action.title(minimized: record.minimized, fullScreen: record.fullScreen)) { onPerform(action) }
                    .disabled(!record.controls.supports(action) || store.pendingControls.contains(record.id))
            }
        }
    }
}
