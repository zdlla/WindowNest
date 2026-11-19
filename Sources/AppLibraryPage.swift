import SwiftUI
import AppKit

private struct HorizontalLibraryScrollRegion: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> PageGestureExclusion { PageGestureExclusion() }
    func updateNSView(_ view: PageGestureExclusion, context: Context) { view.enabled = enabled }
}

/// An independent launcher page: no NavigationSplitView and no window-browser sidebar.
struct AppLibraryPage: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var store: WindowStore
    @ObservedObject var library: AppLibraryStore
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var preferences: AppearanceStore
    @StateObject private var presentation = FolderPresentation()
    @FocusState private var searchFocused: Bool

    private var expanded: Bool { presentation.scope != nil }
    private var motion: FolderMotionPlan { FolderMotionPlan(reduced: reducedMotion, effects: preferences.settings.effects) }
    private var folders: [AppFolder] {
        library.library.categories.map { category in
            let scope = LibraryScope.category(category.id)
            return AppFolder(id: scope, name: category.name, symbol: category.symbol,
                applications: library.library.applications(in: scope))
        } + [AppFolder(id: .uncategorized, name: "未分类", symbol: "tray", applications: library.library.applications(in: .uncategorized))]
    }
    private var searchResults: [SavedApplication] {
        library.library.applications(in: .all).filter {
            WindowNaming.matches(query: library.query, fields: [$0.name, library.categoryName($0.categoryID), $0.path])
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                canvas(width: geometry.size.width)
                    .blur(radius: presentation.visible && !motion.simple ? (preferences.settings.effects == .clearGlass ? 3 : preferences.settings.effects.usesGlass ? 10 : 5) : 0)
                    .animation(.easeInOut(duration: motion.simple ? 0.12 : 0.28), value: presentation.visible)
                    .allowsHitTesting(!expanded).accessibilityHidden(expanded)
                if let scope = presentation.scope {
                    Color.black.opacity(presentation.visible ? (colorScheme == .dark ? 0.24 : 0.12) : 0).ignoresSafeArea()
                        .animation(.easeInOut(duration: motion.simple ? 0.12 : 0.28), value: presentation.visible)
                        .contentShape(Rectangle()).onTapGesture { closeFolder() }
                    ExpandedFolderPanel(library: library, scope: scope, visible: presentation.visible,
                        motion: motion, close: closeFolder)
                        .frame(width: min(720, geometry.size.width - 70), height: min(560, geometry.size.height - 50))
                        .scaleEffect(presentation.visible ? 1 : motion.panelScale)
                        .opacity(presentation.visible ? 1 : 0)
                        .animation(motion.simple ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 1)
                            .delay(presentation.visible ? 0 : 0.10), value: presentation.visible)
                        .allowsHitTesting(presentation.visible)
                        .id(scope).zIndex(2)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: library.scope) { _, scope in
            if scope == .all { presentation.dismiss(after: motion.removalDelay) }
            else { presentation.show(scope) }
        }
        .onAppear { if library.scope != .all { presentation.show(library.scope) } }
        .onDisappear { presentation.reset() }
        .sheet(isPresented: $library.showAddApplications) { AddApplicationsSheet(library: library) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WindowNest.FocusSearch"))) { _ in
            guard store.mode == .applications else { return }
            if expanded { closeFolder() }
            searchFocused = true
        }
        .onExitCommand {
            if expanded { closeFolder() }
            else if !library.query.isEmpty { library.query = "" }
            else { NSApp.keyWindow?.close() }
        }
        .alert("窗匣", isPresented: Binding(get: { library.message != nil || store.message != nil }, set: { if !$0 { library.message = nil; store.message = nil } })) {
            Button("好") { library.message = nil; store.message = nil }
        } message: { Text(library.message ?? store.message ?? "") }
    }

    private var background: some View {
        ZStack {
            WorkspaceStyle.canvas
            if preferences.settings.effects.usesGlass && colorScheme == .dark {
                LinearGradient(colors: [accent.opacity(0.065), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea()
    }

    private func canvas(width: CGFloat) -> some View {
        let layout = FolderGridLayout(width: width)
        return ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceStyle.sectionGap) {
                HStack(alignment: .center, spacing: 24) {
                    WorkspaceHeading(title: "应用资源库", subtitle: "\(library.library.applications.count) 个应用 · \(library.library.categories.count) 个分类")
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(WorkspaceStyle.secondary)
                        TextField("搜索应用或分类", text: $library.query).textFieldStyle(.plain)
                            .focused($searchFocused).accessibilityLabel("搜索应用资源库")
                        if !library.query.isEmpty {
                            Button { library.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(WorkspaceStyle.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("清除应用搜索")
                        } else { Text("⌘F").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary) }
                    }.font(.system(size: 13)).padding(.horizontal, 14).frame(width: 292, height: 40)
                        .workspaceSearchSurface(focused: searchFocused)
                }
                if library.query.isEmpty {
                    pinnedSection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("应用分类").font(WorkspaceStyle.section)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: WorkspaceStyle.gap, alignment: .leading), count: layout.columns), alignment: .leading, spacing: 28) {
                            ForEach(folders) { folder in
                                AppFolderTile(library: library, folder: folder,
                                    side: layout.side, iconSize: layout.icon) { openFolder(folder.id) }
                            }
                        }
                    }
                } else if searchResults.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(WorkspaceStyle.secondary)
                        Text("没有找到匹配的应用").font(.system(size: 18, weight: .medium))
                        Text("试试应用名，或清除搜索。").font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("搜索结果 · \(searchResults.count)").font(WorkspaceStyle.section)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 155), spacing: 24)], spacing: 20) {
                            ForEach(searchResults) { app in ApplicationTile(library: library, app: app) }
                        }
                    }
                }
            }.padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 28).padding(.bottom, 32)
        }
    }
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("常用应用").font(WorkspaceStyle.section)
                Spacer()
                Button { library.beginPinning() } label: { Label("固定应用", systemImage: "plus").font(.system(size: 13, weight: .medium)) }
                    .libraryButton().foregroundStyle(accent).accessibilityLabel("添加常用应用")
            }
            if library.library.pinnedApplications.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "pin").font(.system(size: 18)).frame(width: 24)
                    Text("右键应用选择“固定到常用应用”，或拖入应用图标。")
                        .font(.system(size: 13))
                    Spacer()
                }.foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 16).frame(height: 56)
                    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(library.library.pinnedApplications) { app in
                            ApplicationTile(library: library, app: app, pinned: true).frame(width: 96)
                        }
                    }
                }.frame(height: 126)
                    .background {
                        GeometryReader { geometry in
                            HorizontalLibraryScrollRegion(enabled: CGFloat(library.library.pinnedApplications.count) * 120 - 24 > geometry.size.width)
                        }
                    }
            }
        }.onDrop(of: [.fileURL, .text], isTargeted: nil) { library.acceptDrop($0, category: nil, pin: true) }
    }
    private func openFolder(_ scope: LibraryScope) {
        searchFocused = false
        library.scope = scope
    }
    private func closeFolder() { library.scope = .all }
}
