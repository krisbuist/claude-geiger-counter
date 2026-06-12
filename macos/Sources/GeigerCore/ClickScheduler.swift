import Foundation

/// Poisson click scheduler: exponential gaps, rate tied to the gauge fraction.
/// Call tick(...) on a ~20 ms timer; it returns true when a click should fire.
public struct ClickScheduler {
    public static let maxClicksPerSec: Double = 30
    private var nextClickAt: TimeInterval = 0

    public init() {}

    public mutating func tick(
        frac: Double,
        now: TimeInterval,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Bool {
        if frac <= 0 {
            // background: occasional lonely click, like cosmic rays
            return random() < 0.003
        }
        let cps = 0.5 + frac * frac * Self.maxClicksPerSec
        guard now >= nextClickAt else { return false }
        let gap = -log(1 - random()) / cps // exponential, seconds
        nextClickAt = now + max(0.015, gap)
        return true
    }
}
