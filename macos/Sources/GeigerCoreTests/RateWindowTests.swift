import Foundation
import GeigerCore

func rateWindowTests() {
    // empty window is zero
    var w = RateWindow()
    expectEqual(w.tokensPerMinute(now: Date()), 0, "empty window is zero")

    // rate scales window sum to per-minute
    w = RateWindow()
    let now = Date()
    // 1500 tokens in the 15 s window → 6000 tokens/min
    w.add(tokens: 1000, at: now.addingTimeInterval(-10))
    w.add(tokens: 500, at: now.addingTimeInterval(-2))
    expectEqual(w.tokensPerMinute(now: now), 6000, accuracy: 0.001, "sum scales to per-minute")

    // old events fall out of the window
    w = RateWindow()
    w.add(tokens: 9999, at: now.addingTimeInterval(-16))
    w.add(tokens: 150, at: now.addingTimeInterval(-1))
    expectEqual(w.tokensPerMinute(now: now), 600, accuracy: 0.001, "old events fall out")
}
