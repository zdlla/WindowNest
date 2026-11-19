import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook

private typealias FilePageState<Value> = SwiftUI.State<Value>

/// A dedicated search workspace, distinct from both the launcher and window cards.
struct FileSearchPage: View {
    @Environment(\.workspaceAccent) private var accent
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var files: FileSearchStore
    @ObservedObject var workspace: WindowStore
    @FocusState private var searchFocused: Bool
    @FocusState private var resultsFocused: Bool
    @FilePageState private var help = false

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            filters
            Divider().padding(.horizontal, WorkspaceStyle.gutter)
            content
            footer
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WorkspaceStyle.canvas)
        .quickLookPreview($files.previewURL)
        .onChange(of: files.selection) { _, selection in
            if !selection.isEmpty { searchFocused = false; resultsFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WindowNest.FocusFileSearch"))) { _ in
            guard workspace.mode == .files else { return }; searchFocused = true
        }
        .onExitCommand {
            if files.previewURL != nil { files.previewURL = nil }
            else if !files.query.isEmpty { files.query = ""; searchFocused = true }
            else { dismiss() }
        }
        .alert("文件搜索", isPresented: Binding(get: { files.message != nil }, set: { if !$0 { files.message = nil } })) {
            Button("好") { files.message = nil }
        } message: { Text(files.message ?? "") }
        .onAppear { searchFocused=true }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            WorkspaceHeading(title: "文件搜索", subtitle: "按名称、路径或条件，查找本机文件。")
            Spacer()
            Menu {
                Button("整个 Mac") { files.changeRoot("/") }
                Button("个人目录") { files.changeRoot(FileManager.default.homeDirectoryForCurrentUser.path) }
                Button("选择文件夹…") { files.chooseFolder() }
                Divider()
                Toggle("显示隐藏项目", isOn: Binding(get: { files.settings.showHidden }, set: { _ in files.toggleHidden() }))
                Button("重新建立当前范围索引") { files.start(rebuild: true) }
                Button("查看文件访问权限…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
            } label: {
                Label(files.rootName, systemImage: "internaldrive").font(.system(size: 12, weight: .medium))
            }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 14).frame(height: 36)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
                .help("索引范围：\(files.settings.root)").accessibilityLabel("文件搜索范围：\(files.rootName)")
            LibraryIconButton(symbol: "questionmark", title: "搜索语法帮助") { help.toggle() }
                .popover(isPresented: $help) { searchHelp }
        }.padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 28).padding(.bottom, 24)
    }
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(WorkspaceStyle.secondary)
            TextField("搜索文件名、路径，或输入 ext:pdf 等条件", text: $files.query)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($searchFocused)
                .accessibilityLabel("搜索全部文件")
                .onSubmit { files.open() }
                .onKeyPress(.downArrow) {
                    guard let first = files.rows.first else { return .ignored }
                    files.selection = [first.id]; searchFocused = false; resultsFocused = true; return .handled
                }
            if files.searching { ProgressView().controlSize(.small).frame(width: 20) }
            if !files.query.isEmpty {
                Button { files.query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(WorkspaceStyle.secondary)
                }.buttonStyle(.plain).accessibilityLabel("清除文件搜索")
            } else { Text("⌘F").font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceStyle.secondary) }
        }.padding(.horizontal, 16).frame(height: 48)
            .workspaceSearchSurface(focused: searchFocused)
            .padding(.horizontal, WorkspaceStyle.gutter)
    }
    private var filters: some View {
        HStack(spacing: 7) {
            ForEach(FileSearchKind.allCases) { kind in
                Button { files.kind = kind } label: {
                    Label(kind.rawValue, systemImage: kind.symbol)
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 32)
                        .foregroundStyle(files.kind == kind ? accent : WorkspaceStyle.secondary)
                        .background(files.kind == kind ? accent.opacity(0.12) : Color.primary.opacity(0.035), in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("筛选\(kind.rawValue)")
                    .accessibilityAddTraits(files.kind == kind ? .isSelected : [])
            }
            Spacer(minLength: 2)
            if files.ready && files.hasSearch && !files.searching {
                Text("\(files.total.formatted()) 个结果").font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
            }
        }.padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 15).padding(.bottom, 17)
    }
    @ViewBuilder private var content: some View {
        if !files.ready && files.failure == nil {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(files.status).font(.system(size: 15, weight: .medium))
                Text("首次索引需要一点时间；后续打开会读取本机缓存。\n你可以先输入搜索条件，索引完成后会自动显示结果。")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = files.failure {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.magnifyingglass").font(.system(size: 34)).foregroundStyle(WorkspaceStyle.secondary)
                Text(error).font(.system(size: 13)).multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 560)
                if !files.ready { Button("重新连接") { files.start() }.libraryButton(prominent: true) }
                else { Button("查看搜索语法") { help = true }.libraryButton() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        } else if !files.hasSearch {
            landing
        } else if files.rows.isEmpty {
            VStack(spacing: 14) {
                if files.searching { ProgressView() }
                else {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40, weight: .light)).foregroundStyle(WorkspaceStyle.secondary)
                    Text("没有找到匹配的文件").font(.system(size: 17, weight: .semibold))
                    Text("试试更短的名称，或调整类型、隐藏项目与搜索范围。")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { results }
    }
    private var landing: some View {
        VStack(spacing: 17) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36, weight: .light)).foregroundStyle(WorkspaceStyle.secondary)
            Text("所有文件，一个入口").font(.system(size: 20, weight: .semibold))
            Text("按名称和路径搜索，也可以组合筛选条件。")
                .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
            HStack(spacing: 10) {
                suggestion("PDF 文档", symbol: "doc.richtext", query: "ext:pdf")
                suggestion("表格", symbol: "tablecells", query: "ext:xlsx;xls;numbers;csv")
                suggestion("图片", symbol: "photo", query: "ext:png;jpg;jpeg;heic")
            }.padding(.top, 7)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func suggestion(_ title: String, symbol: String, query: String) -> some View {
        Button { files.kind = .all; files.query = query; searchFocused = true } label: {
            Label(title, systemImage: symbol)
        }.libraryButton()
    }
    private var results: some View {
        VStack(spacing: 0) {
            Table(files.rows, selection: $files.selection) {
                TableColumn("名称") { file in
                    HStack(spacing: 9) {
                        Image(nsImage: icon(file)).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(file.parent).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1).truncationMode(.middle)
                        }.padding(.vertical, 6)
                    }.help(file.path)
                }.width(min: 340, ideal: 550)
                TableColumn("类型") { file in Text(file.kind).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary) }.width(70)
                TableColumn("大小") { file in
                    Text(file.directory ? "—" : file.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                }.width(80)
                TableColumn("修改时间") { file in
                    if let value = file.modified { Text(Date(timeIntervalSince1970: value), format: .dateTime.year().month().day()).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary) }
                    else { Text("—").foregroundStyle(WorkspaceStyle.secondary) }
                }.width(110)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .focused($resultsFocused)
            .contextMenu(forSelectionType: String.self) { paths in
                if let file = files.rows.first(where: { paths.contains($0.id) }) {
                    Button("打开") { files.open(file) }
                    Button("快速预览") { files.preview(file) }
                    Button("在访达中显示") { files.reveal(file) }
                    Divider()
                    Button("复制路径") { files.copyPath(file) }
                }
            } primaryAction: { paths in
                if let file = files.rows.first(where: { paths.contains($0.id) }) { files.open(file) }
            }
            .onKeyPress(.space) { guard files.selectedFile != nil else { return .ignored }; files.preview(); return .handled }
            .onKeyPress(.return) { guard files.selectedFile != nil else { return .ignored }; files.open(); return .handled }
            .opacity(files.searching ? 0.65 : 1)
            if let selected = files.selectedFile {
                HStack(spacing: 9) {
                    Text(selected.path).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("快速预览") { files.preview() }.buttonStyle(.borderless).font(.system(size: 11))
                    Button("在访达中显示") { files.reveal() }.buttonStyle(.borderless).font(.system(size: 11))
                }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
            }
        }.padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 8)
    }
    private func icon(_ file: IndexedFile) -> NSImage {
        FileTypeIcons.shared.image(for:file.url,directory:file.directory)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                Circle().fill(files.ready ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(files.status).lineLimit(1)
                if files.hasSearch && files.total > files.rows.count { Text("· 显示前 \(files.rows.count) 个，请缩小条件") }
                Spacer(minLength: 6)
                if let ms = files.milliseconds, files.hasSearch { Text("\(ms, specifier: "%.0f") ms").monospacedDigit() }
                Text("Cardinal").fontWeight(.medium)
            }.font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 11)
            HStack {
                Text(files.warning ?? "无需完全磁盘访问即可使用；搜索受保护目录时才需另行授权。")
                Spacer()
                Text("名称与索引保存在本机")
            }.font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, WorkspaceStyle.gutter).padding(.top, 5).padding(.bottom, 11)
        }
    }
    private var searchHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("搜索语法").font(.system(size: 17, weight: .semibold))
            Text("默认按名称与路径搜索，空格表示同时满足。").font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
            ForEach([("项目 报告", "名称同时包含两个词"), ("ext:pdf;docx", "只找 PDF 和 Word 文档"), ("folder: 资料", "查找资料文件夹"), ("size:>100MB", "查找较大的文件"), ("content:\"关键字\" ext:txt", "按需读取文本文件内容")], id: \.0) { example in
                HStack { Text(example.0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(width: 215, alignment: .leading); Text(example.1).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary) }
            }
            Text("索引首次建立后会缓存；文件变化由 Cardinal 实时跟踪。内容条件可能需要更长时间。")
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).frame(maxWidth: 430, alignment: .leading)
            Text("普通搜索不要求完全磁盘访问。只有需要受保护目录时才考虑授权；授权后，内置搜索引擎也可能获得相同访问范围。")
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary).frame(maxWidth: 430, alignment: .leading)
            Link("Cardinal 开源项目 · MIT", destination: URL(string: "https://github.com/cardisoft/cardinal")!).font(.system(size: 11))
        }.padding(24)
    }
}
