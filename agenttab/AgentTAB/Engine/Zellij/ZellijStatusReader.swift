// agenttab/AgentTAB/Engine/Zellij/ZellijStatusReader.swift
import Foundation

final class ZellijStatusReader {
    private let statusDir = URL(fileURLWithPath: "/tmp/claude-tab-status")
    private var dirSource: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "agenttab.zellij")

    var onUpdate: (([URL: ZellijStatusFile]) -> Void)?

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

        scan()
    }

    func stop() { dirSource?.cancel() }

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
