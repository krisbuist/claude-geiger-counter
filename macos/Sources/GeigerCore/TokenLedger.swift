import Foundation

/// Counts fresh tokens from transcript JSONL lines, deduplicating streaming
/// updates that repeat the same message id with growing usage counts.
///
/// Bounded memory means baselines for evicted message ids are forgotten; if an
/// evicted id streams again later its tokens re-count from zero. Accepted
/// trade-off (same as the CLI): evicted ids are thousands of messages old and
/// no longer streaming in practice.
public struct TokenLedger {
    private var countedByMsg: [String: Int] = [:]
    private var insertionOrder: [String] = []
    public private(set) var totalDose: Int = 0

    public var trackedMessageCount: Int { countedByMsg.count }

    public init() {}

    /// Parses one JSONL line; returns the fresh-token delta (0 if nothing new).
    public mutating func register(line: String) -> Int {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return 0 }
        let msg = obj["message"] as? [String: Any]
        guard let usage = msg?["usage"] as? [String: Any] else { return 0 }
        guard let id = (msg?["id"] as? String)
            ?? (obj["requestId"] as? String)
            ?? (obj["uuid"] as? String)
        else { return 0 }

        let total = (usage["input_tokens"] as? Int ?? 0)
            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            + (usage["output_tokens"] as? Int ?? 0)

        let prev = countedByMsg[id]
        let prevTotal = prev ?? 0
        guard total > prevTotal else { return 0 }
        if prev == nil { insertionOrder.append(id) }
        countedByMsg[id] = total

        if countedByMsg.count > 5000 {
            // Keep the newest 4000 ids; rebuild both structures so duplicate
            // order entries from re-seen evicted ids cannot accumulate.
            var keep = Set<String>()
            var newOrder: [String] = []
            for id in insertionOrder.reversed()
            where countedByMsg[id] != nil && !keep.contains(id) {
                keep.insert(id)
                newOrder.append(id)
                if keep.count == 4000 { break }
            }
            insertionOrder = Array(newOrder.reversed())
            countedByMsg = countedByMsg.filter { keep.contains($0.key) }
        }

        totalDose += total - prevTotal
        return total - prevTotal
    }
}
