import Foundation

public struct Burst: Equatable {
    public let project: String
    public let tokens: Int

    public init(project: String, tokens: Int) {
        self.project = project
        self.tokens = tokens
    }
}

/// Tails *.jsonl transcripts under a Claude projects directory, returning
/// fresh-token bursts on each scan. First sighting of a file seeks to EOF so
/// history is never counted.
public final class TranscriptScanner {
    private let projectsDir: URL
    private var fileOffsets: [String: UInt64] = [:]
    private var partialLine: [String: Data] = [:]
    private var ledger = TokenLedger()

    public var totalDose: Int { ledger.totalDose }

    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
    }

    @discardableResult
    public func scan(now: Date = Date()) -> [Burst] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsDir.path) else { return [] }
        let cutoff = now.addingTimeInterval(-3600) // ignore stale sessions
        var bursts: [Burst] = []
        for d in dirs.sorted() {
            let dir = projectsDir.appendingPathComponent(d)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files.sorted() where f.hasSuffix(".jsonl") {
                let file = dir.appendingPathComponent(f)
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let mtime = attrs[.modificationDate] as? Date,
                      let size = (attrs[.size] as? NSNumber)?.uint64Value
                else {
                    fileOffsets.removeValue(forKey: file.path)
                    partialLine.removeValue(forKey: file.path)
                    continue
                }
                if mtime < cutoff && fileOffsets[file.path] == nil { continue }
                bursts += readAppended(file: file, size: size, project: projectName(d))
            }
        }
        return bursts
    }

    /// "-Users-krisbuist-repo-claude-geiger" → "repo-claude-geiger"
    public func projectName(_ dirName: String) -> String {
        let stripped = dirName.replacingOccurrences(
            of: "^-Users-[^-]+-?", with: "", options: .regularExpression)
        return stripped.isEmpty ? dirName : stripped
    }

    private func readAppended(file: URL, size: UInt64, project: String) -> [Burst] {
        let key = file.path
        guard let offset = fileOffsets[key] else {
            fileOffsets[key] = size // first sighting: skip history
            return []
        }
        if size < offset {
            // file shrank (deleted + recreated): re-prime at EOF, drop stale partial
            fileOffsets[key] = size
            partialLine.removeValue(forKey: key)
            return []
        }
        guard size > offset,
              let handle = try? FileHandle(forReadingFrom: file)
        else { return [] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: Int(size - offset)), !data.isEmpty
        else { return [] }
        fileOffsets[key] = offset + UInt64(data.count)

        // Buffer raw bytes and split on \n before decoding, so a chunk
        // ending mid-multibyte-character never corrupts or drops a line.
        var buffer = (partialLine[key] ?? Data()) + data
        var bursts: [Burst] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            let delta = ledger.register(line: line)
            if delta > 0 { bursts.append(Burst(project: project, tokens: delta)) }
        }
        partialLine[key] = buffer
        return bursts
    }
}
