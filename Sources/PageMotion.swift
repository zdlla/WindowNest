import Foundation

/// Critically damped motion: carries release velocity without a decorative bounce.
/// The analytic step is independent of refresh rate, including after a delayed frame.
struct PageMotion {
    var position: Double
    var velocity: Double
    let destination: Double
    let response: Double

    init(position: Double, velocity: Double = 0, destination: Double, response: Double = 20) {
        self.position = position
        self.velocity = max(-6, min(6, velocity))
        self.destination = destination
        self.response = response
    }
    var isSettled: Bool { abs(position - destination) < 0.0005 && abs(velocity) < 0.008 }
    mutating func advance(by elapsed: TimeInterval) {
        guard elapsed > 0 else { return }
        let offset = position - destination
        let coefficient = velocity + response * offset
        let decay = exp(-response * elapsed)
        position = destination + (offset + coefficient * elapsed) * decay
        velocity = (velocity - response * coefficient * elapsed) * decay
    }
}
