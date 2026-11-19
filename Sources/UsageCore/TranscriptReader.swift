import Foundation

/// Tokens currently occupying a session's context window.
public struct ContextUsage: Equatable, Sendable {
    public var tokens: Int
    public var model: String?

    public init(tokens: Int, model: String?) {
        self.tokens = tokens
        self.model = model
    }
}

/// Reads context usage from a Claude Code transcript (`~/.claude/projects/<dir>/<sessionId>.jsonl`).
public enum TranscriptReader {
    /// `~/.claude/projects`
    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Claude Code's folder name for a working directory: every non-alphanumeric ASCII char becomes `-`.
    public static func projectDirName(for cwd: String) -> String {
        String(cwd.map { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber) ? ch : "-"
        })
    }

    public static func locate(projectsDir: URL, cwd: String, sessionId: String) -> URL? {
        let fm = FileManager.default
        let fileName = "\(sessionId).jsonl"
        let direct = projectsDir
            .appendingPathComponent(projectDirName(for: cwd))
            .appendingPathComponent(fileName)
        if fm.fileExists(atPath: direct.path) { return direct }

        let subdirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return subdirs
            .map { $0.appendingPathComponent(fileName) }
            .first { fm.fileExists(atPath: $0.path) }
    }

    /// Usage of the last main-thread assistant message. Reads from the end of the file,
    /// widening the window until a match is found or the whole file has been scanned.
    public static func lastContextUsage(at url: URL, initialTailBytes: Int = 262_144) -> ContextUsage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

        var window = UInt64(max(initialTailBytes, 1))
        while true {
            let offset = size > window ? size - window : 0
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.readToEnd()
            else { return nil }

            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            // A tail that does not start at byte 0 may begin mid-line.
            if offset > 0, !lines.isEmpty { lines.removeFirst() }
            for line in lines.reversed() {
                if let usage = parse(line) { return usage }
            }
            if offset == 0 { return nil }
            window *= 2
        }
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var input_tokens: Int?
                var cache_read_input_tokens: Int?
                var cache_creation_input_tokens: Int?
            }
            var model: String?
            var usage: Usage?
        }
        var type: String?
        var isSidechain: Bool?
        var message: Message?
    }

    private static let usageMarker = Data(#""usage""#.utf8)

    private static func parse(_ line: Data.SubSequence) -> ContextUsage? {
        // Cheap pre-filter: most lines (user turns, tool output) carry no usage block.
        guard line.range(of: usageMarker) != nil,
              let decoded = try? JSONDecoder().decode(Line.self, from: Data(line)),
              decoded.type == "assistant",
              decoded.isSidechain != true,
              let usage = decoded.message?.usage
        else { return nil }
        let tokens = (usage.input_tokens ?? 0)
            + (usage.cache_read_input_tokens ?? 0)
            + (usage.cache_creation_input_tokens ?? 0)
        return ContextUsage(tokens: tokens, model: decoded.message?.model)
    }
}

/// Memoizes `lastContextUsage` per file, re-reading only when size or mtime change.
public final class TranscriptCache: @unchecked Sendable {
    private struct Entry {
        var size: Int
        var modified: Date
        var usage: ContextUsage?
    }

    private var entries: [URL: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func usage(at url: URL) -> ContextUsage? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let modified = attrs[.modificationDate] as? Date
        else { return nil }

        lock.lock()
        let cached = entries[url]
        lock.unlock()
        if let cached, cached.size == size, cached.modified == modified { return cached.usage }

        let usage = TranscriptReader.lastContextUsage(at: url)
        lock.lock()
        entries[url] = Entry(size: size, modified: modified, usage: usage)
        lock.unlock()
        return usage
    }

    /// Drops entries for files no longer of interest.
    public func retain(only urls: Set<URL>) {
        lock.lock()
        entries = entries.filter { urls.contains($0.key) }
        lock.unlock()
    }
}
