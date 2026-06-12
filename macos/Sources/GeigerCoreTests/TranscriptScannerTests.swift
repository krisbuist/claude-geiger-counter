import Foundation
import GeigerCore

private func usageLine(id: String, output: Int) -> String {
    "{\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":0,\"output_tokens\":\(output)}}}\n"
}

private func append(_ s: String, to file: URL) throws {
    if FileManager.default.fileExists(atPath: file.path) {
        let h = try FileHandle(forWritingTo: file)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: s.data(using: .utf8)!)
    } else {
        try s.data(using: .utf8)!.write(to: file)
    }
}

private func appendBytes(_ bytes: [UInt8], to file: URL) throws {
    let h = try FileHandle(forWritingTo: file)
    defer { try? h.close() }
    try h.seekToEnd()
    try h.write(contentsOf: Data(bytes))
}

/// Runs `body` with a fresh temp projects dir; cleans up after.
private func withTempProjects(_ name: String, _ body: (URL) throws -> Void) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("geiger-tests-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try body(tmp)
    } catch {
        expect(false, "\(name): unexpected error \(error)")
    }
    try? FileManager.default.removeItem(at: tmp)
}

private func makeProjectDir(_ tmp: URL, _ dirName: String) throws -> URL {
    let dir = tmp.appendingPathComponent(dirName)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func transcriptScannerTests() {
    // first sighting skips history
    withTempProjects("first sighting") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-myproject")
        let file = dir.appendingPathComponent("session.jsonl")
        try append(usageLine(id: "old", output: 500), to: file)
        let scanner = TranscriptScanner(projectsDir: tmp)
        expectEqual(scanner.scan(), [], "first scan primes offsets, counts nothing")
        expectEqual(scanner.totalDose, 0, "no dose from history")
    }

    // appended lines register as bursts
    withTempProjects("appended bursts") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-myproject")
        let file = dir.appendingPathComponent("session.jsonl")
        try append(usageLine(id: "old", output: 500), to: file)
        let scanner = TranscriptScanner(projectsDir: tmp)
        _ = scanner.scan()
        try append(usageLine(id: "m1", output: 42), to: file)
        expectEqual(scanner.scan(), [Burst(project: "myproject", tokens: 42)], "appended line registers")
        expectEqual(scanner.totalDose, 42, "dose tracks bursts")
    }

    // partial lines buffer across scans
    withTempProjects("partial lines") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-p")
        let file = dir.appendingPathComponent("s.jsonl")
        try append("", to: file)
        let scanner = TranscriptScanner(projectsDir: tmp)
        _ = scanner.scan()
        let full = usageLine(id: "m1", output: 10)
        let mid = full.index(full.startIndex, offsetBy: 30)
        try append(String(full[..<mid]), to: file)
        expectEqual(scanner.scan(), [], "partial line not parsed yet")
        try append(String(full[mid...]), to: file)
        expectEqual(scanner.scan(), [Burst(project: "p", tokens: 10)], "completed line parses")
    }

    // project name strips -Users-<name>- prefix
    withTempProjects("project name") { tmp in
        let scanner = TranscriptScanner(projectsDir: tmp)
        expectEqual(scanner.projectName("-Users-krisbuist-repo-claude-geiger"), "repo-claude-geiger", "strips user prefix")
        expectEqual(scanner.projectName("plain-dir"), "plain-dir", "non-matching name unchanged")
    }

    // ignores non-jsonl files
    withTempProjects("non-jsonl") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-p")
        try append(usageLine(id: "m1", output: 99), to: dir.appendingPathComponent("notes.txt"))
        let scanner = TranscriptScanner(projectsDir: tmp)
        _ = scanner.scan()
        try append(usageLine(id: "m2", output: 99), to: dir.appendingPathComponent("notes.txt"))
        expectEqual(scanner.scan(), [], "txt files ignored")
    }

    // missing projects dir is harmless
    withTempProjects("missing dir") { tmp in
        let scanner = TranscriptScanner(projectsDir: tmp.appendingPathComponent("nope"))
        expectEqual(scanner.scan(), [], "missing dir returns empty")
    }

    // stale untracked files are skipped until they grow fresh again
    withTempProjects("stale files") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-p")
        let file = dir.appendingPathComponent("stale.jsonl")
        try append(usageLine(id: "old", output: 5), to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: file.path)
        let scanner = TranscriptScanner(projectsDir: tmp)
        expectEqual(scanner.scan(), [], "stale untracked file skipped")
        try append(usageLine(id: "m1", output: 7), to: file) // append refreshes mtime
        expectEqual(scanner.scan(), [], "first sighting primes at EOF")
        expectEqual(scanner.totalDose, 0, "nothing counted while priming")
        try append(usageLine(id: "m2", output: 9), to: file)
        expectEqual(scanner.scan(), [Burst(project: "p", tokens: 9)], "fresh append after priming registers")
    }

    // multibyte char split across reads must not drop data
    withTempProjects("multibyte split") { tmp in
        let dir = try makeProjectDir(tmp, "-Users-test-p")
        let file = dir.appendingPathComponent("s.jsonl")
        try append("", to: file)
        let scanner = TranscriptScanner(projectsDir: tmp)
        scanner.scan()
        // id contains a 2-byte UTF-8 char (é = 0xC3 0xA9); split between its bytes
        let full = usageLine(id: "café", output: 21)
        let bytes = [UInt8](full.utf8)
        let splitAt = full.utf8.distance(from: full.utf8.startIndex,
            to: full.utf8.firstIndex(of: 0xC3)!) + 1 // one byte into é
        try appendBytes(Array(bytes[..<splitAt]), to: file)
        expectEqual(scanner.scan(), [], "partial multibyte chunk buffered, not dropped")
        try appendBytes(Array(bytes[splitAt...]), to: file)
        expectEqual(scanner.scan(), [Burst(project: "p", tokens: 21)], "line survives multibyte split")
    }
}
