import Foundation
import CoreGraphics

enum WindowFocusRouting {
    // Finder activation/unhide and AXFrontmost can raise every folder window.
    // Its route must stay window-specific, including retries and fallbacks.
    static func targetsOnlyOneWindow(bundleID:String)->Bool { bundleID == "com.apple.finder" }
}

struct WindowForegroundSurface {
    let id: UInt32
    let bounds: CGRect
    let hasTitle: Bool
    let knownTask: Bool
}

enum WindowForegroundPolicy {
    static func frontmostTask(targetID: UInt32?, surfaces: [WindowForegroundSurface]) -> UInt32? {
        guard let targetID, let target = surfaces.first(where: { $0.id == targetID }) else { return nil }
        for surface in surfaces {
            guard surface.bounds.width >= 80, surface.bounds.height >= 50,
                  surface.hasTitle || surface.knownTask else { continue }
            if surface.bounds.intersects(target.bounds) { return surface.id }
        }
        return nil
    }
}

enum WindowFocusVerification {
    static func succeeded(targetPID: Int32, frontPID: Int32?, exactAccessibility: Bool,
                          compatibilityAttempted: Bool, targetID: UInt32?, frontWindowID: UInt32?,
                          requiresForegroundWindow: Bool = false) -> Bool {
        guard targetPID == frontPID else { return false }
        if requiresForegroundWindow {
            guard let targetID, targetID != 0, frontWindowID == targetID else { return false }
        }
        if exactAccessibility { return true }
        guard compatibilityAttempted, let targetID, targetID != 0, let frontWindowID else { return false }
        return targetID == frontWindowID
    }
}

enum WindowFocusInterruption {
    static let superseded = "已取消旧的窗口切换。"
    static let userChangedApplication = "切换已被其他操作中断。"
    static func contains(_ message: String) -> Bool {
        message == superseded || message == userChangedApplication
    }
}

/// A newer user choice invalidates every delayed raise from an older one.
final class WindowFocusTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    func issue() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; return generation
    }
    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == token
    }
}

enum PublishedWindowMerge {
    static func unique<Element>(_ sources: [[Element]], equal: (Element, Element) -> Bool) -> [Element] {
        var result: [Element] = []
        for source in sources {
            for element in source where !result.contains(where: { equal($0, element) }) { result.append(element) }
        }
        return result
    }
    static func onlyMatch<Element>(_ elements: [Element], where predicate: (Element) -> Bool) -> Element? {
        let matches = elements.filter(predicate)
        return matches.count == 1 ? matches[0] : nil
    }
}
