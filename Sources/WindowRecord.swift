import AppKit
import ApplicationServices

struct WindowRecord: Identifiable {
    let id: UUID
    let pid: pid_t
    let appName: String
    let bundleID: String
    let icon: NSImage
    let title: String
    let document: String?
    let label: String
    let minimized: Bool
    let fullScreen: Bool
    let hidden: Bool
    let element: AXUIElement?
    let cgID: CGWindowID?
    let controls: WindowControlCapabilities

    static func sameCatalog(_ left: [WindowRecord], _ right: [WindowRecord]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { a, b in
            a.id == b.id && a.pid == b.pid && a.appName == b.appName && a.bundleID == b.bundleID &&
            a.title == b.title && a.document == b.document && a.label == b.label && a.minimized == b.minimized &&
            a.fullScreen == b.fullScreen && a.hidden == b.hidden && a.cgID == b.cgID &&
            a.controls.close == b.controls.close && a.controls.minimize == b.controls.minimize &&
            a.controls.zoom == b.controls.zoom && a.controls.fullscreen == b.controls.fullscreen &&
            ((a.element == nil && b.element == nil) || (a.element != nil && b.element != nil && CFEqual(a.element!, b.element!)))
        }
    }
}
