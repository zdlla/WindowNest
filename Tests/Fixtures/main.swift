// Disposable native windows for manual CUA validation; no documents are read or written.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var needsConfirmation = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        needsConfirmation = Bundle.main.object(forInfoDictionaryKey: "WindowNestFixtureNeedsConfirmation") as? Bool ?? true
        let menu = NSMenu()
        let root = NSMenuItem()
        root.submenu = NSMenu()
        root.submenu?.addItem(withTitle: "退出窗口操作验收", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(root)
        NSApp.mainMenu = menu
        for (index, title) in ["A · 窗匣测试确认", "B · 窗匣测试普通窗口"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 80 + index * 90, y: 140 + index * 70, width: 440, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.delegate = self
            let label = NSTextField(labelWithString: "仅用于窗匣窗口按钮验收，没有个人文档。")
            label.frame = NSRect(x: 30, y: 130, width: 380, height: 30)
            window.contentView?.addSubview(label)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === windows.first, needsConfirmation else { return true }
        if sender.attachedSheet != nil { return false }
        let alert = NSAlert()
        alert.messageText = "模拟未保存窗口"
        alert.informativeText = "这是窗匣验收用的测试提示，不含任何真实文档。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "放弃测试内容")
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            if response == .alertSecondButtonReturn {
                self?.needsConfirmation = false
                sender?.close()
            }
        }
        return false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
