import Foundation
import ApplicationServices

private final class TestAccess: WindowControlAccess {
    var buttons: [WindowControlAction: Int] = [.close: 11, .zoom: 13]
    var disabled: Set<Int> = []
    var isMinimized = false
    var settable = true
    var stale = false
    var pressFailure: WindowControlFailure?
    var pressed: [Int] = []
    var zoomed: [Int] = []
    var supportsZoom = true
    var writes: [(Int, Bool)] = []
    var addressed: [Int] = []
    var fullscreenState = false
    var fullscreenSettable = true
    var fullscreenWrites: [(Int, Bool)] = []

    func button(of window: Int, action: WindowControlAction) throws -> Int? {
        addressed.append(window)
        if stale { throw WindowControlFailure.stale }
        return buttons[action]
    }
    func enabled(_ button: Int) throws -> Bool { !disabled.contains(button) }
    func canSetMinimized(_ window: Int) throws -> Bool {
        addressed.append(window)
        if stale { throw WindowControlFailure.stale }
        return settable
    }
    func minimized(_ window: Int) throws -> Bool? { isMinimized }
    func setMinimized(_ value: Bool, window: Int) throws {
        writes.append((window, value)); isMinimized = value
    }
    func press(_ button: Int) throws {
        if let pressFailure { throw pressFailure }
        pressed.append(button)
    }
    func canZoom(_ button: Int) throws -> Bool { supportsZoom }
    func zoom(_ button: Int) throws {
        guard supportsZoom else { throw WindowControlFailure.unsupported }
        zoomed.append(button)
    }
    func canSetFullScreen(_ window: Int) throws -> Bool { fullscreenSettable }
    func fullScreen(_ window: Int) throws -> Bool? { fullscreenState }
    func setFullScreen(_ value: Bool, window: Int) throws {
        fullscreenWrites.append((window, value)); fullscreenState = value
    }
}

@main struct WindowControlTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ title: String) {
            guard condition() else { fatalError(title) }; count += 1
        }
        func expectFailure(_ action: () throws -> Void, _ title: String) {
            do { try action(); fatalError(title) }
            catch is WindowControlFailure { count += 1 }
            catch { fatalError("Unexpected error: \(error)") }
        }
        let access = TestAccess(), window = 42
        let driver = WindowControlDriver(access: access)
        let caps = driver.capabilities(of: window)
        check(caps.close && caps.minimize && caps.zoom, "Normal unminimized windows expose all actions")
        try driver.perform(.close, on: window)
        check(access.pressed == [11] && access.writes.isEmpty, "Close presses only this window's native close button")
        try driver.perform(.zoom, on: window)
        check(access.pressed == [11] && access.zoomed == [window], "Maximize resizes the exact window, without a fullscreen press")
        try driver.perform(.minimize, on: window)
        check(access.writes.count == 1 && access.writes[0].0 == window && access.writes[0].1, "Minimize sets exact window state")
        try driver.perform(.minimize, on: window)
        check(access.writes.count == 2 && !access.writes[1].1, "A second click restores the live minimized state")
        check(Set(access.addressed) == [window], "Every operation targets only the scanned window")
        check(caps.fullscreen, "Fullscreen availability is independent of maximize")
        try driver.perform(.fullscreen, on: window)
        check(access.fullscreenWrites.count == 1 && access.fullscreenWrites[0].0 == window && access.fullscreenState,
            "Fullscreen sets only the exact target window's state")
        try driver.perform(.fullscreen, on: window)
        check(!access.fullscreenState && access.fullscreenWrites.count == 2, "Fullscreen toggles back from live state")
        access.fullscreenSettable = false
        expectFailure({ try driver.perform(.fullscreen, on: window) }, "Read-only fullscreen state is not overridden")
        check(access.fullscreenWrites.count == 2 && access.pressed == [11], "Unsupported fullscreen cannot fall back to shortcuts or another window")
        check(WindowControlAction.fullscreen.title(minimized: false, fullScreen: true) == "退出全屏", "Exit fullscreen is labeled explicitly")

        // State changes after scanning must be checked before pressing anything.
        access.disabled.insert(11)
        expectFailure({ try driver.perform(.close, on: window) }, "Disabled close must be rejected")
        check(access.pressed == [11], "A newly disabled close does not press or fall back")
        access.buttons[.zoom] = nil
        access.supportsZoom = false
        expectFailure({ try driver.perform(.zoom, on: window) }, "Missing zoom is unsupported")
        access.settable = false
        expectFailure({ try driver.perform(.minimize, on: window) }, "Read-only minimized state cannot be changed")
        check(access.writes.count == 2, "Unsupported minimize leaves window untouched")
        let unsupported = driver.capabilities(of: window)
        check(!unsupported.close && !unsupported.minimize && !unsupported.zoom, "Unavailable controls render disabled")
        access.stale = true
        expectFailure({ try driver.perform(.close, on: window) }, "Closed window cannot target a replacement window")
        check(access.pressed == [11], "Stale window issues no action")
        access.stale = false
        access.disabled = []
        access.pressFailure = .unavailable
        expectFailure({ try driver.perform(.close, on: window) }, "Timeout is reported without retries")
        check(access.pressed == [11], "Ambiguous close failure is never retried automatically")
        access.buttons[.zoom] = 13
        access.supportsZoom = false
        check(!driver.capabilities(of: window).zoom, "Fullscreen-only controls do not advertise maximize")
        expectFailure({ try driver.perform(.zoom, on: window) }, "Never substitute fullscreen for unavailable zoom")
        check(access.zoomed == [window] && access.pressed == [11], "Unsupported zoom issues no fullscreen press")
        check(WindowControlAction.minimize.title(minimized: true) == "恢复窗口", "Restorable card is labeled correctly")
        let main = CGRect(x: 0, y: 25, width: 1440, height: 825)
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let original = CGRect(x: 100, y: 100, width: 600, height: 450)
        let first = WindowZoomGeometry.plan(current: original, original: nil, maximized: nil, screens: [main, second])!
        check(first.target == main && !first.restoring, "Maximize uses current display's visible work area")
        let restore = WindowZoomGeometry.plan(current: main, original: original, maximized: main, screens: [main, second])!
        check(restore.target == original && restore.restoring, "Second click restores original size and position")
        let onSecond = CGRect(x: -1000, y: 0, width: 700, height: 400)
        check(WindowZoomGeometry.plan(current: onSecond, original: nil, maximized: nil, screens: [main, second])!.target == second,
            "Left and vertically offset monitors use global AX coordinates")
        let manual = WindowZoomGeometry.plan(current: original, original: onSecond, maximized: main, screens: [main, second])!
        check(!manual.restoring && manual.target == main, "Manual resize starts a new maximize cycle")
        let removedDisplay = WindowZoomGeometry.plan(current: main, original: onSecond, maximized: main, screens: [main])!
        check(main.contains(removedDisplay.target), "Disconnected display cannot restore a window off screen")
        check(WindowZoomGeometry.plan(current: original, original: nil, maximized: nil, screens: []) == nil,
            "No display never produces invented geometry")
        print("Passed \(count) exact-window control checks")
    }
}
