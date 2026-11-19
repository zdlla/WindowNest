import AppKit
import Combine
import ServiceManagement
import SwiftUI
import Carbon

enum WorkspaceLaunchContext {
    static func isLogin(_ event:NSAppleEventDescriptor?)->Bool {
        guard let event,event.eventClass == AEEventClass(kCoreEventClass),event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword:AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
            || event.paramDescriptor(forKeyword:AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true
    }
}

@MainActor protocol LoginItemService {
    var status:SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
@MainActor private struct SystemLoginItemService:LoginItemService {
    var status:SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
@MainActor final class LoginItemController:ObservableObject {
    @Published private(set) var status:SMAppService.Status = .notRegistered
    @Published private(set) var changing=false
    @Published var error:String?
    private let service:LoginItemService
    init(service:LoginItemService? = nil) { self.service=service ?? SystemLoginItemService();refresh() }
    var enabled:Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status=service.status }
    func setEnabled(_ enabled:Bool) {
        guard !changing else { return };changing=true;defer { changing=false;refresh() }
        error=nil
        do {
            if enabled { if service.status != .enabled && service.status != .requiresApproval { try service.register() } }
            else if service.status != .notRegistered { try service.unregister() }
        } catch { self.error="无法更新登录启动设置：\(error.localizedDescription)" }
    }
}
struct LoginItemSettings:View {
    @ObservedObject var controller:LoginItemController
    var body:some View {
        Section {
            Toggle("登录 Mac 时启动窗匣",isOn:Binding(get:{controller.enabled},set:{controller.setEnabled($0)})).disabled(controller.changing)
            if controller.status == .requiresApproval {
                Text("已登记，需在系统登录项中允许。").font(.system(size:12)).foregroundStyle(.secondary)
                Button("打开系统登录项…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error=controller.error { Text(error).font(.system(size:12)).foregroundStyle(.red) }
        } header:{Text("启动")} footer:{Text("使用 macOS 登录项启动；关闭此开关即可取消。不会在退出后反复拉起应用。")}
        .onAppear { controller.refresh() }
    }
}
