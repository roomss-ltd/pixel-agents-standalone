// TokenTracker — per-machine daily token-spend counter.
//
// Sums token usage across every Claude Code agent that ran today by
// scanning ~/.claude/projects/**/*.jsonl. Only `assistant` lines with
// a today-dated `timestamp` are counted; the total is
// input + output + cache_creation + cache_read tokens.
//
// Scanning is incremental — each file keeps a byte cursor so a refresh
// only parses bytes appended since the last pass. The counter resets
// automatically when the local date rolls over (it's the source of
// truth recomputed from today's lines, so no persistence is needed).

import Foundation
import Combine

@MainActor
final class TokenTracker: ObservableObject {
    /// Total tokens spent across all agents on the local machine today.
    @Published private(set) var todayTokens: Int = 0

    private let projectsDir: URL
    private var timer: AnyCancellable?

    /// Per-file scan cursor — byte offset already summed.
    private var fileCursors: [URL: UInt64] = [:]

    /// The start-of-day the running total belongs to. When the wall
    /// clock crosses midnight we reset everything.
    private var currentDay: Date = Calendar.current.startOfDay(for: Date())

    /// Reused — ISO8601DateFormatter is expensive to allocate per line.
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFraction = ISO8601DateFormatter()

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }

    func start() {
        refresh()
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Recompute the delta since the last pass. Cheap to call often —
    /// safe to invoke on panel-expand for a fresh number.
    func refresh() {
        // Date rollover → wipe and start the new day at zero.
        let today = Calendar.current.startOfDay(for: Date())
        if today != currentDay {
            currentDay = today
            fileCursors.removeAll()
            todayTokens = 0
            AgentLog.engine.info("token tracker reset for new day")
        }

        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return }

        var added = 0
        for project in projects {
            guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir,
                  let files = try? FileManager.default.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: [.contentModificationDateKey]
                  )
            else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                // A file untouched today can't contain today's lines.
                guard mtime >= currentDay else { continue }
                added += scanFile(file)
            }
        }

        if added > 0 {
            todayTokens += added
            AgentLog.engine.info("token tracker +\(added) → \(self.todayTokens)")
        }
    }

    /// Returns the tokens found in the bytes appended to `url` since the
    /// last scan, and advances the file cursor past the last complete
    /// line (a trailing partial line is left for the next refresh).
    private func scanFile(_ url: URL) -> Int {
        let cursor = fileCursors[url] ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        // File shrank → rotated/truncated, rescan from the top.
        let start: UInt64 = end < cursor ? 0 : cursor
        guard end > start else { return 0 }

        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let lastNL = text.lastIndex(of: "\n")
        else { return 0 }   // no complete line yet — don't advance cursor

        let complete = text[..<lastNL]
        let consumed = complete.utf8.count + 1   // +1 for the newline
        fileCursors[url] = start + UInt64(consumed)

        var sum = 0
        for line in complete.split(separator: "\n") where !line.isEmpty {
            sum += tokensInLine(String(line))
        }
        return sum
    }

    private func tokensInLine(_ line: String) -> Int {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return 0 }

        // A file modified today can still hold lines from a session
        // that started yesterday — only count today's.
        if let ts = json["timestamp"] as? String, !isToday(ts) { return 0 }

        let input  = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return input + output + cacheCreate + cacheRead
    }

    private func isToday(_ iso: String) -> Bool {
        let date = isoFormatter.date(from: iso)
            ?? isoFormatterNoFraction.date(from: iso)
        guard let date else { return true }   // unparseable → count it
        return Calendar.current.isDate(date, inSameDayAs: currentDay)
    }
}
