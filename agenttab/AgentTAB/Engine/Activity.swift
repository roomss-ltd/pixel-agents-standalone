import Foundation

enum Activity: Equatable {
    case initState
    case thinking
    case tool(String)        // tool name, e.g. "Bash", "Read"
    case waiting             // permission needed or end of turn
    case done                // recently finished, lingers 30s
    case idle                // long stale
}

extension Activity {
    /// True while the agent is actively working a turn — the run clock
    /// counts during these states. `.waiting` still counts (the turn
    /// hasn't finished, it's just paused for approval); only `.done` and
    /// `.idle` stop the clock.
    var isRunning: Bool {
        switch self {
        case .initState, .thinking, .tool, .waiting: return true
        case .done, .idle:                           return false
        }
    }

    var rank: Int {
        switch self {
        case .waiting:   return 5
        case .tool:      return 4
        case .thinking:  return 3
        case .done:      return 2
        case .initState: return 1
        case .idle:      return 0
        }
    }
}
