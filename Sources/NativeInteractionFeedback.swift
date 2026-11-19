import SwiftUI

private typealias FeedbackState<Value> = SwiftUI.State<Value>

private struct NativePressedKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var nativePressed: Bool {
        get { self[NativePressedKey.self] }
        set { self[NativePressedKey.self] = newValue }
    }
}

/// Pass press state down to the icon; its caption and hit region stay fixed.
struct NativePressStyle: ButtonStyle {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    var scaleLabel = false
    func makeBody(configuration: Configuration) -> some View {
        let motion = InteractionMotion(role: .control, hovered: false, pressed: configuration.isPressed,
            enabled: enabled, simple: reduceMotion || preferences.settings.effects == .minimal)
        configuration.label.environment(\.nativePressed, configuration.isPressed && enabled)
            .opacity(configuration.isPressed && enabled ? 0.9 : 1)
            .scaleEffect(scaleLabel ? motion.scale : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct NativeIconFeedback: ViewModifier {
    @EnvironmentObject private var preferences: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.nativePressed) private var pressed
    let hovered: Bool
    let role: InteractionMotion.Role
    func body(content: Content) -> some View {
        let simple = reduceMotion || preferences.settings.effects == .minimal
        let motion = InteractionMotion(role: role, hovered: hovered, pressed: pressed, enabled: enabled, simple: simple)
        content.scaleEffect(motion.scale).offset(y: motion.lift)
            .animation(simple ? nil : .spring(response: 0.28, dampingFraction: 0.92), value: hovered)
            .animation(simple ? nil : .spring(response: 0.22, dampingFraction: 0.95), value: pressed)
            .animation(nil, value: simple)
    }
}

private struct NativeHoverFeedback<S: InsettableShape>: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FeedbackState private var hovered = false
    let shape: S
    let selected: Bool
    func body(content: Content) -> some View {
        content.background(shape.fill(.primary.opacity(hovered && enabled && !selected ? 0.055 : 0)))
            .overlay(shape.strokeBorder(.primary.opacity(hovered && enabled && contrast == .increased ? 0.45 : 0), lineWidth: 1)
                .allowsHitTesting(false))
            .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func nativeIconFeedback(hovered: Bool, role: InteractionMotion.Role = .icon) -> some View {
        modifier(NativeIconFeedback(hovered: hovered, role: role))
    }
    func nativeHoverFeedback<S: InsettableShape>(in shape: S, selected: Bool = false) -> some View {
        modifier(NativeHoverFeedback(shape: shape, selected: selected))
    }
}
