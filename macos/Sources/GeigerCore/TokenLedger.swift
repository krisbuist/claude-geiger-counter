import Foundation

/// Counts fresh tokens from transcript JSONL lines, deduplicating streaming
/// updates that repeat the same message id with growing usage counts.
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

        let prev = countedByMsg[id] ?? 0
        guard total > prev else { return 0 }
        if countedByMsg[id] == nil { insertionOrder.append(id) }
        countedByMsg[id] = total

        if countedByMsg.count > 5000 {
            while countedByMsg.count > 4000, !insertionOrder.isEmpty {
                countedByMsg.removeValue(forKey: insertionOrder.removeFirst())
            }
        }

        totalDose += total - prev
        return total - prev
    }
}
