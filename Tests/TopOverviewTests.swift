import Foundation
import CoreGraphics

@main struct TopOverviewTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ title: String) {
            guard condition() else { fatalError(title) }; count += 1
        }
        let desktop = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let layout = TopOverviewLayout(screen: desktop, topInset: 30)
        check(layout.trigger.width == desktop.width * 0.2 && layout.trigger.midX == desktop.midX, "Exactly central twenty percent triggers")
        check(layout.trigger.maxY == desktop.maxY && layout.trigger.height == 12, "Trigger remains on the upper edge")
        check(layout.panel.maxY == desktop.maxY - 38, "Panel clears the menu bar and leaves breathing room")
        check(abs(layout.panel.height - desktop.height * 0.32) < 0.01, "Default panel uses a readable 32 percent height")
        check(desktop.contains(layout.panel), "Panel stays inside its display")
        check(layout.previewHeight + 88 <= layout.panel.height, "Header, controls, previews and captions all fit")
        let laptop = TopOverviewLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 37, notchInset: 37)
        check(laptop.panel.maxY < 982 - 37 && laptop.trigger.height == 12, "Panel clears the notch while the trigger keeps the configured depth")
        check(laptop.panel.height >= 240 && laptop.previewHeight >= 152, "Compact screens retain readable content")
        check(laptop.cardWidth >= 168, "Each card retains room for separate 28pt controls")
        let upper = CGRect(x: -1920, y: 1440, width: 1920, height: 1080)
        let secondary = TopOverviewLayout(screen: upper, topInset: 0)
        check(secondary.trigger.midX == -960 && secondary.trigger.maxY == 2520, "Negative and vertically offset display coordinates work")
        check(upper.contains(secondary.panel) && secondary.panel.width == upper.width - 32, "Secondary panel uses that display's dimensions")
        let left = TopOverviewLayout(screen: desktop, topInset: 30, position: .left, widthPercent: 40, triggerDepth: 24)
        check(left.trigger.minX == desktop.minX && left.trigger.width == 1024 && left.trigger.height == 24, "Left trigger uses adjustable width and depth")
        let right = TopOverviewLayout(screen: upper, topInset: 0, position: .right, widthPercent: 50, triggerDepth: 8)
        check(right.trigger.maxX == upper.maxX && right.trigger.width == 960, "Right trigger supports negative screen coordinates")
        let entire = TopOverviewLayout(screen: desktop, topInset: 30, position: .right, widthPercent: 1000, triggerDepth: 1000)
        check(entire.trigger.width == desktop.width && entire.trigger.height == 64, "Invalid oversized trigger is clamped to the display")
        check(left.panel == layout.panel, "Trigger adjustments never move or resize the visible strip")

        for screen in [desktop, upper] {
            for position in TopOverviewPosition.allCases {
                for width: Double in [10, 30, 75, 100] {
                    let region = TopOverviewLayout(screen: screen, topInset: 38, notchInset: 38,
                        position: position, widthPercent: width, triggerDepth: 8)
                    check(region.trigger.height == 8, "Notch minimum silently expands the user's selected depth")
                    check(region.containsTrigger(CGPoint(x: region.trigger.minX, y: screen.maxY)), "Left/top closed boundary does not trigger")
                    check(region.containsTrigger(CGPoint(x: region.trigger.maxX, y: screen.maxY)), "Right/top closed boundary does not trigger")
                    check(!region.containsTrigger(CGPoint(x: region.trigger.minX - 0.01, y: screen.maxY)), "Outside-left top edge bypasses the region")
                    check(!region.containsTrigger(CGPoint(x: region.trigger.maxX + 0.01, y: screen.maxY)), "Outside-right top edge bypasses the region")
                    check(!region.containsTrigger(CGPoint(x: region.trigger.midX, y: region.trigger.minY - 0.01)), "Pointer below the configured depth triggers")
                }
            }
        }

        for size in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 720),
                     CGSize(width: 1366, height: 768), CGSize(width: 1512, height: 982),
                     CGSize(width: 2560, height: 1440)] {
            let screen = CGRect(origin: CGPoint(x: -120, y: 90), size: size)
            let compact = TopOverviewLayout(screen: screen, topInset: 38)
            check(screen.contains(compact.panel), "Small-screen panel must stay on its display")
            check(compact.previewHeight >= 100, "Preview collapsed into a narrow strip on a laptop")
            check(compact.cardWidth >= 220, "Card controls and title need a readable minimum width")
            for percent: Double in [24, 32, 40, 55] {
                let customSize = TopOverviewLayout(screen: screen, topInset: 38, heightPercent: percent)
                check(customSize.panel.maxY == compact.panel.maxY, "Resizing must keep the panel anchored below the menu bar")
                check(screen.contains(customSize.panel), "Custom panel height escaped its screen")
                check(customSize.previewHeight + 88 <= customSize.panel.height, "Resized cards overlap header or captions")
                check(customSize.cardWidth <= customSize.panel.width - 36, "Resized card cannot fit inside the panel")
            }
        }
        let taller = TopOverviewLayout(screen: desktop, topInset: 30, heightPercent: 55)
        check(taller.panel.height > layout.panel.height && taller.previewHeight > layout.previewHeight,
            "Height setting must enlarge previews as well as the panel")
        let huge = TopOverviewLayout(screen: CGRect(x: 0, y: 0, width: 800, height: 400), topInset: 38, heightPercent: 500)
        check(huge.panel.maxY == 354 && huge.panel.minY >= 0 && huge.previewHeight > 0,
            "Oversized height settings must respect the usable display")
        let defaults = AppearanceSettings()
        let oldHeight = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{}".utf8)).topOverviewHeightPercent
        check(defaults.topOverviewHeightPercent == 32 && oldHeight == 32, "Upgrades and new installs need the readable default")
        let clamped = try JSONDecoder().decode(AppearanceSettings.self,
            from: Data("{\"topOverviewHeightPercent\":200}".utf8))
        check(clamped.topOverviewHeightPercent == 55, "Saved height exceeds the supported range")
        let short = try JSONDecoder().decode(AppearanceSettings.self,
            from: Data("{\"topOverviewHeightPercent\":-1}".utf8))
        check(short.topOverviewHeightPercent == 5, "Saved height can shrink the panel too far")

        for height: CGFloat in [640, 768, 982, 1080, 1440] {
            let screen = CGRect(x: -100, y: 50, width: 1280, height: height)
            for percent: Double in [5, 8, 9, 9.99] {
                let small = TopOverviewLayout(screen: screen, topInset: 38, heightPercent: percent)
                check(small.iconsOnly && small.previewHeight == 0, "Sub-ten-percent mode still has thumbnail space")
                check(small.panel.height < screen.height * 0.1, "The old minimum height prevents a compact strip")
                check(small.panel.height >= 44 && screen.contains(small.panel), "Compact controls escaped their display")
                check(small.panel.maxY == screen.maxY - 46, "Compact mode moved the anchored top edge")
            }
        }
        let ten = TopOverviewLayout(screen: desktop, topInset: 30, heightPercent: 10)
        check(!ten.iconsOnly && ten.previewHeight > 0, "The ten-percent boundary should allow previews when they fit")
        let constrained = TopOverviewLayout(screen: CGRect(x: 0, y: 0, width: 1024, height: 640), topInset: 30, heightPercent: 10)
        check(constrained.iconsOnly, "A short display must not squeeze controls into a tiny thumbnail")
        let savedCompact = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{\"topOverviewHeightPercent\":8}".utf8))
        check(savedCompact.topOverviewHeightPercent == 8, "Upgrade loading clamps a compact height back to the old minimum")

        let expandedWidth = TopOverviewLayout.iconCardWidth(available: 2400, count: 5)
        check(expandedWidth == 300, "Compact cards exceed the comfortable width cap")
        for available: CGFloat in [700, 1280, 2400, 5000] {
            check(TopOverviewLayout.iconCardWidth(available: available, count: 1) == 300,
                "One window stretches across the entire display")
            check(TopOverviewLayout.iconCardWidth(available: available, count: 2) == 300,
                "Two windows stretch when filtering applications")
        }
        check(TopOverviewLayout.iconCardWidth(available: 600, count: 10) == 190,
            "Overflow must scroll readable cards instead of crushing titles")
        var hover = TopOverviewHover()
        func tick(_ trigger: String?, _ time: Double, inside: Bool = false, drag: Bool = false, menu: Bool = false) -> TopOverviewHover.Event {
            hover.update(trigger: trigger, insidePanel: inside, dragging: drag, interacting: menu, time: time)
        }
        check(tick("A", 0) == .none, "Entering does not immediately open")
        check(tick("A", 0.20) == .none, "Short incidental hover is ignored")
        check(tick(nil, 0.25) == .none, "A boundary wobble starts grace rather than throwing away dwell")
        check(tick("A", 0.30) == .none && tick("A", 0.35) == .none, "Reentry within grace preserves original dwell")
        check(tick("A", 0.37) == .show("A") && hover.screenID == "A", "Sustained hover opens on the matching screen")
        check(tick(nil, 0.70) == .none, "Pointer can bridge the menu-to-panel gap")
        check(tick(nil, 0.90, inside: true) == .none, "Entering panel cancels dismissal")
        check(tick(nil, 1.00) == .none && tick(nil, 1.30, inside: true) == .none, "Brief exits do not flicker")
        check(tick(nil, 1.40) == .none && tick(nil, 2.00) == .hide, "Sustained exit closes after grace")
        hover.reveal(on: "A")
        check(tick(nil, 3.0, menu: true) == .none && tick(nil, 4.0, menu: true) == .none, "Context-menu tracking keeps the panel open")
        check(tick(nil, 4.1) == .none && tick(nil, 4.7) == .hide, "Panel closes normally after a menu finishes")
        hover.dismiss()
        check(tick("A", 5) == .none && tick("A", 7) == .none, "Explicit dismissal cannot immediately reopen under the pointer")
        _ = tick(nil, 7.1)
        _ = tick("A", 7.2)
        check(tick("A", 7.6) == .show("A"), "Leaving rearms explicit dismissal")
        check(tick("B", 8) == .none && tick("B", 8.6) == .hide, "Changing display closes the old panel before moving it")
        _ = tick("B", 8.7)
        check(tick("B", 9.1) == .show("B"), "New display can open without a second pointer exit")
        check(tick(nil, 9.2, drag: true) == .hide, "Dragging outside dismisses immediately")
        check(tick("B", 10, drag: true) == .none && tick("B", 11, drag: true) == .none, "Dragging files cannot open the overlay")
        _ = tick("B", 11.1)
        check(tick("B", 11.5) == .show("B"), "Release starts a new hover rather than opening during drag")
        hover.reset()
        check(tick("A", 12, menu: true) == .none && tick("A", 13, menu: true) == .none, "Existing menus do not trigger an overlay")
        hover.reveal(on: "A"); hover.dismiss(); hover.reset()
        _ = tick("B", 14)
        check(tick("B", 14.4) == .show("B"), "Disable/re-enable clears obsolete timing and display state")

        let legacy = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{\"version\":1,\"previewsEnabled\":false}".utf8))
        check(!legacy.topOverviewEnabled && !legacy.previewsEnabled, "Old preferences keep thumbnails off and new hover off")
        var settings = legacy
        settings.topOverviewEnabled = true
        let restored = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(settings))
        check(restored == settings && restored.topOverviewEnabled, "Hover opt-in persists without changing other preferences")
        check(!AppearanceSettings().topOverviewEnabled, "New installations require explicit opt-in")
        check(AppearanceSettings().topOverviewDelay == 0.2, "Default trigger is shortened to 0.2 seconds")
        var instant = TopOverviewHover(dwell: 0)
        check(instant.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0) == .show("A"), "Zero delay opens on entry")
        var fast = TopOverviewHover(dwell: 0.2)
        _ = fast.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0)
        check(fast.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0.15) == .none,
            "Custom delay is respected before its deadline")
        check(fast.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0.21) == .show("A"),
            "Custom delay opens as soon as it elapses")
        fast.reset()
        check(fast.dwellDuration == 0.2, "Reset keeps the user's chosen delay")
        let invalid = try JSONDecoder().decode(AppearanceSettings.self,
            from: Data("{\"topOverviewWidthPercent\":-20,\"topOverviewDepth\":10000,\"topOverviewDelay\":-5}".utf8))
        check(invalid.topOverviewWidthPercent == 10 && invalid.topOverviewDepth == 64 && invalid.topOverviewDelay == 0,
            "Persisted out-of-range parameters are safely clamped")
        settings.topOverviewPosition = .right
        settings.topOverviewWidthPercent = 45
        settings.topOverviewDepth = 24
        settings.topOverviewDelay = 0.05
        settings.topOverviewHeightPercent = 45
        let custom = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(settings))
        check(custom == settings, "Custom region and delay round-trip together")
        var jitter = TopOverviewHover(dwell: 0.2)
        _ = jitter.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0)
        _ = jitter.update(trigger: nil, insidePanel: false, dragging: false, interacting: false, time: 0.1)
        _ = jitter.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0.15)
        check(jitter.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 0.21) == .show("A"),
            "Boundary jitter cannot perpetually restart the opening delay")
        jitter.reset()
        _ = jitter.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 1)
        _ = jitter.update(trigger: nil, insidePanel: false, dragging: false, interacting: false, time: 1.05)
        _ = jitter.update(trigger: nil, insidePanel: false, dragging: false, interacting: false, time: 1.16)
        check(jitter.update(trigger: "A", insidePanel: false, dragging: false, interacting: false, time: 1.2) == .none,
            "A deliberate exit beyond boundary grace still cancels the opening")
        for cycle in 0..<50 {
            let time = Double(cycle) * 2 + 20
            hover.reveal(on: "A")
            hover.dismiss()
            _ = tick(nil, time + 0.001)
            _ = tick("A", time + 0.01)
            check(tick("A", time + 0.4) == .show("A"), "Rapid exit/reentry \(cycle) must rearm after explicit close")
            _ = tick(nil, time + 0.5)
            check(tick(nil, time + 1.1) == .hide, "Automatic close \(cycle) must finish and permit the next cycle")
        }
        print("Passed \(count) top overview geometry, hover and preference checks")
    }
}
