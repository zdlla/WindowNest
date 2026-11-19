import AppKit

@MainActor enum OpenSourceNotices {
    private static var controller:NSWindowController?
    private static var closeObserver:NSObjectProtocol?
    static func show() {
        if let controller { controller.showWindow(nil);controller.window?.makeKeyAndOrderFront(nil);NSApp.activate();return }
        guard let root=Bundle.main.resourceURL?.appendingPathComponent("Licenses"),
              let text=try? String(contentsOf:root.appendingPathComponent("THIRD_PARTY_NOTICES.md"),encoding:.utf8) else { return }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:560),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="开源软件声明";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:520,height:360)
        window.appearance=NSApp.mainWindow?.appearance
        let scroll=NSScrollView(frame:window.contentView!.bounds);scroll.hasVerticalScroller=true;scroll.autoresizingMask=[.width,.height]
        let content=NSTextView(frame:scroll.bounds)
        content.isEditable=false;content.isSelectable=true;content.font=NSFont.systemFont(ofSize:13)
        content.textContainerInset=NSSize(width:20,height:20);content.textColor = .labelColor
        content.backgroundColor = .textBackgroundColor;content.isVerticallyResizable=true;content.isHorizontallyResizable=false
        content.autoresizingMask=[.width];content.textContainer?.widthTracksTextView=true
        content.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        var fullText=text
        let files=(FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])?.allObjects as? [URL] ?? [])
            .filter { !["json","html"].contains($0.pathExtension) && $0.lastPathComponent != "THIRD_PARTY_NOTICES.md" }.sorted { $0.path<$1.path }
        for file in files {
            if let license=try? String(contentsOf:file,encoding:.utf8) {
                fullText += "\n\n—— \(file.path.replacingOccurrences(of:root.path+"/",with:"")) ——\n\n"+license
            }
        }
        content.string=fullText;scroll.documentView=content;window.contentView?.addSubview(scroll)
        controller=NSWindowController(window:window)
        closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { _ in
            MainActor.assumeIsolated {
                controller=nil
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver=nil
            }
        }
        window.center();controller?.showWindow(nil);NSApp.activate()
    }
}
