import Foundation

/// Bounded, event-driven feedback. No clock, cursor polling or layout mutation.
struct InteractionMotion {
    enum Role: CaseIterable { case icon, preview, control }
    let scale: Double
    let lift: Double

    init(role: Role, hovered: Bool, pressed: Bool, enabled: Bool, simple: Bool) {
        guard enabled && !simple else { scale = 1; lift = 0; return }
        switch role {
        case .icon:
            scale = pressed ? 0.95 : hovered ? 1.055 : 1
            lift = hovered && !pressed ? -2 : 0
        case .preview:
            scale = pressed ? 0.99 : hovered ? 1.012 : 1
            lift = 0
        case .control:
            scale = pressed ? 0.97 : hovered ? 1.025 : 1
            lift = 0
        }
    }

    static func filterDirection(from: String?, to: String?, order: [String]) -> Double {
        func index(_ id: String?) -> Int {
            guard let id else { return 0 }
            return order.firstIndex(of: id).map { $0 + 1 } ?? 1
        }
        return index(to) < index(from) ? -1 : 1
    }
}
