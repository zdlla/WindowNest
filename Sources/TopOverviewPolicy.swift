import Foundation
import CoreGraphics

struct TopOverviewLayout: Equatable {
    let trigger: CGRect
    let panel: CGRect
    let previewHeight: CGFloat
    let cardWidth: CGFloat
    let iconsOnly: Bool

    init(screen: CGRect, topInset: CGFloat, notchInset: CGFloat = 0,
         position: TopOverviewPosition = .center, widthPercent: Double = 20, triggerDepth: Double = 12, heightPercent: Double = 32) {
        let inset = max(0, topInset)
        let width = screen.width * CGFloat(min(100, max(10, widthPercent))) / 100
        let depth = CGFloat(min(64, max(4, triggerDepth)))
        let x: CGFloat
        switch position {
        case .left: x = screen.minX
        case .center: x = screen.midX - width / 2
        case .right: x = screen.maxX - width
        }
        trigger = CGRect(x: x, y: screen.maxY - depth, width: width, height: depth)
        // Small heights use a single icon row instead of shrinking screenshots
        // and controls into an unreadable strip. Keep only a 44pt control floor.
        let available = max(1, screen.height - inset - 24)
        let percent = min(55, max(5, heightPercent))
        let height = min(available, max(44, screen.height * CGFloat(percent) / 100))
        iconsOnly = percent < 10 || height < 132
        let margin: CGFloat = screen.width < 900 ? 10 : 16
        panel = CGRect(x: screen.minX + margin, y: screen.maxY - inset - 8 - height,
            width: max(1, screen.width - margin * 2), height: height)
        previewHeight = iconsOnly ? 0 : max(1, panel.height - 88)
        cardWidth = min(max(1, panel.width - 36), iconsOnly ? 190 : max(220, min(384, previewHeight * 1.55)))
    }
    static func iconCardWidth(available: CGFloat, count: Int) -> CGFloat {
        min(300, max(190, (available - CGFloat(max(0, count - 1)) * 8) / CGFloat(max(1, count))))
    }
    func containsTrigger(_ point: CGPoint) -> Bool {
        // Screen-edge coordinates can equal maxY/maxX; CGRect.contains uses
        // half-open edges and used to reject a pointer pushed to the very top.
        return point.x >= trigger.minX && point.x <= trigger.maxX &&
            point.y >= trigger.minY && point.y <= trigger.maxY
    }
}

/// Pure hover state: dwell to open, hysteresis to leave, and exit-to-rearm after
/// explicit dismissal. No event interception or input-monitoring permission.
struct TopOverviewHover {
    enum Event: Equatable { case none, show(String), hide }
    private(set) var screenID: String?
    private var candidate: String?
    private var candidateSince: TimeInterval?
    private var candidateExitSince: TimeInterval?
    private var outsideSince: TimeInterval?
    private var suppressed = false
    let dwellDuration: TimeInterval
    static let leaveDelay: TimeInterval = 0.58
    static let boundaryGrace: TimeInterval = 0.09
    var needsClock: Bool { candidate != nil || outsideSince != nil }

    init(dwell: TimeInterval = 0.36) { dwellDuration = min(1.5, max(0, dwell)) }

    mutating func update(trigger: String?, insidePanel: Bool, dragging: Bool, interacting: Bool,
                         time: TimeInterval) -> Event {
        if let screenID {
            if insidePanel || trigger == screenID || interacting {
                outsideSince = nil
            } else {
                if dragging { dismiss(suppressReentry: false); return .hide }
                if outsideSince == nil { outsideSince = time }
                if time - outsideSince! >= Self.leaveDelay { dismiss(suppressReentry: false); return .hide }
            }
            return .none
        }
        if trigger == nil { suppressed = false }
        guard !suppressed, !dragging, !interacting else {
            candidate = nil; candidateSince = nil; candidateExitSince = nil
            return .none
        }
        guard let trigger else {
            if candidate != nil {
                if candidateExitSince == nil { candidateExitSince = time }
                if time - candidateExitSince! >= Self.boundaryGrace {
                    candidate = nil; candidateSince = nil; candidateExitSince = nil
                }
            }
            return .none
        }
        let exitedTooLong = candidateExitSince.map { time - $0 >= Self.boundaryGrace } ?? false
        if candidate != trigger || exitedTooLong { candidate = trigger; candidateSince = time }
        candidateExitSince = nil
        guard let since = candidateSince, time - since >= dwellDuration else { return .none }
        reveal(on: trigger)
        return .show(trigger)
    }

    mutating func reveal(on id: String) {
        screenID = id; candidate = nil; candidateSince = nil; candidateExitSince = nil; outsideSince = nil; suppressed = false
    }
    mutating func dismiss(suppressReentry: Bool = true) {
        screenID = nil; candidate = nil; candidateSince = nil; candidateExitSince = nil; outsideSince = nil; suppressed = suppressReentry
    }
    mutating func reset() { self = TopOverviewHover(dwell: dwellDuration) }
}
