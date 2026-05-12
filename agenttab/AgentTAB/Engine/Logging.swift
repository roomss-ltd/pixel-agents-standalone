import Foundation
import os

enum AgentLog {
    static let subsystem = "com.roomss.agenttab"

    static let engine    = Logger(subsystem: subsystem, category: "engine")
    static let watcher   = Logger(subsystem: subsystem, category: "watcher")
    static let parser    = Logger(subsystem: subsystem, category: "parser")
    static let notify    = Logger(subsystem: subsystem, category: "notify")
    static let zellij    = Logger(subsystem: subsystem, category: "zellij")
    static let screen    = Logger(subsystem: subsystem, category: "screen")
    static let panel     = Logger(subsystem: subsystem, category: "panel")
}

extension Activity {
    var logTag: String {
        switch self {
        case .initState:   return "init"
        case .thinking:    return "thinking"
        case .tool(let n): return "tool(\(n))"
        case .waiting:     return "waiting"
        case .done:        return "done"
        case .idle:        return "idle"
        }
    }
}
