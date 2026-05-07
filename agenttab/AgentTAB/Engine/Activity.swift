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
}
