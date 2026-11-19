import AppKit

/// A mouse-operated overview, never a keyboard destination. SwiftUI controls
/// may request key status even in a .nonactivatingPanel; that style alone
/// only prevents application activation, not key-focus stealing.
@MainActor
final class TopOverviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
