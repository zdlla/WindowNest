import AppKit
import QuartzCore

/// Regions with their own horizontal scrolling take precedence over page swipes.
@MainActor
final class PageGestureExclusion: NSView {
    private static let regions = NSHashTable<PageGestureExclusion>.weakObjects()
    var enabled = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { Self.regions.add(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static func contains(_ point: NSPoint, in window: NSWindow) -> Bool {
        regions.allObjects.contains {
            $0.enabled && $0.window === window && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.contains($0.convert(point, from: nil))
        }
    }
}

private final class PagingSurface: NSView {
    var onLayout: (() -> Void)?
    var blocksContent = false
    override func layout() { super.layout(); onLayout?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        blocksContent && bounds.contains(point) ? self : super.hitTest(point)
    }
}

/// Keeps each SwiftUI root at a constant size while its lightweight container moves.
private final class PageHolder: NSView {
    override func layout() {
        super.layout()
        if let content = subviews.first, content.frame != bounds { content.frame = bounds }
    }
}

@MainActor
private final class PageDisplayTarget: NSObject {
    weak var pager: WorkspacePager?
    @objc func frame(_ link: CADisplayLink) { pager?.displayFrame(at: link.targetTimestamp) }
}

/// One continuously sampled position drives both independent pages and the switcher.
@MainActor
final class WorkspacePager: NSViewController {
    private let pages: [NSViewController]
    private let holders = WorkspaceMode.allCases.map { _ in PageHolder() }
    private(set) var selectedMode: WorkspaceMode
    private(set) var isBusy = false
    private(set) var position: CGFloat
    var onSelection: ((WorkspaceMode) -> Void)?
    var onTransition: ((CGFloat) -> Void)?
    private var gestureTarget: WorkspaceMode?
    private var motion: PageMotion?
    private var completion: (() -> Void)?
    private var displayLink: CADisplayLink?
    private let displayTarget = PageDisplayTarget()
    private var lastFrameTime: TimeInterval = 0

    init(windows: NSViewController, applications: NSViewController, files: NSViewController, selected: WorkspaceMode) {
        pages = [windows, applications, files]
        selectedMode = selected
        position = CGFloat(selected.rawValue)
        super.init(nibName: nil, bundle: nil)
        displayTarget.pager = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { displayLink?.invalidate() }
    override func loadView() {
        let surface = PagingSurface(frame: NSRect(x: 0, y: 0, width: 1060, height: 700))
        surface.wantsLayer = true
        surface.layer?.masksToBounds = true
        surface.onLayout = { [weak self] in self?.render() }
        view = surface
        attach(selectedMode)
        render()
    }
    var minimalEffects = false
    private var reducedMotion: Bool { minimalEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func attach(_ mode: WorkspaceMode) {
        let page = pages[mode.rawValue], holder = holders[mode.rawValue]
        if page.parent !== self { addChild(page) }
        if holder.superview !== view {
            holder.frame = view.bounds
            holder.wantsLayer = true
            holder.layer?.masksToBounds = true
            view.addSubview(holder)
        }
        if page.view.superview !== holder {
            page.view.frame = holder.bounds
            holder.addSubview(page.view)
        }
        holder.layoutSubtreeIfNeeded()
    }
    private func prepare() {
        _ = view
        if !isBusy {
            for mode in WorkspaceMode.allCases { attach(mode) }
            // Moving cards must not accidentally launch an app or focus a window.
            (view as? PagingSurface)?.blocksContent = true
            for page in pages { page.view.setAccessibilityHidden(true) }
        }
        isBusy = true
    }
    private func render() {
        let bounds = view.bounds
        let p = min(CGFloat(pages.count - 1), max(0, position))
        let depth = abs(sin(.pi * p))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, holder) in holders.enumerated() where holder.superview != nil {
            let distance = abs(CGFloat(index) - p)
            holder.frame = reducedMotion ? bounds : bounds.offsetBy(dx: (CGFloat(index) - p) * bounds.width, dy: 0)
            holder.alphaValue = reducedMotion ? max(0, 1 - distance) : 1 - 0.06 * min(1, distance)
            holder.layer?.cornerRadius = reducedMotion ? 0 : 10 * depth
        }
        onTransition?(p)
        CATransaction.commit()
    }
    @discardableResult
    func navigate(to mode: WorkspaceMode, animated: Bool = true, completion: (() -> Void)? = nil) -> Bool {
        if !isBusy && mode == selectedMode { completion?(); return true }
        self.completion = completion
        prepare()
        gestureTarget = nil
        settle(to: mode, velocity: motion?.velocity ?? 0, animated: animated)
        return true
    }
    func track(to mode: WorkspaceMode, progress: CGFloat) {
        prepare()
        stopDisplayLink()
        motion = nil; completion = nil
        gestureTarget = mode
        position = min(CGFloat(pages.count - 1), max(0, progress))
        render()
    }
    func finishGesture(commit: Bool, velocity: Double = 0) {
        guard let gestureTarget else { return }
        self.gestureTarget = nil
        settle(to: commit ? gestureTarget : selectedMode, velocity: velocity, animated: true)
    }
    func cancelTransition() {
        guard isBusy else { return }
        completion = nil; gestureTarget = nil
        settle(to: selectedMode, velocity: motion?.velocity ?? 0, animated: true)
    }
    private func settle(to mode: WorkspaceMode, velocity: Double, animated: Bool) {
        guard animated else { finish(at: mode); return }
        motion = PageMotion(position: Double(position), velocity: velocity,
            destination: Double(mode.rawValue), response: reducedMotion ? 36 : 20)
        if motion?.isSettled == true { finish(at: mode); return }
        if displayLink == nil && view.window != nil {
            lastFrameTime = CACurrentMediaTime()
            let link = view.displayLink(target: displayTarget, selector: #selector(PageDisplayTarget.frame(_:)))
            let maximum = Float(view.window?.screen?.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }
    fileprivate func displayFrame(at time: TimeInterval) {
        let elapsed = max(0, time - lastFrameTime)
        lastFrameTime = time
        advanceAnimation(by: elapsed)
    }
    /// Advances the same analytic motion in production frames and deterministic tests.
    func advanceAnimation(by elapsed: TimeInterval) {
        guard var motion else { return }
        motion.advance(by: elapsed)
        self.motion = motion
        position = CGFloat(motion.position)
        render()
        if motion.isSettled, let destination = WorkspaceMode(rawValue: Int(motion.destination)) {
            finish(at: destination)
        }
    }
    private func stopDisplayLink() { displayLink?.invalidate(); displayLink = nil }
    /// Finalizes before hiding/minimizing, where a view display link stops receiving frames.
    func finishImmediately() {
        guard isBusy else { return }
        let mode = motion.flatMap { WorkspaceMode(rawValue: Int($0.destination)) } ?? selectedMode
        completion = nil
        finish(at: mode)
    }
    private func finish(at mode: WorkspaceMode) {
        stopDisplayLink()
        motion = nil; gestureTarget = nil
        selectedMode = mode; position = CGFloat(mode.rawValue); isBusy = false
        for index in pages.indices where index != mode.rawValue {
            holders[index].removeFromSuperview()
            if pages[index].parent === self { pages[index].removeFromParent() }
        }
        pages[mode.rawValue].view.setAccessibilityHidden(false)
        (view as? PagingSurface)?.blocksContent = false
        render()
        onSelection?(mode)
        let action = completion; completion = nil
        action?()
    }
}
