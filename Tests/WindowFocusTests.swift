import Foundation

@main struct WindowFocusTests {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
        check(WindowFocusRouting.targetsOnlyOneWindow(bundleID:"com.apple.finder"),"Finder must not enter application-wide activation")
        check(!WindowFocusRouting.targetsOnlyOneWindow(bundleID:"com.kingsoft.wpsoffice.mac"),"Finder routing must not replace the WPS handoff")
        check(!WindowFocusRouting.targetsOnlyOneWindow(bundleID:"other.app"),"Ordinary application routing changed")
        let gate = WindowFocusTicket()
        let first = gate.issue()
        check(gate.isCurrent(first), "New focus request is not current")
        let second = gate.issue()
        check(!gate.isCurrent(first) && gate.isCurrent(second), "An old delayed raise can override a newer window choice")
        let third = gate.issue()
        check(!gate.isCurrent(second) && gate.isCurrent(third), "User interruption did not invalidate pending work")
        let desktop = PublishedWindowMerge.unique([[1,2,3], [2], [3], [1,4]], equal: ==)
        check(desktop == [1,2,3,4], "Window union loses stable identity or duplicates windows")
        let fullscreen = PublishedWindowMerge.unique([[5], [2], [3], [1,2,3,4]], equal: ==)
        check(Set(fullscreen) == Set(1...5), "Current-Space enumeration deleted other-Space windows")
        let missing = PublishedWindowMerge.unique([[], [2], [3], [1,4]], equal: ==)
        check(Set(missing) == Set(1...4), "Empty AXWindows loses key/main/remembered windows")
        check(PublishedWindowMerge.onlyMatch([1,2,3], where: { $0 == 2 }) == 2, "Exact target cannot resolve")
        check(PublishedWindowMerge.onlyMatch([1,2,2], where: { $0 == 2 }) == nil, "Ambiguous geometry guessed a different window")
        check(PublishedWindowMerge.onlyMatch([1,3], where: { $0 == 2 }) == nil, "A closed target fell back to another window")
        check(WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: true,
            compatibilityAttempted: false, targetID: 100, frontWindowID: nil), "Native AX window no longer verifies")
        check(WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: false,
            compatibilityAttempted: true, targetID: 100, frontWindowID: 100), "Exact WPS foreground document cannot verify without an AX root")
        check(!WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: false,
            compatibilityAttempted: true, targetID: 100, frontWindowID: 101), "WPS home was accepted instead of the selected document")
        check(!WindowFocusVerification.succeeded(targetPID: 10, frontPID: 11, exactAccessibility: true,
            compatibilityAttempted: true, targetID: 100, frontWindowID: 100), "Background application's stale AX focus counted as foreground")
        check(!WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: false,
            compatibilityAttempted: true, targetID: nil, frontWindowID: nil), "Missing identifiers verified a guessed window")
        check(!WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: false,
            compatibilityAttempted: false, targetID: 100, frontWindowID: 100), "Compatibility verification leaked into ordinary AX routing")
        check(!WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: true,
            compatibilityAttempted: false, targetID: 100, frontWindowID: 101, requiresForegroundWindow: true),
            "WPS AX focus falsely succeeded while a different window was on top")
        check(WindowFocusVerification.succeeded(targetPID: 10, frontPID: 10, exactAccessibility: true,
            compatibilityAttempted: false, targetID: 100, frontWindowID: 100, requiresForegroundWindow: true),
            "A verified native WPS document could not complete")
        let document = WindowForegroundSurface(id: 100, bounds: CGRect(x: 0,y: 0,width: 1000,height: 800), hasTitle: true, knownTask: true)
        let tinyHelper = WindowForegroundSurface(id: 200, bounds: CGRect(x: 50,y: 50,width: 20,height: 20), hasTitle: true, knownTask: false)
        let renderHelper = WindowForegroundSurface(id: 201, bounds: document.bounds, hasTitle: false, knownTask: false)
        let otherDisplay = WindowForegroundSurface(id: 300, bounds: CGRect(x: 1200,y: 0,width: 1000,height: 800), hasTitle: true, knownTask: true)
        let otherDocument = WindowForegroundSurface(id: 301, bounds: document.bounds, hasTitle: true, knownTask: true)
        let untitledDocument = WindowForegroundSurface(id: 302, bounds: document.bounds, hasTitle: false, knownTask: true)
        check(WindowForegroundPolicy.frontmostTask(targetID: 100, surfaces: [tinyHelper, renderHelper, document]) == 100,
            "WPS helper surfaces falsely block the focused document")
        check(WindowForegroundPolicy.frontmostTask(targetID: 100, surfaces: [otherDisplay, document]) == 100,
            "A window on another display falsely blocks focus verification")
        check(WindowForegroundPolicy.frontmostTask(targetID: 100, surfaces: [otherDocument, document]) == 301,
            "An overlapping document was ignored and a covered target succeeded")
        check(WindowForegroundPolicy.frontmostTask(targetID: 100, surfaces: [untitledDocument, document]) == 302,
            "A real untitled AX task window was treated as a helper")
        check(WindowForegroundPolicy.frontmostTask(targetID: 100, surfaces: [otherDocument]) == nil,
            "An off-Space or minimized target falsely succeeded")
        for _ in 0..<1000 {
            let old = gate.issue(), current = gate.issue()
            check(!gate.isCurrent(old) && gate.isCurrent(current), "Rapid requests keep stale activation authority")
        }
        print("Passed \(checks) focus-ticket, cross-Space union and exact-target checks")
    }
}
