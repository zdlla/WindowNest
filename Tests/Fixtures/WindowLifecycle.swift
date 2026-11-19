import AppKit

final class LifecycleFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var controller: NSPanel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示 A", action: #selector(showA), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "显示全部测试窗口", action: #selector(showAll), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "隐藏全部测试窗口（保留进程）", action: #selector(hideAll), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "退出窗口存活测试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        for (index, name) in ["A", "B"].enumerated() {
            let w = NSWindow(contentRect: NSRect(x: 180 + 80*index, y: 180 + 60*index, width: 520, height: 300),
                styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            w.title = "\(name) · 窗口存活测试"; w.identifier = NSUserInterfaceItemIdentifier(name)
            w.isReleasedWhenClosed = false; w.delegate = self; w.collectionBehavior = [.fullScreenPrimary]
            let label = NSTextField(labelWithString: "无个人文档 · 用于验证关闭、隐藏、最小化与全屏")
            label.frame = NSRect(x: 20,y: 220,width: 480,height: 30); w.contentView!.addSubview(label)
            for (position, item) in [("最小化 A", #selector(minimizeA)), ("全屏 A", #selector(fullscreenA)),
                                     ("隐藏应用", #selector(hideApp)), ("关闭 A", #selector(closeA))].enumerated() {
                let b = NSButton(title: item.0, target: self, action: item.1)
                b.frame = NSRect(x: 20 + position*120,y: 120,width: 110,height: 32); w.contentView!.addSubview(b)
            }
            windows.append(w); w.makeKeyAndOrderFront(nil)
        }
        controller = NSPanel(contentRect: NSRect(x: 50,y: 60,width: 280,height: 32),
            styleMask: [.titled,.utilityWindow,.nonactivatingPanel], backing: .buffered, defer: false)
        controller.title = "窗口存活测试控制"; controller.level = .floating
        controller.canHide = false; controller.isReleasedWhenClosed = false
        controller.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        for (index, item) in [("显示 A", #selector(showA)), ("隐藏全部", #selector(hideAll)), ("退出测试", #selector(quit))].enumerated() {
            let b = NSButton(title: item.0, target: self, action: item.1)
            b.frame = NSRect(x: 5 + index*90,y: 3,width: 85,height: 26); controller.contentView!.addSubview(b)
        }
        controller.orderFrontRegardless(); NSApp.activate(); record()
    }
    @objc func showA() { NSApp.unhide(nil); windows[0].deminiaturize(nil); windows[0].makeKeyAndOrderFront(nil); NSApp.activate(); record() }
    @objc func showAll() { NSApp.unhide(nil); windows.forEach { $0.deminiaturize(nil); $0.makeKeyAndOrderFront(nil) }; NSApp.activate(); record() }
    @objc func hideAll() { windows.forEach { $0.orderOut(nil) }; controller.makeKeyAndOrderFront(nil); record() }
    @objc func closeA() { windows[0].close(); controller.makeKeyAndOrderFront(nil); record() }
    @objc func minimizeA() { windows[0].miniaturize(nil); record() }
    @objc func fullscreenA() { windows[0].toggleFullScreen(nil) }
    @objc func hideApp() { NSApp.hide(nil); record() }
    @objc func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { DispatchQueue.main.async { self.record() } }
    func windowDidMiniaturize(_ notification: Notification) { record() }
    func windowDidDeminiaturize(_ notification: Notification) { record() }
    func windowDidEnterFullScreen(_ notification: Notification) { record() }
    func windowDidExitFullScreen(_ notification: Notification) { record() }
    func applicationDidHide(_ notification: Notification) { record() }
    func applicationDidUnhide(_ notification: Notification) { record() }
    func record() {
        let state: [String: Any] = ["pid": getpid(), "hidden": NSApp.isHidden,
            "windows": windows.map { ["name": $0.identifier!.rawValue, "number": $0.windowNumber,
                "visible": $0.isVisible, "minimized": $0.isMiniaturized, "fullscreen": $0.styleMask.contains(.fullScreen)] as [String: Any] }]
        guard let path = Bundle.main.object(forInfoDictionaryKey: "LifecycleStatePath") as? String,
              let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let delegate = LifecycleFixture(); app.delegate = delegate; app.run()
