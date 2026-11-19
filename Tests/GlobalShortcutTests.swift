import Foundation

@main struct GlobalShortcutTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let c = GlobalShortcut.command, t = GlobalShortcut.control, o = GlobalShortcut.option, s = GlobalShortcut.shift
        check(GlobalShortcut.suggested.isValid && !GlobalShortcut.suggested.isReserved, "Suggested chord violates policy")
        check(GlobalShortcut.suggested.display == "⌃⌥⌘空格", "Modifier display order is inconsistent")
        for modifiers in [UInt32(0), c, s, o, t] {
            check(!GlobalShortcut(keyCode: 0, modifiers: modifiers, keyLabel: "A").isValid, "Plain/common typing could become a global shortcut")
        }
        for modifiers in [c|o,c|t,o|t,c|s] {
            check(GlobalShortcut(keyCode: 0, modifiers: modifiers, keyLabel: "A").isValid, "A valid two-modifier chord was rejected")
        }
        for (key, modifiers): (UInt16, UInt32) in [(49,c),(49,c|o),(49,t),(49,t|o),(49,t|c),(12,t|c),(53,c|o),(48,c|s)] {
            check(GlobalShortcut(keyCode: key, modifiers: modifiers, keyLabel: "key").isReserved, "An OS navigation or privacy shortcut was not protected")
        }
        check(!GlobalShortcut(keyCode: 150, modifiers: c|o, keyLabel: "X").isValid, "Out-of-range key accepted")
        check(!GlobalShortcut(keyCode: 0, modifiers: c|o|(1<<30), keyLabel: "X").isValid, "Unsupported modifier accepted")
        let old = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{\"version\":1,\"effects\":\"glass\"}".utf8))
        check(!old.globalShortcutEnabled && old.globalShortcut == nil && old.effects == .glass, "Upgrade enabled an unchecked shortcut or reset appearance")
        var settings = old; settings.globalShortcut = .suggested; settings.globalShortcutEnabled = true
        let roundTrip = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(settings))
        check(roundTrip == settings, "Custom shortcut did not survive settings persistence")
        let invalid = Data("{\"version\":1,\"globalShortcutEnabled\":true,\"globalShortcut\":{\"keyCode\":255,\"modifiers\":768,\"keyLabel\":\"X\"}}".utf8)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: invalid)
        check(!decoded.globalShortcutEnabled && decoded.globalShortcut == nil, "Malformed stored shortcut became active")
        var single = AppearanceSettings(); single.shortcutSingleKey = .rightOption; single.globalShortcutEnabled = true
        let singleRoundTrip = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(single))
        check(singleRoundTrip.globalShortcutEnabled && singleRoundTrip.shortcutSingleKey == .rightOption, "Bare-key mode did not persist")
        var tap = SingleKeyTap()
        check(!tap.update(down: true, onlyModifier: true, time: 1), "Press fired before release")
        check(tap.update(down: false, onlyModifier: true, time: 1.1), "Short bare tap did not fire")
        check(!tap.update(down: false, onlyModifier: true, time: 1.11), "One tap fired twice")
        _ = tap.update(down: true, onlyModifier: true, time: 2); tap.cancelChord()
        check(!tap.update(down: false, onlyModifier: true, time: 2.1), "Option typing or clicking opened the window")
        _ = tap.update(down: true, onlyModifier: true, time: 3)
        check(!tap.update(down: false, onlyModifier: true, time: 3.8), "Long modifier hold fired")
        _ = tap.update(down: true, onlyModifier: false, time: 4)
        check(!tap.update(down: false, onlyModifier: true, time: 4.1), "Another held modifier was ignored")
        var chordTap = CommandControlTap()
        check(!chordTap.update(modifiers: c, time: 10), "Command alone fired the chord")
        check(!chordTap.update(modifiers: c|t, time: 10.1), "Chord fired before release")
        check(!chordTap.update(modifiers: t, time: 10.2), "Chord fired while Control was still held")
        check(chordTap.update(modifiers: 0, time: 10.3), "Bare Command-Control did not fire on full release")
        check(!chordTap.update(modifiers: 0, time: 10.4), "Chord fired twice")
        _ = chordTap.update(modifiers: c|t, time: 11); chordTap.cancelChord()
        check(!chordTap.update(modifiers: 0, time: 11.1), "Command-Control typing/clicking was swallowed")
        _ = chordTap.update(modifiers: t, time: 12); chordTap.cancelChord()
        _ = chordTap.update(modifiers: c|t, time: 12.1)
        check(!chordTap.update(modifiers: 0, time: 12.2), "A prior shortcut became a bare chord")
        _ = chordTap.update(modifiers: c|t|s, time: 13)
        _ = chordTap.update(modifiers: c|t, time: 13.1)
        check(!chordTap.update(modifiers: 0, time: 13.2), "Three-modifier chord accidentally triggered")
        _ = chordTap.update(modifiers: c|t, time: 14)
        check(!chordTap.update(modifiers: 0, time: 15), "Long modifier hold fired")
        _ = chordTap.update(modifiers: t, time: 16)
        _ = chordTap.update(modifiers: c|t, time: 16.1)
        check(chordTap.update(modifiers: 0, time: 16.2), "Control-first ordering did not work")
        single.commandControlShortcutEnabled = true
        let both = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(single))
        check(both.commandControlShortcutEnabled && both.shortcutSingleKey == .rightOption,
            "Command-Control replaced the right Option setting")
        let layout = TopOverviewLayout(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), topInset: 38)
        for x: CGFloat in [layout.trigger.minX, layout.trigger.midX, layout.trigger.maxX] {
            check(layout.containsTrigger(CGPoint(x: x, y: 900)), "Configured exact upper boundary was excluded")
            check(layout.containsTrigger(CGPoint(x: x, y: 898)), "Fast approach inside the selected region missed the trigger")
        }
        for x: CGFloat in [0, 1, 400, 1439, 1440] {
            check(!layout.containsTrigger(CGPoint(x: x, y: 900)), "Legacy full-edge shortcut bypassed the user's selected region")
        }
        check(!layout.containsTrigger(CGPoint(x: -1, y: 900)), "Trigger extended to another screen")
        check(!layout.containsTrigger(CGPoint(x: 720, y: 901)), "Trigger extended above the display")
        print("Passed \(checks) global-shortcut policy and settings checks")
    }
}
