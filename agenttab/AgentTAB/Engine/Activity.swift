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

    /// States that only make sense while the agent is alive and moving.
    /// The engine's staleness sweep ages these out when nothing has proven
    /// the agent is still there — an agent that is killed, crashes, or is
    /// Ctrl-C'd never sends `Stop`/`SessionEnd`, so without a sweep it stays
    /// pinned here forever and the tab reads as "processing" indefinitely.
    ///
    /// `.waiting` is deliberately NOT transient: a permission prompt
    /// legitimately sits on screen for hours while the user is away, and
    /// ageing it out would hide a tab that genuinely needs attention.
    var isTransient: Bool {
        switch self {
        case .initState, .thinking, .tool: return true
        case .waiting, .done, .idle:       return false
        }
    }
}
