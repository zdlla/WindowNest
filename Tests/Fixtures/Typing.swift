import AppKit
import SwiftUI

@MainActor struct TestOverviewContent: View {
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack {
            Button("筛选测试窗口", action: select)
            Button("关闭测试浮层", action: close)
        }.padding().frame(width: 360, height: 56).background(.regularMaterial)
    }
}

// Disposable input target. Only this fixture's test text/counters are saved.
@MainActor final class CountingTextView: NSTextView {
    var keyDownCount = 0
    var insertionCount = 0
    var onChange: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        keyDownCount += 1
        super.keyDown(with: event)
        onChange?()
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        insertionCount += 1
        super.insertText(string, replacementRange: replacementRange)
        onChange?()
    }
}
@MainActor final class TypingFixture: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var input: CountingTextView!
    var observer: NSObjectProtocol?
    var panel: TopOverviewPanel?
    var panelSelections = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "清空测试输入", action: #selector(reset), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "显示输入隔离浮层", action: #selector(showPanel), keyEquivalent: "1").target = self
        appMenu.addItem(withTitle: "退出输入测试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 350, y: 220, width: 600, height: 360),
            styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = "窗匣输入隔离测试"; window.isReleasedWhenClosed = false; window.delegate = self
        let label = NSTextField(labelWithString: "仅输入测试字符，不包含个人文档")
        label.frame = NSRect(x: 20,y: 310,width: 550,height: 30); window.contentView!.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 20,y: 30,width: 560,height: 270))
        input = CountingTextView(frame: scroll.bounds)
        input.isRichText = false; input.font = .monospacedSystemFont(ofSize: 22,weight: .regular)
        input.isAutomaticQuoteSubstitutionEnabled = false; input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false; input.isAutomaticSpellingCorrectionEnabled = false
        input.setAccessibilityLabel("测试输入区"); input.delegate = self
        scroll.documentView = input; scroll.hasVerticalScroller = true; window.contentView!.addSubview(scroll)
        input.onChange = { [weak self] in self?.record() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.record() } }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input); NSApp.activate(); record()
    }
    @objc func reset() { input.string = ""; input.keyDownCount = 0; input.insertionCount = 0; window.makeFirstResponder(input); record() }
    @objc func showPanel() {
        if panel == nil {
            let p = TopOverviewPanel(contentRect: NSRect(x: 420,y: 640,width:360,height:56),
                styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "输入隔离测试浮层"; p.level = .statusBar; p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true; p.isReleasedWhenClosed = false
            p.contentViewController = NSHostingController(rootView: TestOverviewContent(select: { [weak self] in
                self?.panelSelections += 1; self?.record()
            }, close: { [weak self] in self?.panel?.orderOut(nil); self?.record() }))
            panel = p
        }
        window.makeFirstResponder(input)
        panel?.orderFrontRegardless()
        // Deliberately request key status: the production class must refuse.
        panel?.makeKey()
        record()
    }
    func textDidChange(_ notification: Notification) { record() }
    func windowDidBecomeKey(_ notification: Notification) { record() }
    func windowDidResignKey(_ notification: Notification) { record() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func record() {
        guard let input, let window, let path = Bundle.main.object(forInfoDictionaryKey: "TypingStatePath") as? String else { return }
        let state: [String: Any] = ["text":input.string,"keyDown":input.keyDownCount,"insertions":input.insertionCount,
            "keyWindow":window.isKeyWindow,"firstResponder":window.firstResponder === input,"active":NSApp.isActive,
            "panelKey":panel?.isKeyWindow ?? false,"panelCanBecomeKey":panel?.canBecomeKey ?? false,
            "panelVisible":panel?.isVisible ?? false,"panelSelections":panelSelections]
        if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: URL(fileURLWithPath:path),options:.atomic) }
    }
}
@main struct TypingFixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = TypingFixture(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
