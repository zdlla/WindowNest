import SwiftUI

struct QuickFolderShortcuts: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var store: QuickFolderStore
    let width: CGFloat
    let onAdd: () -> Void
    let onOpen: (QuickFolder) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if !store.folders.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(Array(store.folders.enumerated()), id: \.element.id) { index, folder in
                            Button { onOpen(folder) } label: {
                                Label(folder.name, systemImage: "folder.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(width: 104, height: 28).padding(.horizontal, 8)
                                    .background(accent.opacity(0.08), in: Capsule())
                                    .overlay(Capsule().strokeBorder(accent.opacity(0.20), lineWidth: 0.5))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(NativePressStyle()).nativeHoverFeedback(in: Capsule())
                            .help(folder.path).accessibilityLabel("用访达打开\(folder.name)")
                            .accessibilityIdentifier("WindowNest.QuickFolder.\(folder.id)")
                            .contextMenu {
                                Button("用访达打开") { onOpen(folder) }
                                Divider()
                                Button("向前移") { store.move(folder.id, by: -1) }.disabled(index == 0)
                                Button("向后移") { store.move(folder.id, by: 1) }.disabled(index == store.folders.count - 1)
                                Divider()
                                Button("取消固定") { store.remove(folder.id) }
                            }
                        }
                    }.padding(.horizontal, 1)
                }
                .scrollIndicators(.never)
                .frame(width: min(width, CGFloat(store.folders.count) * 125), height: 28)
                .accessibilityLabel("固定文件夹")
            }
            Button(action: onAdd) {
                Group {
                    if store.folders.isEmpty { Label("固定文件夹", systemImage: "folder.badge.plus").padding(.horizontal, 9) }
                    else { Image(systemName: "folder.badge.plus").frame(width: 28) }
                }
                .font(.system(size: 11, weight: .medium)).frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(NativePressStyle()).nativeHoverFeedback(in: Capsule())
            .help("固定访达文件夹").accessibilityLabel("固定访达文件夹")
            .accessibilityIdentifier("WindowNest.AddQuickFolder")
        }.fixedSize(horizontal: true, vertical: true)
    }
}

struct QuickFolderSettings: View {
    @ObservedObject var store: QuickFolderStore
    var body: some View {
        Section {
            if store.folders.isEmpty {
                Text("尚未固定文件夹").foregroundStyle(WorkspaceStyle.secondary)
            }
            ForEach(Array(store.folders.enumerated()), id: \.element.id) { index, folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name).lineLimit(1)
                        Text(folder.path).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    Button { store.move(folder.id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0).help("向前移").accessibilityLabel("将\(folder.name)向前移")
                    Button { store.move(folder.id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == store.folders.count - 1).help("向后移").accessibilityLabel("将\(folder.name)向后移")
                    Button { store.remove(folder.id) } label: { Image(systemName: "minus.circle") }
                        .help("取消固定").accessibilityLabel("取消固定\(folder.name)")
                }
            }
            Button("添加文件夹…") { store.chooseFolders() }.libraryButton()
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        } header: { Text("速览固定文件夹") } footer: {
            Text("显示在顶部速览的右侧，点击用访达打开。取消固定只移除入口，不删除文件夹。")
        }
    }
}
