import Foundation

struct WindowServerPresence {
    var exists = false
    var onScreen = false
    var orderedIn: Bool?
    var hasSpace: Bool?
    var onActiveSpace: Bool?
}

struct WindowAvailabilityEvidence {
    var server = WindowServerPresence()
    var axAlive = false
    var axListed = false
    var minimized = false
    var hidden = false
    var fullScreen = false
    var retired = false
}

enum WindowAvailabilityPolicy {
    static func includes(_ evidence: WindowAvailabilityEvidence) -> Bool {
        guard !evidence.retired else { return false }
        let server = evidence.server
        // AppKit can remove minimized/hidden windows from the visible list.
        // A stale main/focused handle alone is deliberately insufficient.
        if evidence.axAlive && evidence.axListed {
            if evidence.minimized { return true }
            if evidence.hidden && !(server.orderedIn == false && server.hasSpace == false) { return true }
        }
        guard server.exists, server.orderedIn != false else { return false }
        if server.onScreen { return true }
        guard server.hasSpace != false else { return false }
        if server.onActiveSpace == true && !evidence.hidden && !evidence.minimized { return false }
        if server.orderedIn == true && server.hasSpace == true {
            if server.onActiveSpace == false { return true }
            if evidence.axAlive && (evidence.hidden || evidence.axListed) { return true }
        }
        // Safe degraded mode when read-only system SPI is unavailable.
        return evidence.axAlive && evidence.fullScreen && server.onActiveSpace != true
    }
}

enum WindowFocusUnavailable {
    static let message = "这个窗口已关闭或不再可用，列表已更新。"
}
