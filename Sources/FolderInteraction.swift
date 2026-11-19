import SwiftUI
import AppKit

@MainActor
final class FolderPresentation: ObservableObject {
    @Published private(set) var scope: LibraryScope?
    @Published private(set) var visible = false
    private var task: Task<Void, Never>?
    func show(_ scope: LibraryScope) {
        task?.cancel()
        self.scope = scope; visible = false
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            self?.visible = true
        }
    }
    func dismiss(after seconds: Double) {
        task?.cancel(); visible = false
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.scope = nil
        }
    }
    func reset() { task?.cancel(); task = nil; visible = false; scope = nil }
}

struct FolderProtectedBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
}
extension View {
    func protectsFolderClick() -> some View {
        anchorPreference(key: FolderProtectedBounds.self, value: .bounds) { [$0] }
    }
}

/// The transparent observer never wins hit-testing. It only dismisses a genuine
/// blank single click; buttons, menus, app tiles, scrolling and drag drops keep
/// their original events. Rectangles come from the actual SwiftUI layout.
struct FolderBlankClickRegion: NSViewRepresentable {
    var protected: [CGRect]
    var enabled: Bool
    let close: () -> Void
    final class Region: NSView {
        var protected: [CGRect] = []
        var enabled = false
        var close: (() -> Void)?
        private var monitor: Any?
        private var down: CGPoint?
        private var dragged = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, self.enabled, !self.isHiddenOrHasHiddenAncestor,
                      event.window === self.window, NSApp.modalWindow == nil else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDown: self.down = point; self.dragged = false
                case .leftMouseDragged: self.dragged = true
                case .leftMouseUp:
                    if let down = self.down, FolderBlankClickPolicy.dismiss(down: down, up: point,
                        bounds: self.bounds, protected: self.protected, dragged: self.dragged) {
                        let action = self.close
                        DispatchQueue.main.async { action?() }
                    }
                    self.down = nil
                default: break
                }
                return event
            }
        }
        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; down = nil
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeNSView(context: Context) -> Region { let view = Region(); view.setAccessibilityElement(false); return view }
    func updateNSView(_ view: Region, context: Context) { view.protected = protected; view.enabled = enabled; view.close = close }
    static func dismantleNSView(_ view: Region, coordinator: ()) { view.removeMonitor() }
}
