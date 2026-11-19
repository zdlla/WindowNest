import AppKit

@MainActor final class DesktopBoxDemo: NSObject, NSApplicationDelegate {
    var boxes: DesktopFileBoxController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "DemoRoot") as! String)
        let prefs = AppearanceStore(repository: AppearanceRepository(url:root.appendingPathComponent("demo-appearance.json")))
        boxes = DesktopFileBoxController(preferences:prefs,configURL:root.appendingPathComponent("demo-boxes.json"))
        boxes.create()
        boxes.models.last!.add([root.appendingPathComponent("DemoA"),root.appendingPathComponent("DemoB")])
        let menu=NSMenu();let entry=NSMenuItem();let actions=NSMenu()
        actions.addItem(withTitle:"退出文件盒测试",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        entry.submenu=actions;menu.addItem(entry);NSApp.mainMenu=menu
        NSApp.activate()
    }
}
@main struct DesktopBoxDemoMain {
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate=DesktopBoxDemo();app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
