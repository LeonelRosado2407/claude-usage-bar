import Foundation

/// One running Claude Code process, as listed in `~/.claude/sessions/<pid>.json`.
public struct SessionRecord: Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var kind: String
    public var name: String?
    public var entrypoint: String?
    /// Short id used by `claude attach/stop` (background sessions only).
    public var jobId: String?
    /// Claude Code's activity state: `busy`, `idle`, `waiting`, `blocked`, …
    public var status: String?

    public init(pid: Int32, sessionId: String, cwd: String, kind: String,
                name: String?, entrypoint: String?, jobId: String? = nil, status: String? = nil) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.kind = kind
        self.name = name
        self.entrypoint = entrypoint
        self.jobId = jobId
        self.status = status
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public var isInteractive: Bool { kind == "interactive" }
}

public enum SessionRegistry {
    /// `~/.claude/sessions`
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    /// Sessions whose registry file parses and whose process is still running.
    public static func liveSessions(
        in dir: URL,
        isAlive: (Int32) -> Bool = SessionRegistry.processIsAlive
    ) -> [SessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(parse)
            .filter { isAlive($0.pid) }
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private struct Raw: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var kind: String?
        var name: String?
        var entrypoint: String?
        var jobId: String?
        var status: String?
    }

    private static func parse(_ url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(Raw.self, from: data)
        else { return nil }
        return SessionRecord(pid: raw.pid, sessionId: raw.sessionId, cwd: raw.cwd,
                             kind: raw.kind ?? "interactive", name: raw.name,
                             entrypoint: raw.entrypoint, jobId: raw.jobId, status: raw.status)
    }
}
