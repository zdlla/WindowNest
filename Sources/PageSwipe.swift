import Foundation

enum PageGesturePhase { case began, changed, ended, cancelled, unphased }
enum PageSwipeEffect: Equatable {
    case pass, swallow
    case track(WorkspaceMode, Double)
    case finish(WorkspaceMode, Bool)
}

/// A single axis-locked trackpad gesture. Momentum must never trigger a second page.
struct PageSwipeTracker {
    private enum Axis { case undecided, vertical, horizontal }
    private var axis = Axis.undecided
    private var origin: WorkspaceMode?
    private var target: WorkspaceMode?
    private var startingPosition = 0.0
    private var direction = 1.0
    private var lowerBound = 0.0
    private var upperBound = 1.0
    private(set) var releaseVelocity = 0.0
    private var x = 0.0
    private var y = 0.0
    private var velocity = 0.0
    private var lastTime = 0.0
    private var swallowMomentum = false
    var isTracking: Bool { origin != nil && target != nil && axis == .horizontal }

    mutating func handle(dx: Double, dy: Double, phase: PageGesturePhase,
        precise: Bool, momentum: Bool, timestamp: Double, mode: WorkspaceMode, width: Double, startingPosition: Double? = nil) -> PageSwipeEffect {
        guard precise else { return .pass }
        if momentum && phase != .ended && phase != .cancelled { return swallowMomentum ? .swallow : .pass }
        guard phase != .unphased else { return .pass }
        if phase == .began {
            axis = .undecided; origin = mode; target = nil
            self.startingPosition = startingPosition ?? Double(mode.rawValue)
            releaseVelocity = 0
            x = 0; y = 0; velocity = 0; lastTime = timestamp; swallowMomentum = false
        }
        guard origin != nil else { return .pass }
        if phase == .ended || phase == .cancelled {
            defer { self.origin = nil; target = nil }
            guard axis == .horizontal, let target else { return .pass }
            let distance = direction * x
            let threshold = max(72, min(140, width * 0.12))
            let recentVelocity = timestamp - lastTime < 0.12 ? velocity : 0
            let directedVelocity = direction * recentVelocity
            releaseVelocity = phase == .cancelled ? 0 : max(-6, min(6, recentVelocity / max(1, width)))
            let position = self.startingPosition + x / max(1, width)
            let midpoint = (lowerBound + upperBound) / 2
            let crossedMiddle = direction > 0 ? position > midpoint : position < midpoint
            let commit = phase != .cancelled && (crossedMiddle || distance >= threshold || (distance > 36 && directedVelocity > 700))
            return .finish(target, commit)
        }
        x += dx; y += dy
        if abs(dx) > 0.01 {
            let instantaneous = dx / max(0.008, timestamp - lastTime)
            velocity = velocity == 0 ? instantaneous : velocity * 0.35 + instantaneous * 0.65
            lastTime = timestamp
        }
        if axis == .undecided {
            if abs(y) > 8 && abs(y) > abs(x) * 1.2 { axis = .vertical }
            else if abs(x) > 10 && abs(x) > abs(y) * 1.3 {
                axis = .horizontal
                self.startingPosition = startingPosition ?? self.startingPosition
                let last = Double(WorkspaceMode.allCases.count - 1)
                direction = x > 0 ? 1 : -1
                if x > 0 && self.startingPosition < last {
                    lowerBound = floor(self.startingPosition + 0.000001)
                    upperBound = min(last, lowerBound + 1)
                    target = WorkspaceMode(rawValue: Int(upperBound))
                } else if x < 0 && self.startingPosition > 0 {
                    upperBound = ceil(self.startingPosition - 0.000001)
                    lowerBound = max(0, upperBound - 1)
                    target = WorkspaceMode(rawValue: Int(lowerBound))
                }
                swallowMomentum = target != nil
            }
        }
        guard axis == .horizontal, let target else { return .pass }
        let position = max(lowerBound, min(upperBound, self.startingPosition + x / max(1, width)))
        return .track(target, position)
    }
}
