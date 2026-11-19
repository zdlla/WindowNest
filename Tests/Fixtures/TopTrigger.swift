// Single, disposable 12pt-high panel lets CUA place the pointer at the actual
// display edge via a native button. It neither moves the pointer itself nor
// reads documents. Its accessory activation policy excludes it from previews.
import AppKit

final class TriggerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class TriggerDelegate: NSObject, NSApplicationDelegate {
    var panel: TriggerPanel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        panel = TriggerPanel(contentRect: CGRect(x: screen.frame.midX - 60, y: screen.frame.maxY - 12, width: 120, height: 12),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "顶部触发验收"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let button = NSButton(title: "顶部触发点", target: self, action: #selector(noop))
        button.frame = CGRect(x: 0, y: 0, width: 88, height: 12)
        button.font = .systemFont(ofSize: 8)
        let quit = NSButton(title: "退出", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = CGRect(x: 90, y: 0, width: 30, height: 12)
        quit.font = .systemFont(ofSize: 8)
        panel.contentView?.addSubview(button)
        panel.contentView?.addSubview(quit)
        panel.orderFrontRegardless()
    }
    @objc func noop() {}
}

@main struct TopTriggerFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = TriggerDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
