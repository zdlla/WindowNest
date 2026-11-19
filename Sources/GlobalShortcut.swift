import Foundation

enum ShortcutSingleKey: String, Codable, CaseIterable, Identifiable {
    case rightOption, rightCommand
    var id: String { rawValue }
    var keyCode: UInt16 { self == .rightOption ? 61 : 54 }
    var title: String { self == .rightOption ? "右侧 Option（⌥）单按" : "右侧 Command（⌘）单按" }
    var modifier: UInt32 { self == .rightOption ? GlobalShortcut.option : GlobalShortcut.command }
}

/// A bare short tap only. Any chord, typing, click or long hold cancels it.
struct SingleKeyTap {
    private var started: TimeInterval?
    private var used = false
    var isDown: Bool { started != nil }
    mutating func cancelChord() { if started != nil { used = true } }
    mutating func reset() { started = nil; used = false }
    mutating func update(down: Bool, onlyModifier: Bool, time: TimeInterval) -> Bool {
        if down {
            if started == nil { started = time; used = !onlyModifier }
            else if !onlyModifier { used = true }
            return false
        }
        defer { reset() }
        guard let started else { return false }
        return !used && onlyModifier && time >= started && time - started <= 0.45
    }
}

/// Both modifiers must form a bare chord, then fully release. Ordinary
/// Command-Control shortcuts cancel the attempt and retain their normal input.
struct CommandControlTap {
    private var started: TimeInterval?
    private var used = false
    mutating func reset() { started = nil; used = false }
    mutating func cancelChord() { used = true }
    mutating func update(modifiers: UInt32, time: TimeInterval) -> Bool {
        let chord = GlobalShortcut.command | GlobalShortcut.control
        if modifiers == 0 {
            defer { reset() }
            guard let started else { return false }
            return !used && time >= started && time - started <= 0.65
        }
        if modifiers & ~chord != 0 { used = true }
        if modifiers == chord && started == nil && !used { started = time }
        return false
    }
}

struct GlobalShortcut: Codable, Equatable {
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12
    static let mask = command | shift | option | control
    static let suggested = GlobalShortcut(keyCode: 49, modifiers: command | option | control, keyLabel: "空格")
    let keyCode: UInt16
    let modifiers: UInt32
    let keyLabel: String
    var display: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
    }
    var isValid: Bool {
        keyCode < 128 && modifiers & ~Self.mask == 0 && modifiers.nonzeroBitCount >= 2
            && modifiers & (Self.command | Self.control | Self.option) != 0
            && !keyLabel.isEmpty && keyLabel.count <= 16
    }
    var isReserved: Bool {
        let c = Self.command, o = Self.option, t = Self.control
        // Core OS navigation, Spotlight/Finder search, input source and lock.
        let reserved: [(UInt16, UInt32)] = [(49,c),(49,c|o),(49,t),(49,t|o),(49,t|c),
            (48,c),(48,c|Self.shift),(50,c),(50,c|Self.shift),(12,t|c),
            (53,c|o),(126,t),(125,t),(123,t),(124,t)]
        return reserved.contains { $0.0 == keyCode && $0.1 == modifiers }
    }
}
