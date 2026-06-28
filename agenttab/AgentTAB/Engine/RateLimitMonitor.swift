// RateLimitMonitor.swift — polls the Claude subscription usage limits.
//
// Claude Code authenticates with a subscription OAuth token (stored in the
// macOS Keychain under "Claude Code-credentials"). Anthropic exposes the live
// 5-hour and weekly (7-day) usage windows at:
//
//     GET https://api.anthropic.com/api/oauth/usage
//        Authorization: Bearer <accessToken>
//        anthropic-beta: oauth-2025-04-20
//
// → { five_hour: {utilization, resets_at}, seven_day: {...}, seven_day_sonnet, ... }
//
// It's a plain GET — costs ZERO token budget, doesn't count against any limit.
// This is the same call the official `/usage` command + the claude-dashboard
// plugin use. NOTE: `/api/oauth/usage` is undocumented/internal — it powers the
// client, so it's stable in practice, but Anthropic could change it.
//
// We re-read the token from the Keychain on every poll (Claude Code keeps it
// refreshed) and cache results for `pollInterval` so we never get 429'd.

import Foundation
import Combine
import os

@MainActor
final class RateLimitMonitor: ObservableObject {
    /// Shared instance so any view can observe it (like `EnergyMonitor.shared`).
    static let shared = RateLimitMonitor()

    /// One usage window (5-hour or weekly).
    struct Window: Equatable {
        /// Percent of the window consumed, 0…100.
        var utilization: Double
        /// When this window rolls over.
        var resetsAt: Date?
    }

    @Published private(set) var fiveHour: Window?
    @Published private(set) var weekly: Window?
    /// Weekly limit specific to Sonnet (Anthropic tracks it separately).
    @Published private(set) var weeklySonnet: Window?
    @Published private(set) var lastUpdated: Date?

    /// 5 minutes — matches the claude-dashboard cache; gentle enough to never
    /// trip the endpoint's own rate limiting.
    private let pollInterval: TimeInterval = 300
    private var timer: Timer?
    private let session = URLSession(configuration: .ephemeral)
    private let log = Logger(subsystem: "com.roomss.agenttab", category: "ratelimit")

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Fetch the current limits. Keeps the last good values on any failure.
    func refresh() async {
        // Read the Keychain token OFF the main actor — the `security` subprocess
        // spawn + waitUntilExit() blocks for tens of ms, which would otherwise
        // hitch the UI on every poll.
        guard let token = await Task.detached(priority: .utility, operation: { Self.readToken() }).value else {
            log.debug("no Claude Code token in keychain")
            return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                log.notice("usage endpoint status \(http.statusCode)")
                return
            }
            let usage = try JSONDecoder().decode(Response.self, from: data)
            fiveHour = usage.five_hour.map(Self.window(from:))
            weekly = usage.seven_day.map(Self.window(from:))
            weeklySonnet = usage.seven_day_sonnet.map(Self.window(from:))
            lastUpdated = Date()
            log.notice("5h=\(self.fiveHour?.utilization ?? -1, format: .fixed(precision: 0))% weekly=\(self.weekly?.utilization ?? -1, format: .fixed(precision: 0))%")
        } catch {
            log.notice("usage fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Token (read from the Keychain via the `security` CLI; the item's
    // ACL already allows it — the same call `/usage` relies on).

    nonisolated private static func readToken() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    private static func window(from raw: RawWindow) -> Window {
        Window(utilization: raw.utilization ?? 0, resetsAt: parseDate(raw.resets_at))
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: - Wire decoding

    private struct Response: Decodable {
        let five_hour: RawWindow?
        let seven_day: RawWindow?
        let seven_day_sonnet: RawWindow?
    }

    private struct RawWindow: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
}
