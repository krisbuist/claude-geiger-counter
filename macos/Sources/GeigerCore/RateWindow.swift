import Foundation

/// Sliding-window token rate: tokens/min over the last 15 seconds.
public struct RateWindow {
    public static let windowSeconds: TimeInterval = 15
    private var events: [(t: Date, tokens: Int)] = []

    public init() {}

    public mutating func add(tokens: Int, at t: Date) {
        events.append((t, tokens))
    }

    public mutating func tokensPerMinute(now: Date) -> Double {
        let cutoff = now.addingTimeInterval(-Self.windowSeconds)
        events.removeAll { $0.t < cutoff }
        let sum = events.reduce(0) { $0 + $1.tokens }
        return Double(sum) / Self.windowSeconds * 60
    }
}
