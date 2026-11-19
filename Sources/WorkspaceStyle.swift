import SwiftUI
import AppKit

/// Shared visual roles; each workspace retains its own structure and interaction.
enum WorkspaceStyle {
    static let gutter: CGFloat = 32
    static let gap: CGFloat = 24
    static let sectionGap: CGFloat = 28
    static let canvas = Color(nsColor: WorkspaceColors.canvas)
    static let surface = Color(nsColor: WorkspaceColors.surface)
    static let chrome = Color(nsColor: WorkspaceColors.chrome)
    static let secondary = Color(nsColor: .labelColor).opacity(0.72)
    static let action = Color(nsColor: .linkColor)
    static let title = Font.system(size: 28, weight: .semibold)
    static let section = Font.system(size: 18, weight: .semibold)
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(WorkspaceStyle.title)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceSearchSurface: ViewModifier {
    @Environment(\.workspaceAccent) private var accent
    @EnvironmentObject private var preferences: AppearanceStore
    let focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if preferences.settings.effects == .clearGlass {
                content.clearGlassSurface(in: Capsule())
            } else {
                content.background(WorkspaceStyle.surface, in: Capsule())
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: contrast == .increased ? 1 : 0.5).allowsHitTesting(false))
        .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: contrast == .increased ? 3 : 2.5)
            .padding(-3).opacity(focused ? 1 : 0).allowsHitTesting(false))
        .animation(.easeOut(duration: 0.14), value: focused)
    }
}

extension View {
    func workspaceSearchSurface(focused: Bool) -> some View { modifier(WorkspaceSearchSurface(focused: focused)) }
}
