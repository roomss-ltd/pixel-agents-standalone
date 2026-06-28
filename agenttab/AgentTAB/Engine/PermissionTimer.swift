import Foundation

final class PermissionTimer {
    private var timers: [String: Task<Void, Never>] = [:]
    /// Tools that must NOT trip the 5s "awaiting input" heuristic. The read-only/
    /// quick tools never prompt; the long-running shell/editors (Bash/Edit/Write…)
    /// emit NO transcript output WHILE running, so — without hooks — a 20s `make`
    /// is indistinguishable from a tool paused for approval and would false-flag
    /// the session as `.waiting` (firing a spurious attention toast + AWP sound).
    static let exemptTools: Set<String> = [
        "AskUserQuestion", "Read", "Grep", "Glob", "ListDir",
        "Bash", "Edit", "Write", "MultiEdit", "NotebookEdit",
    ]
    static let delaySeconds: TimeInterval = 5

    func start(for sessionId: String, hasNonExemptTool: Bool, fire: @escaping () -> Void) {
        cancel(for: sessionId)
        guard hasNonExemptTool else { return }
        timers[sessionId] = Task {
            try? await Task.sleep(for: .seconds(Self.delaySeconds))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    func cancel(for sessionId: String) {
        timers[sessionId]?.cancel()
        timers[sessionId] = nil
    }
}
