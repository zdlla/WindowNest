import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum LibraryCorners {
    static let folder: CGFloat = 28
    static let panel: CGFloat = 16
}

struct AppFolder: Identifiable {
    let id: LibraryScope
    let name: String
    let symbol: String
    let applications: [SavedApplication]
    var count: Int { applications.count }
    var preview: AppFolderPreview { AppFolderPreview(applications: applications) }
}

private struct FolderDirectAppButton: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var library: AppLibraryStore
    let app: SavedApplication
    let size: CGFloat
    @LocalState private var hovered = false
    @LocalState private var targeted = false
    var body: some View {
        Button { library.launch(app) } label: {
            Image(nsImage: library.icon(app.path)).resizable().interpolation(.high)
                .frame(width: size, height: size).opacity(library.available(app) ? 1 : 0.4)
                .nativeIconFeedback(hovered: hovered)
                .background(hovered ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(accent.opacity(targeted ? 0.8 : 0), lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 19))
        }.buttonStyle(NativePressStyle()).onHover { hovered = $0 }
            .help("直接打开 \(app.name)；拖放可调整顺序")
            .accessibilityLabel("直接打开 \(app.name)")
            .onDrag { NSItemProvider(object: "windownest-app:\(app.id.uuidString)" as NSString) }
            .onDrop(of: [.fileURL, .text], isTargeted: $targeted) {
                library.acceptDrop($0, category: app.categoryID, before: app.id)
            }
            .contextMenu { ApplicationActions(library: library, app: app) }
    }
}

/// First three positions launch apps; the fourth is always the only expansion target.
struct FolderPreviewGrid: View {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var stackHovered = false
    private var fan: Bool { stackHovered && !reduceMotion && preferences.settings.effects != .minimal }
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var library: AppLibraryStore
    let folder: AppFolder
    let size: CGFloat
    let open: () -> Void
    private var preview: AppFolderPreview { folder.preview }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) { directSlot(0); directSlot(1) }
            HStack(spacing: 12) {
                directSlot(2)
                Button(action: open) {
                    stack.frame(width: size, height: size).nativeIconFeedback(hovered: stackHovered)
                        .contentShape(RoundedRectangle(cornerRadius: 19))
                }
                    .buttonStyle(NativePressStyle()).onHover { stackHovered = $0 }
                    .accessibilityLabel("展开文件夹 \(folder.name)，\(folder.count) 个应用")
                    .help("展开 \(folder.name)，查看和排列全部 \(folder.count) 个应用")
            }
        }.frame(width: size * 2 + 12, height: size * 2 + 12)
    }
    @ViewBuilder private func directSlot(_ index: Int) -> some View {
        if index < preview.direct.count { FolderDirectAppButton(library: library, app: preview.direct[index], size: size) }
        else {
            RoundedRectangle(cornerRadius: 18).fill(.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.025)))
                .frame(width: size * 0.86, height: size * 0.86).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
    private var stack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.07))
                .frame(width: size * 0.75, height: size * 0.75).rotationEffect(.degrees(-11)).offset(x: -5, y: 4)
            RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.08))
                .frame(width: size * 0.78, height: size * 0.78).rotationEffect(.degrees(9)).offset(x: 5, y: -4)
            ForEach(Array(preview.stacked.enumerated().reversed()), id: \.element.id) { index, app in
                Image(nsImage: library.icon(app.path)).resizable().interpolation(.high)
                    .frame(width: size * 0.87, height: size * 0.87)
                    .rotationEffect(.degrees(index == 0 ? 0 : index == 1 ? (fan ? -13 : -10) : (fan ? 12 : 9)))
                    .offset(x: index == 0 ? 0 : index == 1 ? (fan ? -8 : -5) : (fan ? 8 : 5),
                        y: index == 0 ? 0 : index == 1 ? (fan ? 5 : 3) : (fan ? -6 : -4))
            }
            if preview.stacked.isEmpty {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 29, weight: .regular)).foregroundStyle(accent)
            }
            Image(systemName: "square.stack.fill").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WorkspaceStyle.surface).padding(5).background(accent, in: Circle())
                .offset(x: size * 0.33, y: size * 0.34)
        }.animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.94), value: fan)
            .accessibilityHidden(true)
    }
}

/// Content covers stay quiet; translucent material is reserved for the overlay.
struct FolderSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = LibraryCorners.folder
    var panelBorder = false
    var body: some View {
        Group {
            if panelBorder && !reduceTransparency && preferences.settings.effects != .minimal {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(WorkspaceStyle.surface.opacity(colorScheme == .dark ? 0.12 : 0.40)))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(WorkspaceStyle.surface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5))
        .shadow(color: .black.opacity(panelBorder ? 0.10 : 0), radius: panelBorder ? 20 : 0, y: 6)
    }
}

struct AppFolderTile: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var library: AppLibraryStore
    let folder: AppFolder
    let side: CGFloat
    let iconSize: CGFloat
    let open: () -> Void
    @LocalState private var hovered = false
    @LocalState private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                FolderSurface()
                FolderPreviewGrid(library: library, folder: folder, size: iconSize, open: open)
            }.frame(width: side, height: side)
                .overlay(RoundedRectangle(cornerRadius: LibraryCorners.folder).strokeBorder(accent.opacity(dropTargeted ? 0.8 : hovered ? 0.22 : 0), lineWidth: 2).allowsHitTesting(false))
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text("\(folder.count) 个应用").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: side, alignment: .leading)
            .onHover { hovered = $0 }
            .accessibilityElement(children: .contain)
            .onDrop(of: [.fileURL, .text], isTargeted: $dropTargeted) { library.acceptDrop($0, category: folder.id.categoryID) }
            .contextMenu {
                Button("展开文件夹", action: open)
                Button("添加应用…") { library.scope = folder.id; library.beginAdding() }
                if let id = folder.id.categoryID, let category = library.library.categories.first(where: { $0.id == id }) {
                    Divider()
                    Button("重命名…") { library.categoryDialog(editing: category) }
                    Button("向前移动") { library.reorder(category, offset: -1) }.disabled(library.library.categories.first?.id == id)
                    Button("向后移动") { library.reorder(category, offset: 1) }.disabled(library.library.categories.last?.id == id)
                    Divider()
                    Button("移除分类，保留应用") { library.deleteCategory(category) }
                }
            }
    }
}

struct ExpandedFolderPanel: View {
    @ObservedObject var library: AppLibraryStore
    let scope: LibraryScope
    let visible: Bool
    let motion: FolderMotionPlan
    let close: () -> Void
    private var apps: [SavedApplication] { library.library.applications(in: scope) }
    private var title: String { library.categoryName(scope.categoryID) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 28, weight: .semibold))
                    Text("\(apps.count) 个应用").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                }
                Spacer()
                Menu {
                    Text("拖动应用到其他图标前调整顺序")
                    Button("按名称排序") { library.sortFolder() }
                } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .medium)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().libraryIconSurface()
                    .accessibilityLabel("排列文件夹应用").protectsFolderClick()
                LibraryIconButton(symbol: "plus", title: "添加到此文件夹") { library.beginAdding() }.protectsFolderClick()
                LibraryIconButton(symbol: "xmark", title: "关闭文件夹（Esc）", action: close).protectsFolderClick()
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            if apps.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 35, weight: .light)).foregroundStyle(WorkspaceStyle.secondary)
                    Text("这个文件夹还没有应用").font(.system(size: 17, weight: .medium))
                    Button("添加应用") { library.beginAdding() }.libraryButton(prominent: true).protectsFolderClick()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 155), spacing: 14)], spacing: 10) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            ApplicationTile(library: library, app: app)
                                .transaction { $0.animation = nil }
                                .scaleEffect(visible ? 1 : motion.itemScale)
                                .opacity(visible ? 1 : 0)
                                .animation(motion.simple ? .easeOut(duration: 0.10) : .smooth(duration: visible ? 0.28 : 0.16)
                                    .delay(motion.itemDelay(index: index, count: apps.count, entering: visible)), value: visible)
                                .protectsFolderClick()
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 25)
                }
            }
            Text("点击空白收起 · 拖放排序 · 右键固定").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspacePanelSurface(radius: LibraryCorners.panel)
        .overlayPreferenceValue(FolderProtectedBounds.self) { anchors in
            GeometryReader { geometry in
                FolderBlankClickRegion(protected: anchors.map { geometry[$0] }, enabled: visible && !library.showAddApplications, close: close)
            }.allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL, .text], isTargeted: nil) { library.acceptDrop($0, category: scope.categoryID) }
        .accessibilityElement(children: .contain)
    }
}
