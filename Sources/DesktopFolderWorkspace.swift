import SwiftUI

private typealias FolderWorkspaceState<Value> = SwiftUI.State<Value>

struct DesktopFolderWorkspace:View {
    @ObservedObject var boxes:DesktopFileBoxController
    @ObservedObject var files:FileSearchStore
    @ObservedObject var workspace:WindowStore
    let onSearchVisibility:(Bool)->Void
    let onReveal:()->Void
    @FolderWorkspaceState private var searchPresented=false
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                WorkspaceHeading(title:"桌面文件夹",subtitle:"打开文件、呼出文件盒，或调整它的布局与外观。")
                Spacer()
                Button { searchPresented=true } label:{Label("全局查找",systemImage:"magnifyingglass")}.libraryButton()
                Button { boxes.create() } label:{Label("新建文件盒",systemImage:"plus")}.libraryButton(prominent:true)
            }.padding(.horizontal,28).padding(.vertical,22)
            Divider()
            if boxes.models.isEmpty {
                VStack(spacing:14) {
                    Image(systemName:"square.stack.3d.up").font(.system(size:38)).foregroundStyle(.secondary)
                    Text("把常用文件夹带到桌面").font(.system(size:20,weight:.semibold))
                    Button("创建第一个文件盒") { boxes.create() }.libraryButton(prominent:true)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                HStack(spacing:0) {
                    ScrollView {
                        VStack(alignment:.leading,spacing:5) {
                            Text("我的文件盒").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.bottom,5)
                            ForEach(Array(boxes.models.enumerated()),id:\.element.configuration.id) { index,model in
                                Button { boxes.selectWorkspace(model) } label:{
                                    Label(model.folder?.name ?? "文件盒 \(index+1)",systemImage:model.locked ? "pin.fill" : "folder")
                                        .font(.system(size:13)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(10)
                                        .background(Color.accentColor.opacity(boxes.workspaceModel === model ? 0.12 : 0),in:RoundedRectangle(cornerRadius:9))
                                }.buttonStyle(NativePressStyle()).nativeHoverFeedback(in:RoundedRectangle(cornerRadius:9))
                            }
                        }.padding(14)
                    }.frame(width:200)
                    Divider()
                    if let model=boxes.workspaceModel {
                        VStack(spacing:10) {
                            HStack {
                                Text("文件盒内容与设置").font(.system(size:13,weight:.semibold))
                                Spacer()
                                Button("在桌面呼出") { boxes.show(model);onReveal() }.libraryButton()
                            }
                            boxes.embeddedView(model).id(model.configuration.id)
                        }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                }
            }
        }.background(WorkspaceStyle.canvas)
        .sheet(isPresented:$searchPresented) {
            VStack(spacing:0) {
                HStack { Text("全局查找").font(.headline);Spacer();Button("完成") { searchPresented=false } }.padding(12)
                FileSearchPage(files:files,workspace:workspace)
            }.frame(width:960,height:680)
        }
        .onChange(of:searchPresented) { _,visible in onSearchVisibility(visible) }
        .onDisappear { searchPresented=false;onSearchVisibility(false) }
        .onChange(of:workspace.mode) { _,mode in
            if mode != .files { searchPresented=false;onSearchVisibility(false) }
        }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("WindowNest.FocusFileSearch"))) { _ in
            if workspace.mode == .files { searchPresented=true }
        }
    }
}
