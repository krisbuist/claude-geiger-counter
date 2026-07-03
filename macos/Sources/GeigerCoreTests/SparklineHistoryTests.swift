import Foundation
import GeigerCore

func sparklineHistoryTests() {
    let now = Date()

    // empty history renders nothing
    var h = SparklineHistory()
    expectEqual(h.render(now: now, columns: 10), "", "empty history is empty string")

    // width matches column count once there is a sample in the oldest bin
    h = SparklineHistory()
    h.add(fraction: 0.5, at: now.addingTimeInterval(-299))
    expectEqual(h.render(now: now, columns: 10).count, 10, "render is padded to columns")

    // full intensity maps to the top block, zero to the floor block
    h = SparklineHistory()
    h.add(fraction: 1.0, at: now)
    expectEqual(String(h.render(now: now, columns: 3).last!), "█", "1.0 → full block")
    h = SparklineHistory()
    h.add(fraction: 0.0, at: now)
    expectEqual(String(h.render(now: now, columns: 3).last!), "▁", "0.0 → floor block")

    // gaps between samples render as spaces
    h = SparklineHistory()
    h.add(fraction: 1.0, at: now.addingTimeInterval(-299)) // oldest bin
    h.add(fraction: 1.0, at: now)                          // newest bin
    let spark = h.render(now: now, columns: 6)
    expect(spark.first == "█" && spark.last == "█", "ends filled")
    expect(spark.contains(" "), "middle bins are spaces")

    // samples older than the window fall out
    h = SparklineHistory()
    h.add(fraction: 1.0, at: now.addingTimeInterval(-301))
    expectEqual(h.render(now: now, columns: 5), "", "stale samples pruned")

    // peak per bin wins over later lower samples in the same bin
    h = SparklineHistory()
    h.add(fraction: 0.9, at: now.addingTimeInterval(-0.5))
    h.add(fraction: 0.1, at: now)
    expectEqual(String(h.render(now: now, columns: 4).last!), "█", "bin keeps peak")
}
