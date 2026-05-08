import Foundation

final class PermissionTimer {
    private var timers: [String: Task<Void, Never>] = [:]
    static let exemptTools: Set<String> = ["AskUserQuestion", "Read", "Grep", "Glob", "ListDir"]
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
