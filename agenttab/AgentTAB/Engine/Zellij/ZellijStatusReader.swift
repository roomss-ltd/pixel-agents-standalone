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
    private struct CachedPaneList {
        let data: Data?
        let readAt: Date
    }
    private var paneListCache: [String: CachedPaneList] = [:]

    /// Cadence of the safety-net poll. The plugin rewrites its status file
    /// every 5s while it lives, so this only does real work once Zellij is
    /// gone — which is exactly the case the filesystem source can't report.
    private let pollInterval: TimeInterval = 5

    private struct PaneListEntry: Decodable {
        let id: Int
        let isPlugin: Bool
        let exited: Bool
        let title: String
        let tabPosition: Int
        let tabName: String
        let paneCommand: String?
        let paneCwd: String?

        enum CodingKeys: String, CodingKey {
            case id, exited, title
            case isPlugin = "is_plugin"
            case tabPosition = "tab_position"
            case tabName = "tab_name"
            case paneCommand = "pane_command"
            case paneCwd = "pane_cwd"
        }
    }

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
        paneListCache.removeAll()
    }

    private func scan() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: nil) else { return }
        let now = Date()
        var result: [URL: ZellijStatusFile] = [:]
        var freshSessionNames: Set<String> = []
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  var parsed = try? JSONDecoder().decode(ZellijStatusFile.self, from: data),
                  // Skip stale (>120s old)
                  now.timeIntervalSince1970 - parsed.updatedAt < 120
            else { continue }
            parsed = Self.withDisplayTabNames(parsed)

            // Older status-plugin instances do not publish Devin at all. Fill
            // that gap from Zellij's read-only pane list so an already-running
            // session works without reloading its plugin or terminal panes.
            let sessionName = fileURL.deletingPathExtension().lastPathComponent
            freshSessionNames.insert(sessionName)
            if let paneList = paneList(for: sessionName, now: now) {
                let discovered = Self.devinSessions(
                    fromPaneList: paneList,
                    excluding: Set(parsed.sessions.map(\.paneId))
                )
                if !discovered.isEmpty {
                    parsed = ZellijStatusFile(
                        sessions: parsed.sessions + discovered,
                        counts: ZellijCounts(
                            active: parsed.counts.active + discovered.count,
                            waiting: parsed.counts.waiting,
                            done: parsed.counts.done
                        ),
                        updatedAt: parsed.updatedAt
                    )
                }
            }
            result[fileURL] = parsed
        }
        paneListCache = paneListCache.filter { freshSessionNames.contains($0.key) }
        onUpdate?(result)
    }

    /// Filesystem writes and the five-second safety timer can arrive almost
    /// together. Reuse one read-only pane snapshot across that burst so a
    /// status update never spawns duplicate Zellij clients. Failed reads are
    /// cached too, which keeps a recently-exited session from causing a
    /// process-launch loop while its status file ages out.
    private func paneList(for sessionName: String, now: Date) -> Data? {
        if let cached = paneListCache[sessionName],
           now.timeIntervalSince(cached.readAt) < pollInterval - 0.25 {
            return cached.data
        }
        let data = Self.runZellij([
            "-s", sessionName, "action", "list-panes", "--json"
        ])
        paneListCache[sessionName] = CachedPaneList(data: data, readAt: now)
        return data
    }

    static func devinSessions(
        fromPaneList data: Data,
        excluding existingPaneIds: Set<Int>,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [ZellijSession] {
        guard let panes = try? JSONDecoder().decode([PaneListEntry].self, from: data) else {
            return []
        }
        return panes.compactMap { pane in
            guard !pane.isPlugin, !pane.exited, !existingPaneIds.contains(pane.id),
                  isDevinPane(pane)
            else { return nil }

            let title = pane.title.lowercased().hasPrefix("devin:")
                ? String(pane.title.dropFirst("devin:".count)).trimmingCharacters(in: .whitespaces)
                : pane.title
            let sessionId = "devin-pane-\(pane.id)"
            return ZellijSession(
                paneId: pane.id,
                runId: "\(sessionId):\(pane.id):\(Int(now)):native",
                tabNum: pane.tabPosition + 1,
                tabName: displayTabName(pane.tabName),
                icon: "●",
                detail: nil,
                activity: "Thinking",
                cwd: pane.paneCwd,
                agentKind: "devin",
                agentTitle: title.isEmpty ? nil : title
            )
        }
    }

    /// `●` belongs to Zellij's tab bar. Keep it out of AgentTAB row titles.
    nonisolated static func displayTabName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(" ●") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func withDisplayTabNames(_ status: ZellijStatusFile) -> ZellijStatusFile {
        let sessions = status.sessions.map { session in
            ZellijSession(
                paneId: session.paneId,
                runId: session.runId,
                tabNum: session.tabNum,
                tabName: displayTabName(session.tabName),
                icon: session.icon,
                detail: session.detail,
                activity: session.activity,
                cwd: session.cwd,
                agentKind: session.agentKind,
                agentTitle: session.agentTitle
            )
        }
        return ZellijStatusFile(
            sessions: sessions,
            counts: status.counts,
            updatedAt: status.updatedAt
        )
    }

    private static func isDevinPane(_ pane: PaneListEntry) -> Bool {
        if pane.title.lowercased().hasPrefix("devin:") { return true }
        guard let command = pane.paneCommand,
              let executable = command.split(whereSeparator: \Character.isWhitespace).first
        else { return false }
        return URL(fileURLWithPath: String(executable)).lastPathComponent.lowercased() == "devin"
    }

    private static func runZellij(_ arguments: [String]) -> Data? {
        guard let executable = zellijExecutableURL else { return nil }

        let output = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    /// Use the matching client embedded by source/release builds. A local
    /// Zellij symlink may point into Desktop, Documents, or Downloads; spawning
    /// that target from AgentTAB makes macOS ask for folder permission on every
    /// poll. Never execute a fallback resolved inside those protected folders.
    static var zellijExecutableURL: URL? {
        #if arch(arm64)
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("agenttab-zellij")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        #endif

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/zellij"),
            URL(fileURLWithPath: "/opt/homebrew/bin/zellij"),
            URL(fileURLWithPath: "/usr/local/bin/zellij"),
        ]
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            guard isSafeZellijLocation(resolved, homeDirectory: home),
                  FileManager.default.isExecutableFile(atPath: resolved.path)
            else { continue }
            return resolved
        }
        return nil
    }

    nonisolated static func isSafeZellijLocation(_ url: URL, homeDirectory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        for folder in ["Desktop", "Documents", "Downloads"] {
            let protected = homeDirectory.appendingPathComponent(folder).standardizedFileURL.path
            if path == protected || path.hasPrefix(protected + "/") {
                return false
            }
        }
        return true
    }
}
