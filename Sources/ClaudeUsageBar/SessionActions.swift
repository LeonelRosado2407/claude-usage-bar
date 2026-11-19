import AppKit
import UsageCore

/// Side effects for background sessions: reattach in Terminal, or stop.
enum SessionActions {
    /// Writes a `.command` file and opens it, which launches a new Terminal window running `claude attach`.
    static func openInTerminal(jobId: String, cwd: String) {
        guard let script = BackgroundCommands.attachScript(jobId: jobId, cwd: cwd) else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageBar")
        let file = dir.appendingPathComponent("attach-\(jobId).command")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(script.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch { return }
        NSWorkspace.shared.open(file)
    }

    /// Runs `claude stop <id>`; returns whether it exited successfully.
    static func stop(jobId: String) async -> Bool {
        guard let args = BackgroundCommands.stopArguments(jobId: jobId) else { return false }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}
