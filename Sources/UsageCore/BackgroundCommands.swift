import Foundation

/// Shell commands for managing Claude Code background sessions (`claude attach` / `claude stop`).
/// Job ids are validated so nothing from disk can inject shell syntax.
public enum BackgroundCommands {
    static func isSafe(_ jobId: String) -> Bool {
        !jobId.isEmpty && jobId.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Contents of a `.command` file that Terminal runs to reattach to the session.
    public static func attachScript(jobId: String, cwd: String) -> String? {
        guard isSafe(jobId) else { return nil }
        return "#!/bin/zsh -l\ncd \(singleQuoted(cwd)) 2>/dev/null\nexec claude attach \(jobId)\n"
    }

    /// Process arguments that stop the session (a login shell so `claude` is on PATH).
    public static func stopArguments(jobId: String) -> [String]? {
        guard isSafe(jobId) else { return nil }
        return ["/bin/zsh", "-lc", "claude stop \(jobId)"]
    }

    private static func singleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
