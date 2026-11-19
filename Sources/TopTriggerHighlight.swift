import AppKit

@MainActor
private final class TriggerHighlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TriggerHighlightView: NSView {
    var accent: NSColor = .controlAccentColor
    var label = ""
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: min(6, bounds.height / 2), yRadius: min(6, bounds.height / 2))
        accent.withAlphaComponent(0.24).setFill(); path.fill()
        accent.withAlphaComponent(0.95).setStroke(); path.lineWidth = 2; path.stroke()
        if bounds.height >= 18 {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .shadow: { let s = NSShadow(); s.shadowColor = NSColor.windowBackgroundColor; s.shadowBlurRadius = 3; return s }()]
            (label as NSString).draw(at: CGPoint(x: 10, y: (bounds.height - 14) / 2), withAttributes: attributes)
        }
    }
}

/// These panels show the exact trigger rectangles, including the display origin
/// and configured depth. They never take focus or intercept a menu-bar click.
@MainActor
final class TopTriggerHighlight {
    private var panels: [NSPanel] = []
    private var hideTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    func show(regions: [CGRect], accent: NSColor, label: String) {
        hideTask?.cancel(); hideTask = nil
        generation &+= 1
        let token = generation
        while panels.count > regions.count { panels.removeLast().close() }
        for (index, rect) in regions.enumerated() {
            let panel: NSPanel
            if index < panels.count { panel = panels[index] }
            else {
                panel = TriggerHighlightPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.title = "触发区域参考"
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                let view = TriggerHighlightView(frame: CGRect(origin: .zero, size: rect.size))
                view.autoresizingMask = [.width, .height]
                panel.contentView = view
                panels.append(panel)
            }
            panel.setFrame(rect, display: true)
            guard let view = panel.contentView as? TriggerHighlightView else { continue }
            view.accent = accent; view.label = label
            view.needsDisplay = true
            panel.orderFrontRegardless()
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.hide()
        }
    }

    func hide() {
        generation &+= 1
        hideTask?.cancel(); hideTask = nil
        panels.forEach { $0.orderOut(nil) }
    }
}
