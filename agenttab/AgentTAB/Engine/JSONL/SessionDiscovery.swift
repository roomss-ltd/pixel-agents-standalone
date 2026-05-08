import Foundation

enum SessionDiscovery {
    /// Recover a display name like "my-repo" or "my-repo/feat-x" from a Claude
    /// projects-directory hash like "-Users-adi-Desktop-my-repo--worktrees-feat-x".
    static func hashToProjectName(_ hash: String) -> String {
        let parts = hash.split(separator: "-").filter { !$0.isEmpty }.map(String.init)
        guard let desktopIdx = parts.firstIndex(of: "Desktop") else {
            return parts.last ?? hash
        }
        let afterDesktop = Array(parts[(desktopIdx + 1)...])
        guard let worktreeIdx = afterDesktop.firstIndex(where: { $0 == "worktrees" || $0 == "worktree" }) else {
            return afterDesktop.joined(separator: "-")
        }
        let repo = afterDesktop[..<worktreeIdx].joined(separator: "-")
        let branch = afterDesktop[(worktreeIdx + 1)...].joined(separator: "-")
        return branch.isEmpty ? repo : "\(repo)/\(branch)"
    }
}
