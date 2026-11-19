import Foundation

@main struct WindowAvailabilityTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ text: String) { precondition(value, text); checks += 1 }
        let visible = WindowServerPresence(exists: true, onScreen: true, orderedIn: true, hasSpace: true, onActiveSpace: true)
        let otherSpace = WindowServerPresence(exists: true, onScreen: false, orderedIn: true, hasSpace: true, onActiveSpace: false)
        let parked = WindowServerPresence(exists: true, onScreen: false, orderedIn: false, hasSpace: true, onActiveSpace: true)
        let noSpace = WindowServerPresence(exists: true, onScreen: false, orderedIn: false, hasSpace: false, onActiveSpace: false)
        check(WindowAvailabilityPolicy.includes(.init(server: visible, axAlive: true, axListed: true)), "Visible task disappeared")
        check(WindowAvailabilityPolicy.includes(.init(server: visible)), "Verified visible CG-only window disappeared")
        check(!WindowAvailabilityPolicy.includes(.init()), "Background process became a window")
        check(!WindowAvailabilityPolicy.includes(.init(axAlive: true)), "Remembered AX handle became proof of an open window")
        check(!WindowAvailabilityPolicy.includes(.init(server: parked, axAlive: true, axListed: true)), "Ordered-out window was resurrected from AXWindows")
        check(!WindowAvailabilityPolicy.includes(.init(server: noSpace, axAlive: true, axListed: true)), "Retained backing window without a Space was listed")
        check(!WindowAvailabilityPolicy.includes(.init(server: noSpace)), "CG metadata created a ghost entry")
        check(WindowAvailabilityPolicy.includes(.init(server: noSpace, axAlive: true, axListed: true, minimized: true)), "Real minimized window was confused with a closed window")
        check(!WindowAvailabilityPolicy.includes(.init(server: noSpace, axAlive: true, minimized: true)), "Stale minimized flag on an unpublished node resurrected a window")
        check(WindowAvailabilityPolicy.includes(.init(server: parked, axAlive: true, axListed: true, hidden: true)), "User-hidden window was dropped")
        check(!WindowAvailabilityPolicy.includes(.init(server: noSpace, axAlive: true, axListed: true, hidden: true)), "App-hidden status resurrected a closed backing window")
        check(WindowAvailabilityPolicy.includes(.init(server: otherSpace, axAlive: true)), "Other-Space AX window disappeared")
        check(WindowAvailabilityPolicy.includes(.init(server: otherSpace)), "Other-Space CG-only task disappeared")
        check(WindowAvailabilityPolicy.includes(.init(server: otherSpace, axAlive: true, fullScreen: true)), "Fullscreen window disappeared")
        check(!WindowAvailabilityPolicy.includes(.init(server: .init(exists: true, onScreen: false, orderedIn: true, hasSpace: true, onActiveSpace: true), axAlive: true, axListed: true)), "Invisible current-Space surface was admitted")
        check(!WindowAvailabilityPolicy.includes(.init(server: .init(exists: true, onScreen: true, orderedIn: false), axAlive: true, axListed: true)), "Old on-screen snapshot overrode an explicit order-out")
        check(!WindowAvailabilityPolicy.includes(.init(server: visible, axAlive: true, axListed: true, retired: true)), "Destroyed ID returned through cached metadata")
        check(!WindowAvailabilityPolicy.includes(.init(server: .init(exists: true), axAlive: false)), "Unknown offscreen metadata was presented as clickable")
        check(WindowAvailabilityPolicy.includes(.init(server: .init(exists: true), axAlive: true, fullScreen: true)), "Unavailable SPI lost a known fullscreen AX window")
        check(WindowAvailabilityPolicy.includes(.init(axAlive: true, axListed: true, hidden: true)), "Hidden AX window was lost when metadata was unavailable")
        check(WindowAvailabilityPolicy.includes(.init(axAlive: true, axListed: true, minimized: true)), "Minimized AX window was lost when metadata was unavailable")
        for _ in 0..<50 {
            check(WindowAvailabilityPolicy.includes(.init(server: visible, axAlive: true, axListed: true)), "Reopened window did not return")
            check(!WindowAvailabilityPolicy.includes(.init(server: parked, axAlive: true, axListed: true)), "Repeated close/reopen left a ghost")
        }
        print("Passed \(checks) window availability, lifecycle and degraded-mode checks")
    }
}
