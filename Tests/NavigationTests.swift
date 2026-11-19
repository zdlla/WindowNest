import AppKit

@MainActor
private final class NavigationTestActions: NSObject {
    @objc func performAction(_ sender: Any?) {}
}

@main
struct NavigationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        func page() -> NSViewController {
            let controller = NSViewController()
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
            return controller
        }
        let windows = page(), applications = page(), files = page()
        let pager = WorkspacePager(windows: windows, applications: applications, files: files, selected: .windows)
        let switcher = PageSwitcher(selected: .windows)
        var transitions: [CGFloat] = []
        pager.onTransition = { position in
            transitions.append(position)
            switcher.move(to: position)
        }
        pager.onSelection = { switcher.updateSelection($0) }
        _ = pager.view
        let width = pager.view.bounds.width
        let originalFrame = switcher.frame
        for amount: CGFloat in [0.05, 0.20, 0.45, 0.30, 0.12] {
            pager.track(to: .applications, progress: amount)
            check(abs(switcher.pagePosition - amount) < 0.0001, "Indicator lost physical gesture progress")
            check(abs(windows.view.superview!.frame.minX + width * amount) < 0.0001, "Page does not match indicator")
            check(windows.view.frame.origin == .zero, "Transition moved the content root within its container")
            check(switcher.frame == originalFrame, "Control geometry changed during gesture")
            check(switcher.selectedMode == .windows, "Uncommitted gesture changed selection")
        }
        func settle() {
            for _ in 0..<150 where pager.isBusy { pager.advanceAnimation(by: 1.0 / 120) }
            check(!pager.isBusy, "Motion did not settle within the expected time")
            check(pager.position == switcher.pagePosition, "Page and indicator finished out of sync")
        }
        pager.finishGesture(commit: false)
        check(switcher.pagePosition == 0.12, "Releasing a gesture teleported the indicator")
        pager.advanceAnimation(by: 1.0 / 120)
        check(switcher.pagePosition > 0 && switcher.pagePosition < 0.12, "Rollback did not advance continuously")
        settle()
        check(pager.selectedMode == .windows && switcher.selectedMode == .windows, "Cancel changed page")
        check(switcher.pagePosition == 0, "Cancel did not restore indicator")
        pager.track(to: .applications, progress: 0.42)
        pager.finishGesture(commit: true, velocity: 1.4)
        check(pager.position == 0.42, "Release changed position before the first animation frame")
        pager.advanceAnimation(by: 1.0 / 120)
        check(pager.position > 0.42 && pager.position < 0.5, "Release velocity was not carried into motion")
        check(pager.position == switcher.pagePosition, "Spring frame uses a different indicator position")
        settle()
        check(pager.selectedMode == .applications && switcher.selectedMode == .applications, "Commit selection mismatch")
        pager.track(to: .windows, progress: 0.75)
        check(switcher.pagePosition == 0.75, "Reverse gesture did not share absolute page progress")
        pager.finishGesture(commit: true, velocity: -2)
        settle()
        check(switcher.pagePosition == 0 && pager.selectedMode == .windows, "Reverse commit failed")
        pager.navigate(to: .applications)
        pager.advanceAnimation(by: 0.06)
        let interruptedPosition = pager.position
        check(interruptedPosition > 0 && interruptedPosition < 1, "Click did not animate")
        check(pager.navigate(to: .windows), "Rapid reverse click was ignored")
        check(pager.position == interruptedPosition, "Reverse click teleported the page")
        settle()
        check(pager.selectedMode == .windows, "Reverse click did not reach requested page")
        pager.navigate(to: .applications)
        pager.advanceAnimation(by: 0.08)
        let beforeDrag = pager.position
        pager.track(to: .windows, progress: beforeDrag - 0.02)
        check(abs(pager.position - (beforeDrag - 0.02)) < 0.0001, "A gesture could not take over a running click")
        pager.finishGesture(commit: true)
        settle()
        pager.navigate(to: .applications)
        pager.advanceAnimation(by: 0.07)
        pager.cancelTransition()
        settle()
        check(pager.selectedMode == .windows, "Escape cancellation did not restore completed page")
        pager.navigate(to: .applications)
        pager.advanceAnimation(by: 0.05)
        pager.finishImmediately()
        check(!pager.isBusy && pager.selectedMode == .applications, "Hiding during motion left navigation locked")
        check(switcher.frame == originalFrame, "Repeated interactions moved the toolbar control")
        check(applications.view.frame.size == pager.view.bounds.size, "A transition changed the content layout size")
        pager.navigate(to: .files)
        settle()
        check(pager.selectedMode == .files && switcher.pagePosition == 2, "Third page could not settle")
        check(files.view.frame.size == pager.view.bounds.size, "File page root was resized during navigation")
        pager.track(to: .applications, progress: 1.7)
        check(switcher.pagePosition == 1.7, "File-to-app gesture lost absolute progress")
        pager.finishGesture(commit: true, velocity: -1.2)
        settle()
        check(pager.selectedMode == .applications, "File-to-app gesture selected the wrong page")
        pager.navigate(to: .windows)
        settle()
        pager.navigate(to: .files)
        pager.advanceAnimation(by: 0.07)
        pager.navigate(to: .applications)
        settle()
        check(pager.selectedMode == .applications, "Three-page retarget failed")
        check(switcher.frame == originalFrame, "Adding the third page moved the navigation shell")
        func navigationButtons(_ view: NSView) -> [NSButton] {
            view.subviews.flatMap { child -> [NSButton] in
                if let button = child as? NSButton { return [button] }
                return navigationButtons(child)
            }.sorted { $0.tag < $1.tag }
        }
        let navigationRects = navigationButtons(switcher).map { $0.convert($0.bounds, to: switcher) }
        for clear in [true, false, true, false] {
            switcher.clearGlassEnabled = clear
            check(switcher.frame == originalFrame && switcher.intrinsicContentSize == PageSwitcher.size, "Glass appearance changed the navigation shell")
            check(navigationButtons(switcher).map { $0.convert($0.bounds, to: switcher) } == navigationRects,
                "Changing glass reparented or resized a navigation hit target")
            check(navigationButtons(switcher).map(\.tag) == [0, 1, 2], "Glass appearance lost a page button")
        }
        for liquid in [true, false, true, false] {
            switcher.liquidFeedbackEnabled = liquid
            check(navigationButtons(switcher).map { $0.convert($0.bounds, to: switcher) } == navigationRects,
                "Liquid hover feedback changed navigation slots")
        }
        let actionTarget = NavigationTestActions()
        let action = #selector(NavigationTestActions.performAction(_:))
        let actions = WorkspaceToolbarActions(target: actionTarget, search: action,
            refresh: action, add: action, category: action)
        let actionsFrame = actions.frame
        actions.transition(to: 0.5)
        check(actions.subviews.filter { !$0.isHidden }.count == 1, "Only the permanent settings control should remain during a transition")
        check(actions.frame == actionsFrame, "Toolbar fade changed its reserved width")
        for mode: WorkspaceMode in [.windows, .applications, .files, .windows, .applications] {
            actions.show(mode)
            check(actions.frame == actionsFrame && actions.intrinsicContentSize == WorkspaceToolbarActions.size,
                "Toolbar actions resized between pages")
        }
        check(actions.subviews.filter { !$0.isHidden }.count == 3, "App toolbar actions did not restore after a fade")
        let toolbarRects = actions.subviews.map(\.frame)
        for liquid in [true, false, true, false] {
            actions.liquidFeedbackEnabled = liquid
            check(actions.subviews.map(\.frame) == toolbarRects && actions.frame == actionsFrame,
                "Liquid button bezels changed toolbar geometry")
        }
        // Test the reported cross-release regression: the canvas must be white
        // in light mode, and round controls must not rely on OS bezel choices.
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            appearance.performAsCurrentDrawingAppearance {
                let color = WorkspaceColors.canvas.usingColorSpace(.sRGB)!
                if name == .aqua {
                    check(color.redComponent > 0.999 && color.greenComponent > 0.999 && color.blueComponent > 0.999,
                        "Light canvas inherited an OS-dependent gray background")
                } else { check(color.redComponent < 0.2, "Dark appearance lost its dark canvas") }
            }
            actions.appearance = appearance
            actions.layoutSubtreeIfNeeded()
            for button in actions.subviews.compactMap({ $0 as? NSButton }) {
                button.layout()
                check(!button.isBordered && button.layer?.cornerRadius == button.bounds.height / 2,
                    "A toolbar control fell back to a square native bezel")
            }
        }
        actions.searchField.layout()
        check(!actions.searchField.input.isBezeled && !actions.searchField.input.drawsBackground,
            "Search field still delegates its shape to the native bezel")
        check(actions.searchField.layer?.cornerRadius == actions.searchField.bounds.height / 2,
            "Toolbar search lost its capsule silhouette")
        for width: CGFloat in [180, 198, 260] {
            let search = CapsuleSearchField(frame: NSRect(x: 0, y: 0, width: width, height: 32))
            check(search.searchButtonBounds.maxX + 6 <= search.searchTextBounds.minX,
                "Search placeholder/editor overlaps the magnifying glass")
            check(search.searchTextBounds.maxX + 3 <= search.cancelButtonBounds.minX,
                "Search text overlaps its clear button")
            check(search.searchTextBounds.midY == search.bounds.midY && search.searchButtonBounds.midY == search.bounds.midY,
                "Search text and icon are no longer vertically centered")
        }
        let editorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150), styleMask: .titled, backing: .buffered, defer: false)
        let editorSearch = CapsuleSearchField(frame: NSRect(x: 20, y: 40, width: 198, height: 32))
        editorWindow.contentView!.addSubview(editorSearch)
        editorSearch.layoutSubtreeIfNeeded()
        let searchFrames = editorSearch.subviews.map(\.frame)
        editorSearch.focus()
        check(editorSearch.currentEditor() == nil && editorSearch.input.currentEditor() != nil,
            "Search focus did not forward to its separate native editor")
        check(editorSearch.subviews.map(\.frame) == searchFrames, "Focusing search moved its icon or text container")
        editorSearch.input.stringValue = "测试查询"
        editorSearch.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editorSearch.input))
        check(editorSearch.stringValue == "测试查询" && editorSearch.subviews.map(\.frame) == searchFrames,
            "Typing changed the search layout")
        check(editorSearch.accessibilityChildren()?.count == 2, "Clear button is missing from search accessibility")
        editorSearch.stringValue = ""
        check(editorSearch.accessibilityChildren()?.count == 1, "Empty search left a visible clear button")
        editorWindow.makeFirstResponder(nil)
        check(switcher.layer?.masksToBounds == true && switcher.layer?.cornerRadius == 18,
            "Glass could escape the navigation capsule")
        let regionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        regionWindow.contentView = root
        let region = PageGestureExclusion(frame: NSRect(x: 100, y: 100, width: 400, height: 120))
        root.addSubview(region)
        check(!PageGestureExclusion.contains(NSPoint(x: 150, y: 150), in: regionWindow), "A non-overflowing pinned row stole page navigation")
        region.enabled = true
        check(PageGestureExclusion.contains(NSPoint(x: 150, y: 150), in: regionWindow), "A horizontally scrolling row did not keep its own gestures")
        check(!PageGestureExclusion.contains(NSPoint(x: 50, y: 50), in: regionWindow), "The scroll region blocked the rest of the page")
        check(region.hitTest(NSPoint(x: 150, y: 150)) == nil, "The scroll marker intercepted app clicks")
        region.isHidden = true
        check(!PageGestureExclusion.contains(NSPoint(x: 150, y: 150), in: regionWindow), "An invisible row blocked navigation")
        region.isHidden = false
        region.removeFromSuperview()
        check(!PageGestureExclusion.contains(NSPoint(x: 150, y: 150), in: regionWindow), "A detached page retained a gesture exclusion")
        print("Passed \(checks) native navigation regression checks")
    }
}
