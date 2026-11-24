import AppKit
import SwiftUI

@MainActor final class DesktopBoxWindowReference:ObservableObject {
    weak var window:NSWindow?
    private var previousLevel:NSWindow.Level?
    func beginModal() {
        guard let window else { return }
        if previousLevel == nil { previousLevel=window.level }
        window.level = .normal;NSApp.activate();window.makeKeyAndOrderFront(nil)
    }
    func endModal() { if let previousLevel { window?.level=previousLevel };previousLevel=nil }
}
struct DesktopBoxWindowCapture:NSViewRepresentable {
    let reference:DesktopBoxWindowReference
    final class Probe:NSView {
        weak var reference:DesktopBoxWindowReference?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow();reference?.window=window }
        override func hitTest(_ point:NSPoint)->NSView? { nil }
    }
    func makeNSView(context:Context)->Probe { let view=Probe();view.reference=reference;return view }
    func updateNSView(_ view:Probe,context:Context) { reference.window=view.window }
}

/// AppKit supplies the system's click count, native field editor and file drag.
/// A delayed name click never races a fast double-click into a rename dialog.
struct DesktopBoxItemCell:NSViewRepresentable {
    let item:DesktopBoxItem
    let icon:NSImage
    let large:Bool
    let selected:Bool
    let renameRequested:Bool
    let disabled:Bool
    let accent:NSColor
    let reducedMotion:Bool
    let onSelect:()->Void
    let onDeselect:()->Void
    let onOpen:()->Void
    let onPreview:()->Void
    let onRenameStarted:()->Void
    let onRename:(String)->Void
    let onNewFolder:()->Void
    let onNewFile:(DesktopNewFileKind)->Void
    let onTemplate:()->Void

    func makeNSView(context:Context)->DesktopBoxItemRow { DesktopBoxItemRow() }
    func updateNSView(_ view:DesktopBoxItemRow,context:Context) {
        view.update(self)
    }
    static func dismantleNSView(_ view:DesktopBoxItemRow,coordinator:()) { view.cancelInteraction() }
}

final class DesktopBoxItemRow:NSView,NSTextFieldDelegate,NSDraggingSource {
    private let iconView=NSImageView()
    private let nameField=NSTextField(labelWithString:"")
    private var config:DesktopBoxItemCell?
    private var pendingRename:DispatchWorkItem?
    private var editing=false
    private var selected=false
    private var downPoint=NSPoint.zero
    private var wasSelected=false
    private var dragged=false
    private var hovered=false
    private var tracking:NSTrackingArea?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true;layer?.cornerRadius=7
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.font = .systemFont(ofSize:13);nameField.lineBreakMode = .byTruncatingMiddle
        nameField.delegate=self;nameField.isSelectable=false
        addSubview(iconView);addSubview(nameField)
        setAccessibilityElement(true);setAccessibilityRole(.button)
        setAccessibilityHelp("单击选中，双击打开。选中后再次单击名称或按回车重命名，空格预览。")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ next:DesktopBoxItemCell) {
        let changed=config?.item.id != next.item.id
        if changed { cancelInteraction() }
        config=next;selected=next.selected
        if !selected || next.disabled { pendingRename?.cancel();pendingRename=nil }
        if editing && (!selected || next.disabled) { finishRename(commit:false) }
        iconView.image=next.icon
        if !editing { nameField.stringValue=next.item.url.lastPathComponent }
        nameField.textColor = .labelColor
        nameField.alignment=next.large ? .center : .left
        nameField.font = .systemFont(ofSize:next.large ? 12 : 13)
        nameField.maximumNumberOfLines=next.large && !editing ? 2 : 1
        nameField.lineBreakMode=next.large ? .byTruncatingTail : .byTruncatingMiddle
        layer?.cornerRadius=next.large ? 10 : 7
        updateSurface()
        alphaValue=next.disabled ? 0.65 : 1
        setAccessibilityLabel(next.item.url.lastPathComponent)
        setAccessibilityValue(next.selected ? "已选中" : "")
        toolTip=next.item.url.lastPathComponent
        needsLayout=true
        if next.renameRequested && !editing && !next.disabled {
            DispatchQueue.main.async { [weak self] in
                guard let self,self.config?.renameRequested == true,self.selected,self.window?.isKeyWindow == true else { return }
                self.config?.onRenameStarted();self.beginRename()
            }
        }
    }
    private func updateSurface() {
        guard let config else { return }
        layer?.backgroundColor=config.accent.withAlphaComponent(selected ? 0.17 : hovered && !config.disabled ? 0.055 : 0).cgColor
        layer?.borderColor=config.accent.withAlphaComponent(selected ? 0.42 : 0).cgColor
        layer?.borderWidth=selected ? 0.75 : 0
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    override func mouseEntered(with event:NSEvent) { hovered=true;updateSurface() }
    override func mouseExited(with event:NSEvent) { hovered=false;updateSurface() }
    override func layout() {
        super.layout()
        if config?.large == true {
            iconView.frame=NSRect(x:(bounds.width-44)/2,y:9,width:44,height:44)
            nameField.frame=NSRect(x:5,y:61,width:max(0,bounds.width-10),height:editing ? 23 : 34)
        } else {
            iconView.frame=NSRect(x:7,y:(bounds.height-26)/2,width:26,height:26)
            nameField.frame=NSRect(x:42,y:(bounds.height-22)/2,width:max(0,bounds.width-51),height:22)
        }
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let hit=super.hitTest(point) else { return nil }
        return editing ? hit : self
    }
    override func mouseDown(with event:NSEvent) {
        guard let config,!config.disabled else { return }
        pendingRename?.cancel();pendingRename=nil
        downPoint=convert(event.locationInWindow,from:nil);wasSelected=selected;dragged=false
        window?.makeFirstResponder(self)
        selected=true;layer?.backgroundColor=config.accent.withAlphaComponent(0.19).cgColor
        config.onSelect()
    }
    override func mouseUp(with event:NSEvent) {
        guard !dragged,let config,!config.disabled,bounds.contains(convert(event.locationInWindow,from:nil)) else { return }
        var nameRect=nameField.frame
        if !config.large { nameRect.size.width=min(nameRect.width,(nameField.stringValue as NSString).size(withAttributes:[.font:nameField.font!]).width+8) }
        switch DesktopBoxItemClickPolicy.action(clickCount:event.clickCount,wasSelected:wasSelected,onName:nameRect.contains(downPoint)) {
        case .open: openItem()
        case .rename:
            let itemID=config.item.id
            let work=DispatchWorkItem { [weak self] in
                guard let self,self.selected,self.window?.isKeyWindow == true,self.config?.item.id==itemID,self.config?.disabled == false else { return }
                self.beginRename()
            }
            pendingRename=work
            DispatchQueue.main.asyncAfter(deadline:.now()+NSEvent.doubleClickInterval+0.08,execute:work)
        case .select,.none: break
        }
    }
    override func mouseDragged(with event:NSEvent) {
        guard let config,!config.disabled,!dragged else { return }
        let point=convert(event.locationInWindow,from:nil)
        guard hypot(point.x-downPoint.x,point.y-downPoint.y) >= 4 else { return }
        dragged=true;pendingRename?.cancel();pendingRename=nil
        let item=NSDraggingItem(pasteboardWriter:config.item.url as NSURL)
        item.setDraggingFrame(iconView.frame,contents:config.icon)
        beginDraggingSession(with:[item],event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { [.copy,.move] }
    override func keyDown(with event:NSEvent) {
        guard let config,!config.disabled else { return }
        pendingRename?.cancel();pendingRename=nil
        switch event.keyCode {
        case 36,76: beginRename()
        case 49: config.onPreview()
        case 53: pendingRename?.cancel();config.onDeselect()
        case 125 where event.modifierFlags.contains(.command): openItem()
        default: super.keyDown(with:event)
        }
    }
    private func openItem() {
        guard let config,!config.disabled else { return }
        pendingRename?.cancel();pendingRename=nil
        if !config.reducedMotion {
            let pulse=CABasicAnimation(keyPath:"transform.scale")
            pulse.fromValue=0.97;pulse.toValue=1;pulse.duration=0.16
            layer?.add(pulse,forKey:"open-feedback")
        }
        config.onOpen()
    }
    private func beginRename() {
        guard let config,!config.disabled,selected,!editing else { return }
        pendingRename?.cancel();pendingRename=nil
        editing=true;nameField.maximumNumberOfLines=1;needsLayout=true;window?.makeKey()
        nameField.isEditable=true;nameField.isSelectable=true;nameField.isBordered=true;nameField.drawsBackground=true
        nameField.backgroundColor = .textBackgroundColor;nameField.focusRingType = .default
        window?.makeFirstResponder(nameField)
        if let editor=nameField.currentEditor() {
            let title=config.item.url.lastPathComponent
            let stem=config.item.directory ? title : (title as NSString).deletingPathExtension
            editor.selectedRange=NSRange(location:0,length:(stem as NSString).length)
        }
    }
    private func finishRename(commit:Bool) {
        guard editing else { return }
        editing=false
        let value=nameField.stringValue
        window?.endEditing(for:nameField)
        nameField.isEditable=false;nameField.isSelectable=false;nameField.isBordered=false;nameField.drawsBackground=false
        nameField.stringValue=config?.item.url.lastPathComponent ?? ""
        nameField.maximumNumberOfLines=config?.large == true ? 2 : 1;needsLayout=true
        if commit,value != config?.item.url.lastPathComponent { config?.onRename(value) }
    }
    func controlTextDidEndEditing(_ obj:Notification) { finishRename(commit:true) }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector)->Bool {
        if command == #selector(NSResponder.cancelOperation(_:)) { finishRename(commit:false);window?.makeFirstResponder(self);return true }
        if command == #selector(NSResponder.insertNewline(_:)) { finishRename(commit:true);window?.makeFirstResponder(self);return true }
        return false
    }
    override func menu(for event:NSEvent)->NSMenu? {
        guard let config else { return nil }
        pendingRename?.cancel();pendingRename=nil;config.onSelect()
        let menu=NSMenu()
        func add(_ title:String,_ tag:Int,_ enabled:Bool=true) {
            let item=NSMenuItem(title:title,action:#selector(menuAction(_:)),keyEquivalent:"")
            item.target=self;item.tag=tag;item.isEnabled=enabled;menu.addItem(item)
        }
        menu.autoenablesItems=false
        add(config.item.acceptsChildren ? "在文件盒中打开" : "使用默认应用打开",0,!config.disabled)
        add("快速查看",1,!config.disabled)
        add("重命名…",2,!config.disabled)
        add("在访达中显示",3)
        menu.addItem(.separator())
        add("在当前目录新建文件夹",4,!config.disabled)
        let newItem=NSMenuItem(title:"新建文件",action:nil,keyEquivalent:"")
        let submenu=NSMenu();submenu.autoenablesItems=false
        for (index,kind) in DesktopNewFileKind.allCases.enumerated() {
            let item=NSMenuItem(title:kind.title,action:#selector(menuAction(_:)),keyEquivalent:"")
            item.target=self;item.tag=100+index;item.isEnabled = !config.disabled
            item.image=FileTypeIcons.shared.menuImage(for:kind.ext);submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let other=NSMenuItem(title:"从其他文件模板新建…",action:#selector(menuAction(_:)),keyEquivalent:"")
        other.target=self;other.tag=5;other.isEnabled = !config.disabled;submenu.addItem(other)
        newItem.submenu=submenu;menu.addItem(newItem)
        return menu
    }
    @objc private func menuAction(_ sender:NSMenuItem) {
        guard let config else { return }
        switch sender.tag {
        case 0: openItem()
        case 1: config.onPreview()
        case 2: selected=true;beginRename()
        case 3: NSWorkspace.shared.activateFileViewerSelecting([config.item.url])
        case 4: config.onNewFolder()
        case 5: config.onTemplate()
        case 100..<(100+DesktopNewFileKind.allCases.count): config.onNewFile(DesktopNewFileKind.allCases[sender.tag-100])
        default: break
        }
    }
    override func accessibilityPerformPress()->Bool { openItem();return config?.disabled == false }
    func cancelInteraction() { pendingRename?.cancel();pendingRename=nil;finishRename(commit:false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow();if window == nil { cancelInteraction() } }
    deinit { pendingRename?.cancel() }
}

struct DesktopBoxNewFileSheet:View {
    let kind:DesktopNewFileKind
    let saving:Bool
    let error:String?
    let onCancel:()->Void
    let onCreate:(String,String)->Void
    @SwiftUI.State private var name="新建文本文件.txt"
    @SwiftUI.State private var contents=""
    @FocusState private var nameFocused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("新建 \(kind.title) 文件").font(.headline)
            TextField("文件名（含扩展名）",text:$name).textFieldStyle(.roundedBorder).focused($nameFocused)
            if kind.editableContents {
                Text("文件内容").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text:$contents).font(.system(size:13,design:.monospaced)).frame(minHeight:200)
                    .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(nsColor:.separatorColor),lineWidth:1))
            } else {
                Label("创建可直接编辑的空白 \(kind.title) 文档",systemImage:"doc.badge.plus")
                    .foregroundStyle(.secondary).padding(.vertical,20)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Spacer();Button("取消",action:onCancel).keyboardShortcut(.cancelAction)
                Button("创建") { onCreate(name,contents) }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || contents.utf8.count > 1024*1024)
            }
        }.padding(20).frame(width:500,height:kind.editableContents ? 400 : 200).disabled(saving).interactiveDismissDisabled(saving)
            .onAppear { name=kind.defaultName;contents=kind.initialContents;nameFocused=true }
    }
}
