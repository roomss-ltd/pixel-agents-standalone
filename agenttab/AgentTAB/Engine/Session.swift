import Foundation

struct Session: Identifiable, Equatable {
    let id: UUID
    let claudeSessionId: String
    let projectName: String
    let projectPath: String
    var activity: Activity
    var currentTool: String?              // human-readable, e.g. "Editing foo.swift"
    var activeToolIds: Set<String>
    var activeToolNames: [String: String]    // toolId -> toolName
    var subagentTools: [String: Set<String>]
    var lastUpdate: Date
    var terminalKind: TerminalKind

    init(claudeSessionId: String, projectName: String, projectPath: String) {
        self.id = UUID()
        self.claudeSessionId = claudeSessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.activity = .idle
        self.currentTool = nil
        self.activeToolIds = []
        self.activeToolNames = [:]
        self.subagentTools = [:]
        self.lastUpdate = Date()
        self.terminalKind = .generic(nil)
    }
}

enum TerminalKind: Equatable {
    case generic(String?)              // optional term_program string
    case zellij(ZellijInfo)
}

struct ZellijInfo: Equatable {
    let paneId: Int
    let tabIndex: Int
    let tabName: String
    let zellijSession: String
}
