import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Disambiguate the property wrapper from the macOS 27 State macro.
typealias LocalState<Value> = SwiftUI.State<Value>

func sidebarLabel(_ name: String, symbol: String, count: Int) -> some View {
    HStack(spacing: 9) {
        Image(systemName: symbol).foregroundStyle(.tint).frame(width: 19)
        Text(name).lineLimit(1)
        Spacer(minLength: 4)
        Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
    }.padding(.vertical, 4)
}

struct ApplicationActions: View {
    @ObservedObject var library: AppLibraryStore
    let app: SavedApplication
    var pinned = false
    var body: some View {
        Button("打开") { library.launch(app) }
        Button(library.isPinned(app) ? "取消固定到常用应用" : "固定到常用应用") {
            if library.isPinned(app) { library.unpin(app) } else { library.pin(app) }
        }
        Divider()
        Button("向前移动") { library.reorderApp(app, offset: -1, pinned: pinned) }
            .disabled(!library.canMove(app, offset: -1, pinned: pinned))
        Button("向后移动") { library.reorderApp(app, offset: 1, pinned: pinned) }
            .disabled(!library.canMove(app, offset: 1, pinned: pinned))
        if !pinned {
            Menu("移到分类") {
                Button("未分类") { library.move(app.id, to: nil) }
                Divider()
                ForEach(library.library.categories) { category in
                    Button { library.move(app.id, to: category.id) } label: {
                        Label(category.name, systemImage: app.categoryID == category.id ? "checkmark" : category.symbol)
                    }
                }
            }
        }
        Button("在访达中显示") { library.reveal(app) }
        Divider()
        Button("从收纳中移除") { library.remove(app) }
    }
}

struct ApplicationTile: View {
    @Environment(\.workspaceAccent) private var accent
    @ObservedObject var library: AppLibraryStore
    let app: SavedApplication
    var pinned = false
    @LocalState private var hovered = false
    @LocalState private var dropTargeted = false
    private var running: Bool { app.bundleID.map { library.runningBundleIDs.contains($0) } ?? false }
    var body: some View {
        Button { library.launch(app) } label: {
            VStack(alignment: .center, spacing: pinned ? 6 : 8) {
                Image(nsImage: library.icon(app.path)).resizable().interpolation(.high).frame(width: 80, height: 80)
                    .opacity(library.available(app) ? 1 : 0.4)
                    .nativeIconFeedback(hovered: hovered)
                VStack(spacing: pinned ? 6 : 3) {
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .truncationMode(.tail).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center).frame(height: 17)
                    if !pinned {
                        HStack(spacing: 4) {
                            if running { Circle().frame(width: 4, height: 4).accessibilityLabel("正在运行") }
                            Text(library.available(app) ? library.categoryName(app.categoryID) : "找不到应用")
                                .font(.system(size: 11)).lineLimit(1)
                        }.foregroundStyle(.secondary)
                    } else { Circle().fill(running ? Color.secondary : .clear).frame(width: 4, height: 4) }
                }
            }.padding(.vertical, 8).padding(.horizontal, pinned ? 0 : 7).frame(maxWidth: .infinity, alignment: .center)
                .background(hovered ? accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(dropTargeted ? 0.8 : 0), lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(NativePressStyle()).onHover { hovered = $0 }
            .help("打开 \(app.name)\n拖到其他图标前调整顺序；右键可固定或整理")
            .accessibilityLabel("打开 \(app.name)，\(pinned ? "常用应用" : library.categoryName(app.categoryID))\(running ? "，正在运行" : "")")
            .onDrag { NSItemProvider(object: "windownest-app:\(app.id.uuidString)" as NSString) }
            .onDrop(of: [.fileURL, .text], isTargeted: $dropTargeted) {
                library.acceptDrop($0, category: app.categoryID, pin: pinned, before: app.id)
            }
            .contextMenu { ApplicationActions(library: library, app: app, pinned: pinned) }
    }
}

struct AddApplicationsSheet: View {
    @FocusState private var pickerSearchFocused: Bool
    @ObservedObject var library: AppLibraryStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(library.pickerPins ? "固定常用应用" : "添加应用").font(.system(size: 21, weight: .semibold))
                    Text(library.pickerPins ? "选择应用，固定在文件夹上方的一行。" : "选择应用图标，再放入一个分类。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                LibraryIconButton(symbol: "xmark", title: "关闭添加应用") { library.showAddApplications = false }
            }.padding(24)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索已安装应用", text: $library.pickerQuery).textFieldStyle(.plain).focused($pickerSearchFocused).accessibilityLabel("搜索已安装应用")
                if !library.pickerQuery.isEmpty { Button { library.pickerQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(.horizontal, 14).frame(height: 38).workspaceSearchSurface(focused: pickerSearchFocused).padding(.horizontal, 24).padding(.bottom, 16)
            if library.catalogLoading {
                VStack(spacing: 12) { ProgressView(); Text("正在读取应用列表…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.filteredCatalog.isEmpty {
                VStack(spacing: 12) {
                    Text("没有找到应用").fontWeight(.semibold)
                    Text("可以清除搜索，或从访达中选择 .app。").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(library.filteredCatalog) { app in
                    Toggle(isOn: Binding(get: { library.pickerSelection.contains(app.path) }, set: { selected in
                        if selected { library.pickerSelection.insert(app.path) } else { library.pickerSelection.remove(app.path) }
                    })) {
                        HStack(spacing: 11) {
                            Image(nsImage: library.icon(app.path)).resizable().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.system(size: 13, weight: .medium))
                                Text(app.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if library.library.applications.contains(where: { $0.path == app.path }) {
                                Text("已收纳").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }.toggleStyle(.checkbox).padding(.vertical, 3)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                if library.pickerPins { Label("常用应用栏", systemImage: "pin.fill").font(.system(size: 12)).foregroundStyle(.secondary) }
                else { Picker("放入", selection: $library.pickerCategory) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(library.library.categories) { category in Text(category.name).tag(Optional(category.id)) }
                }.frame(width: 190) }
                Spacer()
                Button("选择 .app…") { library.chooseFiles(category: library.pickerCategory, pin: library.pickerPins) }.libraryButton()
                Button("\(library.pickerPins ? "固定" : "添加") \(library.pickerSelection.count) 个应用") { library.addPickerSelection() }
                    .libraryButton(prominent: true).disabled(library.pickerSelection.isEmpty).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 600, height: 560)
    }
}
