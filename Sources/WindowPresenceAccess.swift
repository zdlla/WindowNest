import ApplicationServices
import Darwin
import Foundation

/// Read-only WindowServer checks. Never switches or moves a Space/window.
/// All calls are serialized by WindowService; each scan has its own cache.
final class WindowPresenceAccess {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Ordered = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Bool>) -> Int32
    private typealias Spaces = @convention(c) (UInt32, UInt64, CFArray) -> Unmanaged<CFArray>?
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private let connection: Connection?
    private let ordered: Ordered?
    private let spaces: Spaces?
    private let displays: Displays?
    private var connectionID: UInt32 = 0
    private var activeSpaces: Set<UInt64>?
    private var cache: [CGWindowID: WindowServerPresence] = [:]

    init() {
        func symbol(_ names: [String]) -> UnsafeMutableRawPointer? {
            for name in names {
                if let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return address }
            }
            return nil
        }
        connection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"]).map { unsafeBitCast($0, to: Connection.self) }
        ordered = symbol(["SLSWindowIsOrderedIn"]).map { unsafeBitCast($0, to: Ordered.self) }
        spaces = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"]).map { unsafeBitCast($0, to: Spaces.self) }
        displays = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"]).map { unsafeBitCast($0, to: Displays.self) }
    }

    func beginSnapshot() {
        cache.removeAll(keepingCapacity: true)
        connectionID = connection?() ?? 0
        activeSpaces = nil
        guard connectionID != 0, let data = displays?(connectionID)?.takeRetainedValue() as? [[String: Any]] else { return }
        let identifiers = data.compactMap { display -> UInt64? in
            guard let current = display["Current Space"] as? [String: Any] else { return nil }
            return (current["ManagedSpaceID"] as? NSNumber ?? current["id64"] as? NSNumber)?.uint64Value
        }
        if !identifiers.isEmpty { activeSpaces = Set(identifiers) }
    }

    func state(id: CGWindowID?, exists: Bool, onScreen: Bool) -> WindowServerPresence {
        guard let id, id != 0 else { return WindowServerPresence(exists: exists, onScreen: onScreen) }
        if let cached = cache[id] { return cached }
        var value = WindowServerPresence(exists: exists, onScreen: onScreen)
        if connectionID != 0 {
            if let ordered {
                var flag = false
                if ordered(connectionID, id, &flag) == 0 { value.orderedIn = flag }
            }
            if onScreen {
                value.hasSpace = true
                value.onActiveSpace = true
            } else if let raw = spaces?(connectionID, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] {
                let assigned = Set(raw.map(\.uint64Value))
                value.hasSpace = !assigned.isEmpty
                if let activeSpaces { value.onActiveSpace = !activeSpaces.isDisjoint(with: assigned) }
            }
        }
        cache[id] = value
        return value
    }
}
