import Foundation
import ServiceManagement
import AppKit
import Carbon

@MainActor final class FakeLoginItemService:LoginItemService {
    var status:SMAppService.Status = .notRegistered
    var registrations=0
    var removals=0
    var fail=false
    func register() throws { registrations += 1;if fail { throw CocoaError(.fileWriteNoPermission) };status = .enabled }
    func unregister() throws { removals += 1;if fail { throw CocoaError(.fileWriteNoPermission) };status = .notRegistered }
}
@main struct LoginItemTests {
    @MainActor static func main() {
        let event=NSAppleEventDescriptor(eventClass:AEEventClass(kCoreEventClass),eventID:AEEventID(kAEOpenApplication),targetDescriptor:nil,returnID:AEReturnID(kAutoGenerateReturnID),transactionID:AETransactionID(kAnyTransactionID))
        precondition(!WorkspaceLaunchContext.isLogin(event) && !WorkspaceLaunchContext.isLogin(nil))
        event.setParam(NSAppleEventDescriptor(enumCode:OSType(keyAELaunchedAsLogInItem)),forKeyword:AEKeyword(keyAEPropData))
        precondition(WorkspaceLaunchContext.isLogin(event))
        event.setParam(NSAppleEventDescriptor(enumCode:OSType(keyAELaunchedAsServiceItem)),forKeyword:AEKeyword(keyAEPropData))
        precondition(!WorkspaceLaunchContext.isLogin(event))
        let service=FakeLoginItemService(),controller=LoginItemController(service:FakeLoginItemService())
        precondition(!controller.enabled)
        let settings=LoginItemController(service:service)
        settings.setEnabled(true);settings.setEnabled(true)
        precondition(settings.enabled && settings.error == nil && service.registrations==1)
        service.status = .requiresApproval;settings.refresh()
        precondition(settings.enabled && settings.status == .requiresApproval)
        settings.setEnabled(true);precondition(service.registrations==1)
        settings.setEnabled(false);precondition(!settings.enabled && service.removals==1)
        service.fail=true;settings.setEnabled(true)
        precondition(!settings.enabled && settings.error != nil && !settings.changing)
        service.status = .enabled;settings.refresh();settings.setEnabled(false)
        precondition(settings.enabled && settings.error != nil)
        print("Passed login-item register, idempotence, approval-required and failure-state checks without changing system login items")
    }
}
