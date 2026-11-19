import SwiftUI

/// Apply glass to the complete content so the system can adapt its foreground
/// and edges, instead of placing an unrelated translucent layer behind it.
private struct WorkspaceGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let clear: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if reduceTransparency || contrast == .increased {
                content.background(WorkspaceStyle.surface, in: shape)
            } else if #available(macOS 26, *) {
                content.background(WorkspaceStyle.surface.opacity(clear ? 0.08 : 0.22), in: shape)
                    .glassEffect(clear ? .clear.interactive(interactive) : .regular.interactive(interactive), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
                    .background(WorkspaceStyle.surface.opacity(clear ? 0.08 : 0.22), in: shape)
            }
        }
        // Native material rendering can differ between macOS releases. The app
        // owns the final silhouette, including the reduced-transparency path.
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.12),
            lineWidth: contrast == .increased ? 1 : 0.5).allowsHitTesting(false))
        .contentShape(shape)
    }
}
extension View {
    func clearGlassSurface<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        workspaceGlassSurface(in: shape, clear: true, interactive: interactive)
    }
    func workspaceGlassSurface<S: InsettableShape>(in shape: S, clear: Bool = false, interactive: Bool = false) -> some View {
        modifier(WorkspaceGlassSurface(shape: shape, interactive: interactive, clear: clear))
    }
    func workspacePanelSurface(radius: CGFloat) -> some View { modifier(WorkspacePanelSurface(radius: radius)) }
    func topOverviewPanelSurface(radius: CGFloat) -> some View { modifier(TopOverviewPanelSurface(radius: radius)) }
}

/// A floating window switcher needs stronger separation than an in-app sheet.
/// One material, a stable tinted backing, and static edges; no backdrop capture.
private struct TopOverviewPanelSurface: ViewModifier {
    let radius: CGFloat
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if reduceTransparency || contrast == .increased || preferences.settings.effects == .minimal {
                shape.fill(Color(nsColor: WorkspaceColors.overview))
            } else {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(Color(nsColor: WorkspaceColors.overview).opacity(scheme == .dark ? 0.90 : 0.92)))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.65 : scheme == .dark ? 0.34 : 0.24),
            lineWidth: contrast == .increased ? 1.5 : 1).allowsHitTesting(false))
        .overlay(shape.inset(by: 1).strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.80), lineWidth: 0.5)
            .allowsHitTesting(false))
    }
}
private struct WorkspacePanelSurface: ViewModifier {
    let radius: CGFloat
    @EnvironmentObject private var preferences: AppearanceStore
    @ViewBuilder func body(content: Content) -> some View {
        if preferences.settings.effects == .clearGlass {
            content.clearGlassSurface(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(FolderSurface(radius: radius, panelBorder: true))
        }
    }
}
