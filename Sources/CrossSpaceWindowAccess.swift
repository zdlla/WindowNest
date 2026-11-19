import ApplicationServices
import Darwin
import Foundation

/// Optional compatibility bridge for windows omitted from AXWindows in another
/// Space. Symbol absence is harmless. Never changes a Space or synthesizes input.
/// Call only on WindowService's serial queue, and only for known WindowServer IDs.
final class CrossSpaceWindowAccess {
    private typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private let create: Create?
    private let windowID: WindowID?
    private var cursors: [pid_t: UInt64] = [:]

    init() {
        let symbols = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        create = dlsym(symbols, "_AXUIElementCreateWithRemoteToken").map { unsafeBitCast($0, to: Create.self) }
        windowID = dlsym(symbols, "_AXUIElementGetWindow").map { unsafeBitCast($0, to: WindowID.self) }
    }

    func prune(pids: Set<pid_t>) { cursors = cursors.filter { pids.contains($0.key) } }

    func identifier(of element: AXUIElement) -> CGWindowID? {
        guard let windowID else { return nil }
        var value: CGWindowID = 0
        guard windowID(element, &value) == AXError.success.rawValue, value != 0 else { return nil }
        return value
    }

    func resolve(pid: pid_t, requested: Set<CGWindowID>, seconds: TimeInterval, maxAttempts: Int = 4096) -> [CGWindowID: AXUIElement] {
        guard pid != getpid(), !requested.isEmpty, seconds > 0, let create, let windowID else { return [:] }
        let end = ProcessInfo.processInfo.systemUptime + min(seconds, 0.18)
        var result: [CGWindowID: AXUIElement] = [:]
        var next = cursors[pid] ?? 0
        // This is the wire token format, not a read of AXUIElement object memory.
        var token = Data(repeating: 0, count: 20)
        var process = pid.littleEndian
        var protocolTag = UInt32(0x636f636f).littleEndian
        withUnsafeBytes(of: &process) { token.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: &protocolTag) { token.replaceSubrange(8..<12, with: $0) }
        var attempts = 0
        while ProcessInfo.processInfo.systemUptime < end && attempts < min(4096, maxAttempts) {
            let identifier = next
            next = next < 1_000_000 ? next + 1 : 0
            attempts += 1
            var field = identifier.littleEndian
            withUnsafeBytes(of: &field) { token.replaceSubrange(12..<20, with: $0) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.02)
            var wid: CGWindowID = 0
            guard windowID(element, &wid) == AXError.success.rawValue,
                  requested.contains(wid), result[wid] == nil,
                  ProcessInfo.processInfo.systemUptime < end else { continue }
            // Descendants can report their containing window's ID. A matching
            // number alone must never authorize a close/raise on a child node.
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                  role as? String == kAXWindowRole as String else { continue }
            result[wid] = element
            if result.count == requested.count { break }
        }
        cursors[pid] = next
        return result
    }
}
