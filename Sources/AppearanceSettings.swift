import Foundation
import CoreGraphics

enum ThemeAccent: String, Codable, CaseIterable, Identifiable {
    case system, blue, purple, pink, orange, green
    var id: String { rawValue }
    var title: String { switch self {
    case .system: return "跟随系统"; case .blue: return "海蓝"; case .purple: return "鸢紫"
    case .pink: return "玫红"; case .orange: return "暖橙"; case .green: return "苔绿"
    } }
}
enum ThemeAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}
enum WorkspaceEffects: String, Codable, CaseIterable, Identifiable {
    case glass, clearGlass, soft, minimal
    var id: String { rawValue }
    var title: String { switch self { case .glass: return "通透"; case .clearGlass: return "透明玻璃"; case .soft: return "柔和"; case .minimal: return "简洁" } }
    var usesGlass: Bool { self == .glass || self == .clearGlass }
    var detail: String { switch self {
    case .glass: return "玻璃材质、背景柔焦与轻盈缩放"
    case .clearGlass: return "透明液态玻璃、透光边缘与轻盈的悬浮面板"
    case .soft: return "克制的材质、柔和缩放与依次出现"
    case .minimal: return "不透明面板与短淡入淡出"
    } }
}
enum TopOverviewPosition: String, Codable, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var title: String { switch self { case .left: return "左侧"; case .center: return "中央"; case .right: return "右侧" } }
}

struct AppearanceSettings: Codable, Equatable {
    var version = 1
    var accent: ThemeAccent = .system
    var appearance: ThemeAppearance = .system
    var effects: WorkspaceEffects = .soft
    var previewsEnabled = true
    var topOverviewEnabled = false
    var topOverviewPosition: TopOverviewPosition = .center
    var topOverviewWidthPercent: Double = 20
    var topOverviewDepth: Double = 12
    var topOverviewDelay: Double = 0.2
    var topOverviewHeightPercent: Double = 32
    var globalShortcutEnabled = false
    var globalShortcut: GlobalShortcut?
    var shortcutSingleKey: ShortcutSingleKey?
    var commandControlShortcutEnabled = false
    // Retained solely to round-trip old preferences. Hit testing now always
    // respects the configured rectangle, including its exact upper boundary.
    var topOverviewEdgeTrigger = true
    init() {}
    private enum CodingKeys: String, CodingKey {
        case version, accent, appearance, effects, previewsEnabled, topOverviewEnabled
        case topOverviewPosition, topOverviewWidthPercent, topOverviewDepth, topOverviewDelay, topOverviewHeightPercent
        case globalShortcutEnabled, globalShortcut, shortcutSingleKey, topOverviewEdgeTrigger
        case commandControlShortcutEnabled
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        accent = try c.decodeIfPresent(ThemeAccent.self, forKey: .accent) ?? .system
        appearance = try c.decodeIfPresent(ThemeAppearance.self, forKey: .appearance) ?? .system
        effects = try c.decodeIfPresent(WorkspaceEffects.self, forKey: .effects) ?? .soft
        previewsEnabled = try c.decodeIfPresent(Bool.self, forKey: .previewsEnabled) ?? true
        topOverviewEnabled = try c.decodeIfPresent(Bool.self, forKey: .topOverviewEnabled) ?? false
        topOverviewPosition = try c.decodeIfPresent(TopOverviewPosition.self, forKey: .topOverviewPosition) ?? .center
        topOverviewWidthPercent = min(100, max(10, try c.decodeIfPresent(Double.self, forKey: .topOverviewWidthPercent) ?? 20))
        topOverviewDepth = min(64, max(4, try c.decodeIfPresent(Double.self, forKey: .topOverviewDepth) ?? 12))
        topOverviewDelay = min(1.5, max(0, try c.decodeIfPresent(Double.self, forKey: .topOverviewDelay) ?? 0.2))
        topOverviewHeightPercent = min(55, max(5, try c.decodeIfPresent(Double.self, forKey: .topOverviewHeightPercent) ?? 32))
        globalShortcut = try c.decodeIfPresent(GlobalShortcut.self, forKey: .globalShortcut)
        if globalShortcut?.isValid == false { globalShortcut = nil }
        shortcutSingleKey = try c.decodeIfPresent(ShortcutSingleKey.self, forKey: .shortcutSingleKey)
        commandControlShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandControlShortcutEnabled) ?? false
        globalShortcutEnabled = (try c.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? false) && (globalShortcut != nil || shortcutSingleKey != nil || commandControlShortcutEnabled)
        topOverviewEdgeTrigger = try c.decodeIfPresent(Bool.self, forKey: .topOverviewEdgeTrigger) ?? true
    }
}
struct AppearanceRepository {
    let url: URL
    static var standard: Self {
        Self(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowNest/preferences.json"))
    }
    func load() throws -> AppearanceSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppearanceSettings() }
        return try JSONDecoder().decode(AppearanceSettings.self, from: Data(contentsOf: url))
    }
    func save(_ value: AppearanceSettings) throws {
        let data = try JSONEncoder().encode(value)
        try PrivateStorage.write(data, to: url)
    }
}

/// Motion only changes opacity and a scale around the existing center; no icon
/// or grid slot is interpolated between unrelated collapsed/expanded layouts.
struct FolderMotionPlan {
    let reduced: Bool
    let effects: WorkspaceEffects
    var simple: Bool { reduced || effects == .minimal }
    var panelScale: Double { simple ? 1 : effects.usesGlass ? 0.94 : 0.965 }
    var itemScale: Double { simple ? 1 : 0.88 }
    var removalDelay: Double { simple ? 0.14 : 0.46 }
    func itemDelay(index: Int, count: Int, entering: Bool) -> Double {
        guard !simple else { return 0 }
        let rank = entering ? index : max(0, count - 1 - index)
        return (entering ? 0.055 : 0) + Double(min(12, max(0, rank))) * (entering ? 0.018 : 0.012)
    }
}

struct FolderBlankClickPolicy {
    static func dismiss(down: CGPoint, up: CGPoint, bounds: CGRect, protected: [CGRect], dragged: Bool) -> Bool {
        !dragged && bounds.contains(down) && bounds.contains(up)
            && hypot(up.x - down.x, up.y - down.y) <= 4
            && !protected.contains(where: { $0.contains(down) || $0.contains(up) })
    }
}
