import SwiftUI

/// One button shape and control size for library panels, empty states and pickers.
private struct LibraryCapsuleStyle: ButtonStyle {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.workspaceAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label.padding(.horizontal, 14).padding(.vertical, 7)
            .frame(minHeight: 32))
            .clipShape(Capsule()).contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion && preferences.settings.effects != .minimal ? 0.97 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.24, dampingFraction: 0.9), value: configuration.isPressed)
    }
    @ViewBuilder private func surface<Label: View>(_ label: Label) -> some View {
        if prominent {
            label.foregroundStyle(.white).background(accent, in: Capsule())
        } else if preferences.settings.effects.usesGlass {
            label.workspaceGlassSurface(in: Capsule(), clear: preferences.settings.effects == .clearGlass, interactive: true)
        } else {
            label.background(WorkspaceStyle.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

extension View {
    func libraryButton(prominent: Bool = false) -> some View {
        self.font(.system(size: 13, weight: .semibold))
            .buttonStyle(LibraryCapsuleStyle(prominent: prominent)).liquidControlFeedback(in: Capsule())
    }
}

private struct LibraryIconSurface: ViewModifier {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if preferences.settings.effects == .clearGlass {
            content.frame(width: 36, height: 36).clearGlassSurface(in: Circle(), interactive: true)
                .contentShape(Circle())
        } else if preferences.settings.effects == .glass {
            content.frame(width: 36, height: 36).workspaceGlassSurface(in: Circle(), interactive: true)
        } else {
            content.frame(width: 36, height: 36)
                .background {
                    if preferences.settings.effects == .minimal || reduceTransparency { Circle().fill(WorkspaceStyle.surface) }
                    else { Circle().fill(.regularMaterial) }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: contrast == .increased ? 1 : 0.5))
                .clipShape(Circle())
                .contentShape(Circle())
        }
    }
}
extension View {
    func libraryIconSurface() -> some View { modifier(LibraryIconSurface()).liquidControlFeedback(in: Circle()) }
}
private struct LibraryIconPressStyle: ButtonStyle {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && preferences.settings.effects != .minimal ? 0.95 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct LibraryIconButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical).libraryIconSurface()
        }.buttonStyle(LibraryIconPressStyle()).accessibilityLabel(title).help(title)
    }
}
