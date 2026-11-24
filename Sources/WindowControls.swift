import Foundation
import ApplicationServices

enum WindowControlAction: CaseIterable {
    case close, minimize, zoom, fullscreen

    func title(minimized: Bool, fullScreen: Bool = false) -> String {
        switch self {
        case .close: return "关闭窗口"
        case .minimize: return minimized ? "恢复窗口" : "最小化窗口"
        case .zoom: return "最大化／还原窗口"
        case .fullscreen: return fullScreen ? "退出全屏" : "全屏显示"
        }
    }
}

struct WindowControlCapabilities {
    var close = false
    var minimize = false
    var zoom = false
    var fullscreen = false

    func supports(_ action: WindowControlAction) -> Bool {
        switch action {
        case .close: return close
        case .minimize: return minimize
        case .zoom: return zoom
        case .fullscreen: return fullscreen
        }
    }
}

enum WindowControlFailure: Error {
    case unsupported, stale, permission, unavailable
    case failed(AXError)

    var message: String {
        switch self {
        case .unsupported: return "这个窗口暂不支持此操作，可能正在显示对话框。请在原应用中处理后重试。"
        case .stale: return "这个窗口已关闭，窗口列表将自动刷新。"
        case .permission: return "请在系统设置中允许窗匣使用辅助功能，然后重试。"
        case .unavailable: return "原应用暂未响应，请稍后重试。"
        case .failed: return "原应用未能完成窗口操作，请在原应用中检查窗口状态。"
        }
    }
}

/// Only the exact scanned window's AX controls and geometry are addressed. No app
/// termination, synthesized keyboard shortcuts or fallback to the front window.
protocol WindowControlAccess {
    associatedtype Element
    func button(of window: Element, action: WindowControlAction) throws -> Element?
    func enabled(_ button: Element) throws -> Bool
    func canSetMinimized(_ window: Element) throws -> Bool
    func minimized(_ window: Element) throws -> Bool?
    func setMinimized(_ value: Bool, window: Element) throws
    func hasSheet(_ window: Element) throws -> Bool
    func press(_ button: Element) throws
    func canZoom(_ window: Element) throws -> Bool
    func zoom(_ window: Element) throws
    func canSetFullScreen(_ window: Element) throws -> Bool
    func fullScreen(_ window: Element) throws -> Bool?
    func setFullScreen(_ value: Bool, window: Element) throws
}

struct WindowControlDriver<Access: WindowControlAccess> {
    let access: Access

    func capabilities(of window: Access.Element) -> WindowControlCapabilities {
        func canPress(_ action: WindowControlAction) -> Bool {
            guard let button = try? access.button(of: window, action: action) else { return false }
            return (try? access.enabled(button)) == true
        }
        // Some apps remove/disable the close control while miniaturized. Keep
        // close available when this exact window can first be restored.
        let canRestore = (try? access.minimized(window)) == true && (try? access.canSetMinimized(window)) == true
        return WindowControlCapabilities(close: canPress(.close) || canRestore,
            minimize: (try? access.canSetMinimized(window)) == true && (try? access.minimized(window)) != nil,
            zoom: (try? access.canZoom(window)) == true,
            fullscreen: (try? access.canSetFullScreen(window)) == true && (try? access.fullScreen(window)) != nil)
    }

    /// Restore only the requested minimized window, then wait for its AX close
    /// control to return. The injected scheduler keeps the serial AX queue free;
    /// no polling survives this one bounded, user-initiated operation.
    func requestClose(on window: Access.Element,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void) {
        var restored = false
        var attemptedPress = false
        func fail(_ error: Error) {
            // Never hide an unsaved-document sheet or undo an ambiguous press.
            if restored && !attemptedPress, (try? access.hasSheet(window)) == false {
                try? access.setMinimized(true, window: window)
            }
            completion(.failure(error))
        }
        func attempt(_ remaining: Int) {
            do {
                guard try !access.hasSheet(window) else { throw WindowControlFailure.unsupported }
                if try access.minimized(window) != true,
                   let button = try access.button(of: window, action: .close), try access.enabled(button) {
                    attemptedPress = true
                    try access.press(button)
                    completion(.success(()))
                } else if remaining > 0 {
                    schedule(0.08) { attempt(remaining - 1) }
                } else { throw WindowControlFailure.unsupported }
            } catch WindowControlFailure.unavailable where remaining > 0 && !attemptedPress {
                // AX can briefly time out while Dock restores the window. Only
                // retry reads; an ambiguous close press is never repeated.
                schedule(0.08) { attempt(remaining - 1) }
            } catch { fail(error) }
        }
        do {
            guard try !access.hasSheet(window) else { throw WindowControlFailure.unsupported }
            if try access.minimized(window) == true, try access.canSetMinimized(window) {
                restored = true
                try access.setMinimized(false, window: window)
                schedule(0.08) { attempt(11) }
            } else {
                // Native close is still valid for apps that can close minimized
                // windows but don't expose a writable minimized attribute.
                attemptedPress = true
                try perform(.close, on: window)
                completion(.success(()))
            }
        } catch { fail(error) }
    }

    func perform(_ action: WindowControlAction, on window: Access.Element) throws {
        // Read live state again: a scan can be stale and the user may have opened
        // a save sheet or minimized the window since the card was rendered.
        if action == .minimize {
            guard try access.canSetMinimized(window), let minimized = try access.minimized(window) else {
                throw WindowControlFailure.unsupported
            }
            try access.setMinimized(!minimized, window: window)
        } else if action == .fullscreen {
            guard try access.canSetFullScreen(window), let fullScreen = try access.fullScreen(window) else {
                throw WindowControlFailure.unsupported
            }
            try access.setFullScreen(!fullScreen, window: window)
        } else if action == .zoom {
            guard try access.canZoom(window) else { throw WindowControlFailure.unsupported }
            try access.zoom(window)
        } else {
            guard let button = try access.button(of: window, action: action), try access.enabled(button) else {
                throw WindowControlFailure.unsupported
            }
            try access.press(button)
        }
    }
}

final class AXWindowControlAccess: WindowControlAccess {
    // Accessed only on WindowService's serial AX queue, never persisted.
    var visibleScreens: [CGRect] = []
    private var zoomFrames: [(window: AXUIElement, original: CGRect, maximized: CGRect)] = []
    private var pendingZooms: [(window: AXUIElement, original: CGRect, plan: WindowZoomGeometry.Plan)] = []

    func prune(keeping windows: [AXUIElement]) {
        zoomFrames.removeAll { saved in !windows.contains { CFEqual(saved.window, $0) } }
    }
    func button(of window: AXUIElement, action: WindowControlAction) throws -> AXUIElement? {
        let key: String
        switch action {
        case .close: key = kAXCloseButtonAttribute
        case .minimize: key = kAXMinimizeButtonAttribute
        case .zoom: key = kAXZoomButtonAttribute
        case .fullscreen: key = "AXFullScreenButton"
        }
        guard let value = try read(window, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    func enabled(_ button: AXUIElement) throws -> Bool {
        (try read(button, kAXEnabledAttribute) as? NSNumber)?.boolValue == true
    }

    func minimized(_ window: AXUIElement) throws -> Bool? {
        (try read(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue
    }

    func hasSheet(_ window: AXUIElement) throws -> Bool {
        let children = try read(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return try children.contains { (try read($0, kAXRoleAttribute) as? String) == kAXSheetRole as String }
    }

    func canSetFullScreen(_ window: AXUIElement) throws -> Bool { try settable(window, "AXFullScreen") }
    func fullScreen(_ window: AXUIElement) throws -> Bool? { (try read(window, "AXFullScreen") as? NSNumber)?.boolValue }
    func setFullScreen(_ value: Bool, window: AXUIElement) throws {
        AXUIElementSetMessagingTimeout(window, 1.5)
        try check(AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, value ? kCFBooleanTrue : kCFBooleanFalse))
    }

    func canSetMinimized(_ window: AXUIElement) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable)
        if result == .attributeUnsupported || result == .noValue { return false }
        try check(result)
        return settable.boolValue
    }

    func setMinimized(_ value: Bool, window: AXUIElement) throws {
        AXUIElementSetMessagingTimeout(window, 1.5)
        try check(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse))
    }

    func press(_ button: AXUIElement) throws {
        AXUIElementSetMessagingTimeout(button, 1.5)
        try check(AXUIElementPerformAction(button, kAXPressAction as CFString))
    }

    func canZoom(_ window: AXUIElement) throws -> Bool {
        if (try read(window, "AXFullScreen") as? NSNumber)?.boolValue == true {
            return try settable(window, "AXFullScreen")
        }
        guard let button = try button(of: window, action: .zoom), try enabled(button) else { return false }
        return try settable(window, kAXPositionAttribute) && settable(window, kAXSizeAttribute)
    }

    func zoom(_ window: AXUIElement) throws {
        AXUIElementSetMessagingTimeout(window, 1.5)
        if (try read(window, "AXFullScreen") as? NSNumber)?.boolValue == true {
            try check(AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse))
            return
        }
        guard let current = try frame(window) else { throw WindowControlFailure.unsupported }
        let saved = zoomFrames.first { CFEqual($0.window, window) }
        guard let plan = WindowZoomGeometry.plan(current: current, original: saved?.original,
            maximized: saved?.maximized, screens: visibleScreens) else { throw WindowControlFailure.unsupported }
        try setPosition(plan.target.origin, window: window)
        pendingZooms.removeAll { CFEqual($0.window, window) }
        pendingZooms.append((window, current, plan))
    }

    func hasPendingZoom(_ window: AXUIElement) -> Bool { pendingZooms.contains { CFEqual($0.window, window) } }

    func finishZoom(_ window: AXUIElement) throws {
        guard let pending = pendingZooms.first(where: { CFEqual($0.window, window) }) else { return }
        try setSize(pending.plan.target.size, window: window)
    }

    func verifyZoom(_ window: AXUIElement) throws {
        guard let pending = pendingZooms.first(where: { CFEqual($0.window, window) }) else { return }
        defer { pendingZooms.removeAll { CFEqual($0.window, window) } }
        guard let actual = try frame(window), WindowZoomGeometry.same(actual, pending.plan.target) else {
            try? setFrame(pending.original, window: window)
            throw WindowControlFailure.unsupported
        }
        zoomFrames.removeAll { CFEqual($0.window, window) }
        if !pending.plan.restoring { zoomFrames.append((window, pending.original, actual)) }
    }

    func cancelZoom(_ window: AXUIElement) {
        if let pending = pendingZooms.first(where: { CFEqual($0.window, window) }) {
            try? setFrame(pending.original, window: window)
        }
        pendingZooms.removeAll { CFEqual($0.window, window) }
    }

    private func settable(_ window: AXUIElement, _ key: String) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, key as CFString, &settable)
        if result == .attributeUnsupported || result == .noValue { return false }
        try check(result)
        return settable.boolValue
    }

    private func frame(_ window: AXUIElement) throws -> CGRect? {
        guard let p = try read(window, kAXPositionAttribute), let s = try read(window, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func setFrame(_ frame: CGRect, window: AXUIElement) throws {
        try setPosition(frame.origin, window: window)
        try setSize(frame.size, window: window)
    }

    private func setPosition(_ value: CGPoint, window: AXUIElement) throws {
        var origin = value
        guard let p = AXValueCreate(.cgPoint, &origin) else { throw WindowControlFailure.unsupported }
        try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p))
    }

    private func setSize(_ value: CGSize, window: AXUIElement) throws {
        var size = value
        guard let s = AXValueCreate(.cgSize, &size) else { throw WindowControlFailure.unsupported }
        try check(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s))
    }

    private func read(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if result == .attributeUnsupported || result == .noValue { return nil }
        try check(result)
        return value
    }

    private func check(_ result: AXError) throws {
        switch result {
        case .success: return
        case .invalidUIElement: throw WindowControlFailure.stale
        case .apiDisabled: throw WindowControlFailure.permission
        case .cannotComplete: throw WindowControlFailure.unavailable
        case .attributeUnsupported, .actionUnsupported: throw WindowControlFailure.unsupported
        default: throw WindowControlFailure.failed(result)
        }
    }
}

enum WindowZoomGeometry {
    struct Plan { let target: CGRect; let restoring: Bool }

    static func same(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 3 && abs(lhs.minY - rhs.minY) <= 3 &&
        abs(lhs.width - rhs.width) <= 3 && abs(lhs.height - rhs.height) <= 3
    }

    static func plan(current: CGRect, original: CGRect?, maximized: CGRect?, screens: [CGRect]) -> Plan? {
        guard current.width > 0, current.height > 0, !screens.isEmpty else { return nil }
        func screen(for rect: CGRect) -> CGRect {
            screens.max { a, b in
                func overlap(_ s: CGRect) -> CGFloat { let r = s.intersection(rect); return r.isNull ? 0 : r.width * r.height }
                let x = overlap(a), y = overlap(b)
                if x != y { return x < y }
                func distance(_ s: CGRect) -> CGFloat { pow(s.midX - rect.midX, 2) + pow(s.midY - rect.midY, 2) }
                return distance(a) > distance(b)
            }!
        }
        if let original, let maximized, same(current, maximized) {
            let area = screen(for: original)
            let width = min(original.width, area.width), height = min(original.height, area.height)
            let target = CGRect(x: min(max(original.minX, area.minX), area.maxX - width),
                y: min(max(original.minY, area.minY), area.maxY - height), width: width, height: height)
            return Plan(target: target, restoring: true)
        }
        // A manual move/resize after maximizing becomes the new restore frame.
        return Plan(target: screen(for: current), restoring: false)
    }
}
