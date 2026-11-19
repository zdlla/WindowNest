import AppKit

/// Content colors belong to the app, rather than OS-specific under-page and
/// control materials. Dynamic providers still follow the chosen light/dark mode.
enum WorkspaceColors {
    static let canvas = adaptive("Canvas", light: 0xFFFFFF, dark: 0x242424)
    static let surface = adaptive("Surface", light: 0xFFFFFF, dark: 0x303030)
    static let chrome = adaptive("Chrome", light: 0xF5F5F7, dark: 0x333335)
    static let overview = adaptive("Overview", light: 0xE5EAF1, dark: 0x282F3A)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("WindowNest.\(name)")) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}
