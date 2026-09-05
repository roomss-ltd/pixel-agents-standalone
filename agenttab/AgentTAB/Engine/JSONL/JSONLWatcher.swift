import Foundation

final class JSONLWatcher {
    /// A live transcript can be hundreds of megabytes. On launch we only
    /// need its recent state, not a replay of the entire conversation.
    private let initialCatchUpBytes: UInt64 = 2 * 1024 * 1024

    private let projectsDir: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fileOffsets: [URL: UInt64] = [:]
    private var lineBuffers: [URL: String] = [:]
    private let queue = DispatchQueue(label: "agenttab.jsonl", qos: .utility)

    /// Files newer than this get a live watcher so we see every appended
    /// JSONL line in real time. Older but historical files are still
    /// surfaced (without a watcher) so the OLDER list isn't empty.
    let liveWatchThreshold: TimeInterval = 30 * 60          // 30 min

    /// How far back we look for "older" sessions. Mirrors Hammerspoon's
    /// behaviour — only sessions touched in the last day count as "recent".
    let historicalThreshold: TimeInterval = 24 * 60 * 60        // 24 hours

    /// Hard cap on the number of historical (non-live) sessions we surface.
    /// Prevents a flood of stale jsonl files from blowing up the OLDER list.
    let historicalCap: Int = 12

    /// Backwards-compat alias for tests / older callers.
    var activeThresholdSeconds: TimeInterval { liveWatchThreshold }

    var onLine: ((URL, String) -> Void)?
    var onSessionDiscovered: ((URL, String, Date, Bool) -> Void)?
    // jsonlPath, projectHash, mtime, isLive (true → being watched)

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }

    func start() {
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return }

        // Initial scan
        scanProjectsDirectory()

        // Watch for new project dirs
        let fd = open(projectsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: queue)
        directorySource?.setEventHandler { [weak self] in self?.scanProjectsDirectory() }
        directorySource?.setCancelHandler { close(fd) }
        directorySource?.resume()
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        for (_, source) in fileSources { source.cancel() }
        fileSources.removeAll()
    }

    /// Forget a file so the next directory scan re-announces it through
    /// `onSessionDiscovered`.
    ///
    /// The engine drops a Session when its Zellij pane disappears or the agent
    /// sends `SessionEnd`. Without this, the watcher would still hold a live
    /// source for that file, so it would never re-announce it — and any line
    /// the file gained afterwards would route to a Session that no longer
    /// exists and be silently discarded, permanently.
    ///
    /// The byte offset is deliberately kept: we resume where we left off
    /// instead of replaying the whole transcript.
    func release(fileURL: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.fileSources[fileURL]?.cancel()
            self.fileSources.removeValue(forKey: fileURL)
        }
    }

    private func scanProjectsDirectory() {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil) else { return }

        for projectURL in projects {
            guard let isDir = (try? projectURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                  isDir else { continue }
            scanProjectFolder(projectURL)
        }
    }

    private func scanProjectFolder(_ projectURL: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: projectURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let candidates: [(URL, Date, TimeInterval)] = files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url in
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let age = Date().timeIntervalSince(mtime)
                guard age <= historicalThreshold else { return nil }
                return (url, mtime, age)
            }
            .sorted { $0.1 > $1.1 }   // newest first

        var historicalCount = 0
        for (fileURL, mtime, age) in candidates {
            guard fileSources[fileURL] == nil else { continue }

            let projectHash = projectURL.lastPathComponent
            let isLive = age <= liveWatchThreshold
            if !isLive {
                historicalCount += 1
                if historicalCount > historicalCap { continue }
            }
            onSessionDiscovered?(fileURL, projectHash, mtime, isLive)
            if isLive {
                startWatching(fileURL: fileURL)
            }
        }
    }

    private func startWatching(fileURL: URL) {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: queue)
        source.setEventHandler { [weak self] in self?.readNewLines(from: fileURL) }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSources[fileURL] = source

        // Initial read for catch-up
        readNewLines(from: fileURL)
    }

    private func readNewLines(from fileURL: URL) {
        let isInitialRead = fileOffsets[fileURL] == nil
        let lastOffset = fileOffsets[fileURL] ?? 0
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        do {
            // If the file shrank below our last offset, it was rotated /
            // truncated — reset to 0 so we don't seek past EOF and miss
            // every subsequent append. Otherwise the previously parsed
            // bytes are guaranteed to be the same byte ranges, so
            // resuming from `lastOffset` is the only way to stay
            // idempotent across rescans triggered by the directory
            // watcher.
            let endOffset = (try? handle.seekToEnd()) ?? 0
            let offset: UInt64
            var dropsLeadingPartialLine = false
            if endOffset < lastOffset {
                AgentLog.watcher.warning("file shrank, resetting offset path=\(fileURL.lastPathComponent, privacy: .public) was=\(lastOffset) now=\(endOffset)")
                offset = endOffset > initialCatchUpBytes ? endOffset - initialCatchUpBytes : 0
                dropsLeadingPartialLine = offset > 0
                lineBuffers[fileURL] = ""
            } else if isInitialRead, endOffset > initialCatchUpBytes {
                offset = endOffset - initialCatchUpBytes
                dropsLeadingPartialLine = true
            } else {
                offset = lastOffset
            }

            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { return }

            let newOffset = offset + UInt64(data.count)
            fileOffsets[fileURL] = newOffset

            let buffer = (lineBuffers[fileURL] ?? "") + (String(data: data, encoding: .utf8) ?? "")
            var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lineBuffers[fileURL] = lines.popLast() ?? ""
            if dropsLeadingPartialLine, !lines.isEmpty {
                lines.removeFirst()
            }

            for line in lines where !line.isEmpty {
                onLine?(fileURL, line)
            }
        } catch {
            AgentLog.watcher.error("read failed path=\(fileURL.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }
}
