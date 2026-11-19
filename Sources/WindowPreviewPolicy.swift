import Foundation
import Combine

@MainActor final class WindowPreviewUpdates: ObservableObject {
    @Published var revision = 0
}

enum WindowPreviewSurface { case main, overview }

enum WindowPreviewBudget {
    static let maxCount = 18
    static let maxBytes = 12 * 1024 * 1024
    static let maxWidth = 480.0
    static let maxHeight = 300.0
    static let interval: TimeInterval = 8

    static func requested(_ orderedIDs: [UUID], main: Set<UUID>, overview: Set<UUID>,
                          mainVisible: Bool, overviewVisible: Bool, overviewAllowsPreviews: Bool = true) -> Set<UUID> {
        let top = overviewVisible && overviewAllowsPreviews ? overview : []
        let main = mainVisible ? main : []
        let prioritized = orderedIDs.filter { top.contains($0) } + orderedIDs.filter { main.contains($0) && !top.contains($0) }
        return Set(prioritized.prefix(maxCount))
    }

    static func due(_ ids: [UUID], demand: Set<UUID>, attempted: [UUID: TimeInterval], now: TimeInterval) -> [UUID] {
        Array(ids.filter { demand.contains($0) && now - (attempted[$0] ?? -.infinity) >= interval }.prefix(maxCount))
    }
}
