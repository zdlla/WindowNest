import SwiftUI

/// Animate the rendered control without changing its layout slot or neighbors.
private struct LiquidControlFeedback<S: InsettableShape>: ViewModifier {
    let shape: S
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @LocalState private var hovered = false
    private var active: Bool { hovered && enabled && preferences.settings.effects.usesGlass }
    func body(content: Content) -> some View {
        content
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .white.opacity(0.20)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                .opacity(active ? 1 : 0).allowsHitTesting(false))
            .brightness(active ? 0.025 : 0)
            .shadow(color: .black.opacity(active ? 0.10 : 0), radius: active ? 7 : 0, y: active ? 3 : 0)
            .scaleEffect(active && !reduceMotion ? 1.025 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.30, dampingFraction: 0.94), value: active)
            .onHover { hovered = $0 }
    }
}
extension View {
    func liquidControlFeedback<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidControlFeedback(shape: shape))
    }
}
