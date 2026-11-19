import AppKit
import QuartzCore

@MainActor
private class LiquidControlButton: NSButton {
    var liquidFeedbackEnabled = false { didSet { updateFeedback(animated: false) } }
    var drawsSurface = false { didSet { updateFeedback(animated: false) } }
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateFeedback(animated: true) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateFeedback(animated: true) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateFeedback(animated: false) }
    override func layout() { super.layout(); updateFeedback(animated: false) }
    private func updateFeedback(animated: Bool) {
        wantsLayer = true
        let active = hovered && isEnabled && liquidFeedbackEnabled
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = bounds.height / 2
            layer?.borderWidth = active ? 0.7 : drawsSurface ? 0.5 : 0
            layer?.borderColor = (active ? NSColor.white.withAlphaComponent(0.4) : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
            layer?.backgroundColor = (drawsSurface ? (active ? WorkspaceColors.surface : WorkspaceColors.chrome)
                : NSColor.labelColor.withAlphaComponent(active ? 0.055 : 0)).cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = active ? 0.12 : 0
            layer?.shadowRadius = active ? 6 : 0
            layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
        CATransaction.commit()
        alphaValue = pressed ? 0.82 : 1
    }
    override func mouseDown(with event: NSEvent) {
        pressed = true; updateFeedback(animated: true)
        super.mouseDown(with: event)
        pressed = false; updateFeedback(animated: true)
    }
}
@MainActor
private final class PageNavigationButton: LiquidControlButton {}

/// One fixed surface and one moving highlight. AppKit does not run a second
/// segmented-control animation or refract the moving pages through the highlight.
@MainActor
final class PageSwitcher: NSView {
    static let size = NSSize(width: 254, height: 36)
    var accent: NSColor? { didSet { updateColors() } }
    var minimalEffects = false
    var liquidFeedbackEnabled = false {
        didSet {
            for button in buttons { (button as? LiquidControlButton)?.liquidFeedbackEnabled = liquidFeedbackEnabled }
            configureGlass()
        }
    }
    var clearGlassEnabled = false { didSet { configureGlass() } }
    private let chrome = NSView()
    private var glassHost: NSView?
    private var showingGlass = false
    private let highlight = CALayer()
    private var buttons: [NSButton] = []
    private(set) var selectedMode: WorkspaceMode
    private(set) var pagePosition: CGFloat
    var onSelect: ((WorkspaceMode) -> Void)?

    init(selected: WorkspaceMode) {
        selectedMode = selected
        pagePosition = CGFloat(selected.rawValue)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 18
        chrome.layer?.masksToBounds = true
        chrome.frame = bounds
        addSubview(chrome)
        chrome.layer?.addSublayer(highlight)
        highlight.cornerRadius = 14
        highlight.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull()]
        for (index, mode) in WorkspaceMode.allCases.enumerated() {
            let button = PageNavigationButton(title: mode.title, target: self, action: #selector(selectPage(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.setButtonType(.momentaryChange)
            (button.cell as? NSButtonCell)?.highlightsBy = []
            button.setAccessibilityRole(.radioButton)
            button.toolTip = "\(mode.subtitle)（⌘\(index + 1)）"
            chrome.addSubview(button)
            buttons.append(button)
        }
        setAccessibilityElement(false)
        updateSelection(selected)
        updateColors()
        layout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { Self.size }
    override var allowsVibrancy: Bool { false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func configureGlass() {
        let enabled = (liquidFeedbackEnabled || clearGlassEnabled) && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if #available(macOS 26, *), enabled == showingGlass, let glass = glassHost as? NSGlassEffectView {
            glass.style = clearGlassEnabled ? .clear : .regular
        }
        if #available(macOS 26, *), enabled != showingGlass {
            chrome.removeFromSuperview()
            if let old = glassHost as? NSGlassEffectView { old.contentView = nil; old.removeFromSuperview() }
            glassHost = nil
            if enabled {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = clearGlassEnabled ? .clear : .regular; glass.cornerRadius = 18
                // Keep the container on the macOS 26 API surface. Individual
                // buttons retain glass bezels and our existing hover feedback.
                // Keep the navigation's existing geometry and hit targets inside the glass.
                glass.contentView = chrome
                addSubview(glass); glassHost = glass
            } else { addSubview(chrome) }
            showingGlass = enabled
        }
        layout(); updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Opaque semantic colors keep moving content from changing the control's outline.
            layer?.backgroundColor = WorkspaceColors.chrome.withAlphaComponent(showingGlass ? 0.45 : 1).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.cgColor
            highlight.backgroundColor = accent?.withAlphaComponent(0.19).cgColor ?? NSColor.quaternaryLabelColor.cgColor
        }
    }
    override func layout() {
        super.layout()
        glassHost?.frame = bounds
        chrome.frame = bounds
        let slot = (bounds.width - 8) / CGFloat(WorkspaceMode.allCases.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 4 + CGFloat(index) * slot, y: 4, width: slot, height: bounds.height - 8)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        updateHighlightGeometry()
        CATransaction.commit()
    }
    private func highlightCenter(at position: CGFloat) -> CGPoint {
        let slot = (bounds.width - 8) / CGFloat(WorkspaceMode.allCases.count)
        return CGPoint(x: 4 + slot / 2 + slot * position, y: bounds.midY)
    }
    private func updateHighlightGeometry() {
        let slot = (bounds.width - 8) / CGFloat(WorkspaceMode.allCases.count)
        let stretch: CGFloat = (minimalEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) ? 0 : 6 * abs(sin(.pi * pagePosition))
        highlight.bounds = NSRect(x: 0, y: 0, width: slot + stretch, height: bounds.height - 8)
        highlight.position = highlightCenter(at: pagePosition)
    }
    /// The pager supplies the actual position on every frame, including spring settling.
    func move(to position: CGFloat) {
        let position = min(CGFloat(WorkspaceMode.allCases.count - 1), max(0, position))
        guard pagePosition != position else { return }
        pagePosition = position
        CATransaction.begin(); CATransaction.setDisableActions(true)
        updateHighlightGeometry()
        CATransaction.commit()
    }
    func updateSelection(_ mode: WorkspaceMode) {
        selectedMode = mode
        for (index, button) in buttons.enumerated() {
            button.setAccessibilityValue(index == mode.rawValue ? 1 : 0)
        }
    }
    @objc private func selectPage(_ sender: NSButton) {
        guard let mode = WorkspaceMode(rawValue: sender.tag) else { return }
        onSelect?(mode)
    }
}

/// A native text editor in a fixed capsule. Search decoration never shares
/// the editor's layout engine, so focus and IME composition cannot move it.
final class NativeSearchInput: NSTextField {
    var onFocus: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

final class CapsuleSearchField: NSControl, NSTextFieldDelegate {
    let input = NativeSearchInput(string: "")
    private let icon = NSImageView()
    private let clearButton = NSButton()
    private let focusIndicator = CAShapeLayer()
    private var editing = false
    var accent: NSColor? { didSet { updateSurface() } }
    override var stringValue: String {
        get { input.stringValue }
        set {
            guard input.stringValue != newValue else { return }
            input.stringValue = newValue
            clearButton.isHidden = newValue.isEmpty
        }
    }
    var placeholderString: String? {
        get { input.placeholderString }
        set { input.placeholderString = newValue; input.setAccessibilityLabel(newValue) }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        input.font = .systemFont(ofSize: 13)
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.cell?.wraps = false
        input.cell?.usesSingleLineMode = true
        input.cell?.isScrollable = true
        input.delegate = self
        input.onFocus = { [weak self] in self?.editing = true; self?.updateSurface() }
        input.target = self; input.action = #selector(commitSearch)
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "清除窗口搜索")
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self; clearButton.action = #selector(clearSearch)
        clearButton.isHidden = true
        clearButton.setAccessibilityLabel("清除窗口搜索")
        clearButton.toolTip = "清除窗口搜索"
        for child in [icon, input, clearButton] { addSubview(child) }
        focusIndicator.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(focusIndicator)
        updateSurface()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func accessibilityChildren() -> [Any]? { clearButton.isHidden ? [input] : [input, clearButton] }
    var searchButtonBounds: NSRect { NSRect(x: 10, y: bounds.midY - 7, width: 14, height: 14) }
    var cancelButtonBounds: NSRect { NSRect(x: bounds.width - 26, y: bounds.midY - 9, width: 18, height: 18) }
    var searchTextBounds: NSRect { NSRect(x: 32, y: bounds.midY - 9, width: max(0, bounds.width - 62), height: 18) }
    override func layout() {
        super.layout()
        icon.frame = searchButtonBounds
        input.frame = searchTextBounds
        clearButton.frame = cancelButtonBounds
        updateSurface()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
    override func mouseDown(with event: NSEvent) { focus() }
    func focus() { window?.makeFirstResponder(input) }
    func controlTextDidBeginEditing(_ notification: Notification) { editing = true; updateSurface() }
    func controlTextDidEndEditing(_ notification: Notification) { editing = false; updateSurface() }
    func controlTextDidChange(_ notification: Notification) {
        clearButton.isHidden = input.stringValue.isEmpty
        _ = sendAction(action, to: target)
    }
    @objc private func commitSearch() { _ = sendAction(action, to: target) }
    @objc private func clearSearch() { stringValue = ""; _ = sendAction(action, to: target); focus() }
    private func updateSurface() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = bounds.height / 2
            layer?.backgroundColor = WorkspaceColors.chrome.cgColor
            layer?.borderColor = (editing ? (accent ?? .controlAccentColor).withAlphaComponent(0.55) : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
            layer?.borderWidth = editing ? 2 : 0.5
            focusIndicator.frame = bounds
            focusIndicator.path = CGPath(roundedRect: bounds.insetBy(dx: -2, dy: -2),
                cornerWidth: bounds.height / 2 + 2, cornerHeight: bounds.height / 2 + 2, transform: nil)
            focusIndicator.strokeColor = (accent ?? .controlAccentColor).withAlphaComponent(0.55).cgColor
            focusIndicator.lineWidth = 3
            focusIndicator.opacity = editing ? 1 : 0
        }
        CATransaction.commit()
    }
}

/// The toolbar item list and this view's size remain identical on all pages.
@MainActor
final class WorkspaceToolbarActions: NSView {
    static let size = NSSize(width: 284, height: 36)
    let searchField = CapsuleSearchField(frame: NSRect(x: 0, y: 2, width: 198, height: 32))
    private let refresh: NSButton
    private let add: NSButton
    private let category: NSButton
    private var transitioning = false
    private let settingsButton: NSButton
    var liquidFeedbackEnabled = false {
        didSet {
            for button in [refresh, add, category, settingsButton] {
                (button as? LiquidControlButton)?.liquidFeedbackEnabled = liquidFeedbackEnabled
            }
        }
    }
    var accent: NSColor? { didSet { searchField.accent = accent; for button in [refresh, add, category, settingsButton] { button.contentTintColor = accent } } }

    init(target: AnyObject, search: Selector, refresh: Selector, add: Selector, category: Selector, settings: Selector? = nil) {
        func button(_ symbol: String, _ label: String, _ action: Selector, x: CGFloat) -> NSButton {
            let button = LiquidControlButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: target, action: action)
            button.frame = NSRect(x: x, y: 2, width: 32, height: 32)
            // Native .glass/.circular bezel silhouettes differ on macOS 26.
            // Draw the stable circular surface in our layer; AppKit owns input.
            button.isBordered = false
            button.drawsSurface = true
            button.imagePosition = .imageOnly
            button.toolTip = label
            button.setAccessibilityLabel(label)
            return button
        }
        self.refresh = button("arrow.clockwise", "刷新窗口（⌘R）", refresh, x: 248)
        self.add = button("plus", "添加应用（⌘O）", add, x: 168)
        self.category = button("folder.badge.plus", "新建文件夹（⇧⌘N）", category, x: 248)
        self.settingsButton = button("gearshape", "设置（⌘,）", settings ?? category, x: 208)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        searchField.placeholderString = "搜索窗口或文件夹"
        searchField.setAccessibilityLabel("搜索窗口或文件夹")
        searchField.target = target; searchField.action = search
        for child in [searchField, self.refresh, self.add, self.category, settingsButton] { addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { Self.size }
    override func hitTest(_ point: NSPoint) -> NSView? {
        transitioning && bounds.contains(point) ? self : super.hitTest(point)
    }
    func show(_ mode: WorkspaceMode) {
        transition(to: CGFloat(mode.rawValue))
    }
    func transition(to position: CGFloat) {
        let p = min(2, max(0, position))
        transitioning = p != p.rounded()
        settingsButton.isHidden = false
        // Fade out before fading in: the search field and app icons share a slot.
        let windowAlpha = max(0, 1 - p * 3)
        let appAlpha = max(0, 1 - abs(1 - p) * 3)
        let fileAlpha = max(0, 1 - abs(2 - p) * 3)
        refresh.isHidden = max(windowAlpha, fileAlpha) == 0
        refresh.alphaValue = max(windowAlpha, fileAlpha)
        let refreshTitle = p > 1.5 ? "刷新当前文件夹（⌘R）" : "刷新窗口（⌘R）"
        refresh.toolTip = refreshTitle; refresh.setAccessibilityLabel(refreshTitle)
        for child in [searchField] {
            child.isHidden = windowAlpha == 0
            child.alphaValue = windowAlpha
        }
        for child in [add, category] {
            child.isHidden = appAlpha == 0
            child.alphaValue = appAlpha
        }
    }
}
