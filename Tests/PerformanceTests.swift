import Foundation
import SwiftUI
import AppKit
import ApplicationServices

@main struct PerformanceTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; checks += 1
        }
        for visible in [false, true] {
            for mini in [false, true] {
                for occluded in [false, true] {
                    for suspended in [false, true] {
                        let work = WorkspaceActivityPolicy.allowsWork(visible: visible, miniaturized: mini,
                            occluded: occluded, suspended: suspended)
                        check(work == (visible && !mini && !occluded && !suspended), "Invisible/locked workspace kept scanning")
                    }
                }
            }
        }
        var motion = OverviewMotionBudget()
        var accepted = 0
        var opening = TopOverviewHover(dwell: 0.1)
        var shownAt: Double?
        for index in 0...240 {
            let time = Double(index) / 240
            if motion.accept(time: time, motion: true) {
                accepted += 1
                if opening.update(trigger: "screen", insidePanel: false, dragging: false, interacting: false, time: time) == .show("screen") {
                    shownAt = time
                }
            }
        }
        check((45...61).contains(accepted), "240 Hz motion was not bounded to at most 60 Hz")
        check(shownAt != nil && shownAt! >= 0.1 && shownAt! <= 0.125, "Coalescing changed the configured dwell")
        check(motion.accept(time: 1.001, motion: false), "Mouse click/release was delayed by motion budget")
        check(motion.accept(time: 0, motion: true), "A reset event clock got stuck")
        var discovery = WindowDiscoveryBudget()
        check(discovery.eligible(pid: 7, candidates: [1,2], now: 0) == [1,2], "New windows must be discoverable immediately")
        discovery.attempted(pid: 7, requested: [1,2], resolved: [1], now: 0)
        check(discovery.eligible(pid: 7, candidates: [1,2,3], now: 0.5) == [1,3], "Rapid reopen retried the same unresolved metadata")
        check(discovery.eligible(pid: 7, candidates: [2], now: 2) == [2], "Discovery did not recover after cooldown")
        discovery.prune(pids: [])
        check(discovery.eligible(pid: 7, candidates: [2], now: 0.5) == [2], "Reused process IDs inherited stale retry deadlines")
        let recordID = UUID()
        func record(title: String = "Document", minimized: Bool = false, fullScreen: Bool = false,
                    hidden: Bool = false, close: Bool = true, element: AXUIElement? = nil) -> WindowRecord {
            WindowRecord(id: recordID, pid: 7, appName: "Test", bundleID: "test", icon: NSImage(),
                title: title, document: nil, label: title, minimized: minimized, fullScreen: fullScreen,
                hidden: hidden, element: element, cgID: 42, controls: WindowControlCapabilities(close: close))
        }
        check(WindowRecord.sameCatalog([record()], [record()]), "Unchanged rows should not invalidate SwiftUI")
        check(!WindowRecord.sameCatalog([record()], []), "Closed windows were suppressed by diff")
        check(!WindowRecord.sameCatalog([record()], [record(title: "Renamed")]), "Title changes were lost")
        check(!WindowRecord.sameCatalog([record()], [record(minimized: true)]), "Minimized changes were lost")
        check(!WindowRecord.sameCatalog([record()], [record(fullScreen: true)]), "Fullscreen changes were lost")
        check(!WindowRecord.sameCatalog([record()], [record(hidden: true)]), "Hidden changes were lost")
        check(!WindowRecord.sameCatalog([record()], [record(close: false)]), "Control capability changes were lost")
        let ax = AXUIElementCreateApplication(7)
        check(!WindowRecord.sameCatalog([record()], [record(element: ax)]), "Resolved AX handles must replace metadata")
        check(WindowRecord.sameCatalog([record(element: ax)], [record(element: AXUIElementCreateApplication(7))]),
            "Equivalent AX handles triggered redraw")
        let bitmap = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); bitmap.fill(CGRect(x: 0,y: 0,width: 1024,height: 1024))
        let originalIcon = NSImage(cgImage: bitmap.makeImage()!, size: NSSize(width: 512,height: 512))
        let iconCache = WindowIconCache()
        let smallIcon = iconCache.image(pid: 7, bundleID: "test", source: originalIcon)
        let smallBitmap = smallIcon.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        check(smallBitmap.width == 96 && smallBitmap.height == 96, "Window icons retained oversized decoded bitmaps")
        check(iconCache.image(pid: 7, bundleID: "test", source: originalIcon) === smallIcon, "Repeated scans decoded the same app again")
        check(iconCache.cached(pid: 7, bundleID: "different") == nil, "PID reuse returned another application's icon")
        iconCache.prune(pids: [])
        check(iconCache.cached(pid: 7, bundleID: "test") == nil, "Exited processes retained icon cache entries")
        let ids = (0..<100).map { _ in UUID() }
        let top = Set(ids.suffix(10)), main = Set(ids.prefix(30))
        let demand = WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: true, overviewVisible: true)
        check(demand.count == 18 && top.isSubset(of: demand), "Visible overview takes priority inside the 18-image budget")
        check(WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: false, overviewVisible: false).isEmpty,
            "Hidden surfaces request no screenshots")
        check(WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: false, overviewVisible: true) == top,
            "Cached main page cannot request offscreen screenshots")
        check(WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: false,
            overviewVisible: true, overviewAllowsPreviews: false).isEmpty,
            "Icon-only overview must never request screenshots, even with lingering old demand")
        let iconAndMain = WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: true,
            overviewVisible: true, overviewAllowsPreviews: false)
        check(iconAndMain == Set(ids.prefix(18)), "Icon-only overview disabled or displaced main-window previews")
        check(WindowPreviewBudget.requested(ids, main: main, overview: top, mainVisible: false,
            overviewVisible: true, overviewAllowsPreviews: true) == top,
            "Returning to a taller overview did not restore thumbnail demand")
        let first = WindowPreviewBudget.due(ids, demand: demand, attempted: [:], now: 0)
        check(first.count == 18 && Set(first) == demand, "First capture is bounded by actual demand")
        let attempted = Dictionary(uniqueKeysWithValues: first.map { ($0, 0.0) })
        check(WindowPreviewBudget.due(ids, demand: demand, attempted: attempted, now: 4).isEmpty,
            "Four-second title refresh does not regenerate eight-second previews")
        check(WindowPreviewBudget.due(ids, demand: demand, attempted: attempted, now: 8).count == 18,
            "Visible previews can refresh after their budgeted interval")
        let newID = ids[50]
        check(WindowPreviewBudget.due(ids, demand: [newID], attempted: attempted, now: 4) == [newID],
            "Newly visible content can be captured immediately")
        let cache = LRUCache<Int, Data>(totalCostLimit: WindowPreviewBudget.maxBytes, countLimit: WindowPreviewBudget.maxCount)
        for i in 0..<50 { cache.setValue(Data(count: 480 * 300 * 4), forKey: i, cost: 480 * 300 * 4) }
        check(cache.count == 18 && cache.totalCost <= WindowPreviewBudget.maxBytes, "Actual open-source cache enforces both image budgets")
        check(cache.value(forKey: 0) == nil, "Old, unused screenshots are evicted")
        _ = cache.value(forKey: 32)
        cache.setValue(Data(count: 16), forKey: 100, cost: 16)
        check(cache.value(forKey: 32) != nil && cache.value(forKey: 33) == nil, "Recently viewed screenshots survive LRU eviction")
        cache.removeAll()
        check(cache.count == 0 && cache.totalCost == 0, "Hiding every surface releases the cache budget")

        var hover = TopOverviewHover(dwell: 0.1)
        check(!hover.needsClock, "Closed, idle hover needs no polling clock")
        _ = hover.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0)
        check(hover.needsClock, "Pending dwell runs a short clock")
        _ = hover.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0.11)
        check(!hover.needsClock, "An open panel under a stationary pointer has no polling clock")
        _ = hover.update(trigger: nil, insidePanel: false, dragging: false, interacting: false, time: 0.2)
        check(hover.needsClock, "Leaving runs only the close-delay clock")
        _ = hover.update(trigger: nil, insidePanel: false, dragging: false, interacting: false, time: 0.8)
        check(!hover.needsClock, "Fully hidden returns to zero idle polling")

        for role in InteractionMotion.Role.allCases {
            for hovered in [false, true] {
                for pressed in [false, true] {
                    let reduced = InteractionMotion(role: role, hovered: hovered, pressed: pressed, enabled: true, simple: true)
                    check(reduced.scale == 1 && reduced.lift == 0, "Reduced/minimal mode must not move any content")
                    let disabled = InteractionMotion(role: role, hovered: hovered, pressed: pressed, enabled: false, simple: false)
                    check(disabled.scale == 1 && disabled.lift == 0, "Disabled controls must not animate as actionable")
                    let regular = InteractionMotion(role: role, hovered: hovered, pressed: pressed, enabled: true, simple: false)
                    check(regular.scale >= 0.95 && regular.scale <= 1.055 && abs(regular.lift) <= 2,
                        "Feedback escaped the small native motion budget")
                    if pressed { check(regular.scale <= 1 && regular.lift == 0, "Press must take priority over hover") }
                }
            }
        }
        let order = ["A", "B", "C"]
        check(InteractionMotion.filterDirection(from: nil, to: "C", order: order) == 1, "All-to-app direction is reversed")
        check(InteractionMotion.filterDirection(from: "C", to: nil, order: order) == -1, "Return-to-all direction is reversed")
        check(InteractionMotion.filterDirection(from: "C", to: "A", order: order) == -1, "Backward tabs slide forward")

        let transition = WindowFilterTransition()
        transition.select("A", animated: true, simple: false)
        check(!transition.contentVisible && transition.displayedApp == nil, "Old row fades before replacing its data")
        try await Task.sleep(for: .milliseconds(25))
        transition.select("B", animated: true, simple: false)
        try await Task.sleep(for: .milliseconds(25))
        transition.select("C", animated: true, simple: false)
        try await Task.sleep(for: .milliseconds(140))
        check(transition.displayedApp == "C" && transition.contentVisible, "Rapid tab clicks commit only the latest selection")
        transition.select("A", animated: true, simple: false)
        transition.select(nil, animated: false, simple: false)
        try await Task.sleep(for: .milliseconds(130))
        check(transition.displayedApp == nil && transition.contentVisible, "A hidden panel cannot be changed by an old animation task")
        transition.select("A", animated: true, simple: true)
        try await Task.sleep(for: .milliseconds(90))
        check(transition.displayedApp == "A" && transition.contentVisible, "Reduced motion retains a short fade and correct selection")
        transition.select("C", animated: false, simple: false)
        transition.select("A", animated: true, simple: false, order: order)
        check(transition.offset == 6, "Outgoing content must follow a backward selection")
        transition.select("C", animated: true, simple: false, order: order)
        check(transition.offset == 0 && transition.contentVisible, "Reselecting the displayed app must immediately recover")
        try await Task.sleep(for: .milliseconds(130))
        check(transition.displayedApp == "C" && transition.offset == 0, "Cancelled direction task changed the visible app")
        transition.select("A", animated: true, simple: true, order: order)
        check(transition.offset == 0, "Reduced motion has directional displacement")
        try await Task.sleep(for: .milliseconds(90))
        check(transition.displayedApp == "A" && transition.offset == 0 && transition.contentVisible, "Transition did not settle")
        print("Passed \(checks) preview-budget, LRU, idle-clock and filter-transition checks")
    }
}
