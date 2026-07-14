// agenttab/AgentTAB/Engine/Zellij/ZellijStatusReader.swift
import Foundation

final class ZellijStatusReader {
    /// Where the Zellij plugin publishes its status files. Injectable so tests
    /// can drive the engine without picking up the developer's own live panes.
    static let defaultStatusDir = URL(fileURLWithPath: "/tmp/claude-tab-status")

    private let statusDir: URL
    private var dirSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "agenttab.zellij")

    /// Cadence of the safety-net poll. The plugin rewrites its status file
    /// every 5s while it lives, so this only does real work once Zellij is
    /// gone — which is exactly the case the filesystem source can't report.
    private let pollInterval: TimeInterval = 5

    var onUpdate: (([URL: ZellijStatusFile]) -> Void)?

    init(statusDir: URL = ZellijStatusReader.defaultStatusDir) {
        self.statusDir = statusDir
    }

    func start() {
        guard FileManager.default.fileExists(atPath: statusDir.path) else { return }
        let fd = open(statusDir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )
        dirSource?.setEventHandler { [weak self] in self?.scan() }
        dirSource?.setCancelHandler { close(fd) }
        dirSource?.resume()

        // The filesystem source only fires when someone *writes*. When Zellij
        // exits, the status files stop being touched and simply rot past the
        // staleness cutoff below — an event that, by definition, produces no
        // write and therefore no callback. Without a poll the engine would
        // keep rendering the last snapshot Zellij ever published, forever.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        pollTimer = timer

        scan()
    }

    func stop() {
        dirSource?.cancel()
        dirSource = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func scan() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: nil) else { return }
        var result: [URL: ZellijStatusFile] = [:]
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONDecoder().decode(ZellijStatusFile.self, from: data),
                  // Skip stale (>120s old)
                  Date().timeIntervalSince1970 - parsed.updatedAt < 120
            else { continue }
            result[fileURL] = parsed
        }
        onUpdate?(result)
    }
}
