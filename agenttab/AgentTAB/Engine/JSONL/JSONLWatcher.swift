import Foundation

final class JSONLWatcher {
    private let projectsDir: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var fileOffsets: [URL: UInt64] = [:]
    private var lineBuffers: [URL: String] = [:]
    private let queue = DispatchQueue(label: "agenttab.jsonl", qos: .utility)

    let activeThresholdSeconds: TimeInterval = 30 * 60     // 30 min

    var onLine: ((URL, String) -> Void)?
    var onSessionDiscovered: ((URL, String) -> Void)?      // jsonlPath, projectHash

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

        for fileURL in files where fileURL.pathExtension == "jsonl" {
            guard fileSources[fileURL] == nil else { continue }

            // Skip stale files
            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(mtime) > activeThresholdSeconds { continue }

            // Pick up
            let projectHash = projectURL.lastPathComponent
            onSessionDiscovered?(fileURL, projectHash)
            startWatching(fileURL: fileURL)
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
        let offset = fileOffsets[fileURL] ?? 0
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { return }

            let newOffset = offset + UInt64(data.count)
            fileOffsets[fileURL] = newOffset

            let buffer = (lineBuffers[fileURL] ?? "") + (String(data: data, encoding: .utf8) ?? "")
            var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lineBuffers[fileURL] = lines.popLast() ?? ""

            for line in lines where !line.isEmpty {
                onLine?(fileURL, line)
            }
        } catch {
            // file may have been rotated — restart watch
        }
    }
}
