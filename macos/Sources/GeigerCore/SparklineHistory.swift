import Foundation

/// Rolling history of gauge intensity (0...1) over the last five minutes,
/// rendered as a Unicode block sparkline for the menu-bar title.
public struct SparklineHistory {
    public static let windowSeconds: TimeInterval = 300

    private static let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    private var samples: [(t: Date, frac: Double)] = []

    public init() {}

    public mutating func add(fraction: Double, at t: Date) {
        samples.append((t, min(1, max(0, fraction))))
    }

    /// Bucket the window into `columns` time bins (newest on the right) and map
    /// the peak intensity in each bin to a block glyph. Bins with no samples
    /// render as a space, so a fresh history stays short instead of padding.
    public mutating func render(now: Date, columns: Int) -> String {
        let cutoff = now.addingTimeInterval(-Self.windowSeconds)
        samples.removeAll { $0.t < cutoff }
        guard columns > 0, !samples.isEmpty else { return "" }

        let binWidth = Self.windowSeconds / Double(columns)
        var peaks = [Double?](repeating: nil, count: columns)
        for s in samples {
            let elapsed = now.timeIntervalSince(s.t)
            let fromRight = Int(elapsed / binWidth)
            guard fromRight >= 0, fromRight < columns else { continue }
            let col = columns - 1 - fromRight
            peaks[col] = max(peaks[col] ?? 0, s.frac)
        }

        return String(peaks.map { peak -> Character in
            guard let peak else { return " " }
            let idx = min(Self.blocks.count - 1, Int(peak * Double(Self.blocks.count)))
            return Self.blocks[idx]
        })
    }
}
