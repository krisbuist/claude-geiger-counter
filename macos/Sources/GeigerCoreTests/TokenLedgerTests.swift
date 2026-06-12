import GeigerCore

private func line(id: String, input: Int, cacheCreate: Int = 0, cacheRead: Int = 0, output: Int) -> String {
    "{\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),"
        + "\"cache_creation_input_tokens\":\(cacheCreate),"
        + "\"cache_read_input_tokens\":\(cacheRead),\"output_tokens\":\(output)}}}"
}

func tokenLedgerTests() {
    // counts fresh tokens
    var ledger = TokenLedger()
    expectEqual(ledger.register(line: line(id: "m1", input: 10, cacheCreate: 5, output: 20)), 35, "fresh tokens counted")
    expectEqual(ledger.totalDose, 35, "dose accumulates")

    // cache reads are shielded
    ledger = TokenLedger()
    expectEqual(ledger.register(line: line(id: "m1", input: 10, cacheRead: 9999, output: 20)), 30, "cache reads shielded")

    // streaming updates count only the delta
    ledger = TokenLedger()
    expectEqual(ledger.register(line: line(id: "m1", input: 10, output: 5)), 15, "first sighting full count")
    expectEqual(ledger.register(line: line(id: "m1", input: 10, output: 25)), 20, "growth counts delta only")
    expectEqual(ledger.register(line: line(id: "m1", input: 10, output: 25)), 0, "repeat counts nothing")
    expectEqual(ledger.totalDose, 35, "dose equals sum of deltas")

    // falls back to requestId then uuid
    ledger = TokenLedger()
    let byRequestId = "{\"requestId\":\"r1\",\"message\":{\"usage\":{\"input_tokens\":7,\"output_tokens\":3}}}"
    expectEqual(ledger.register(line: byRequestId), 10, "requestId fallback")
    expectEqual(ledger.register(line: byRequestId), 0, "requestId dedups")
    let byUuid = "{\"uuid\":\"u1\",\"message\":{\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}"
    expectEqual(ledger.register(line: byUuid), 2, "uuid fallback")

    // ignores garbage and non-usage lines
    ledger = TokenLedger()
    expectEqual(ledger.register(line: "not json at all"), 0, "garbage ignored")
    expectEqual(ledger.register(line: "{\"type\":\"summary\"}"), 0, "no message ignored")
    expectEqual(ledger.register(line: "{\"message\":{\"id\":\"x\"}}"), 0, "no usage ignored")
    expectEqual(ledger.totalDose, 0, "nothing registered")

    // dedup map stays bounded
    ledger = TokenLedger()
    for i in 0..<5100 {
        _ = ledger.register(line: line(id: "m\(i)", input: 1, output: 0))
    }
    expect(ledger.trackedMessageCount <= 5000, "dedup map bounded")
    expectEqual(ledger.totalDose, 5100, "dose unaffected by eviction")
}
