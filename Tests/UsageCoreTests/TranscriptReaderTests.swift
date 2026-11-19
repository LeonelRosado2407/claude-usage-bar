import Foundation
import Testing
@testable import UsageCore

@Suite struct TranscriptReaderTests {
    private func jsonl(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    @Test func encodesProjectDir() {
        #expect(TranscriptReader.projectDirName(for: "/Users/demo/projects") == "-Users-demo-projects")
        #expect(TranscriptReader.projectDirName(for: "/Users/demo/my files/app.v2")
                == "-Users-demo-my-files-app-v2")
    }

    @Test func sumsTokensOfLastAssistant() throws {
        let dir = try TempDir()
        let url = try dir.write("s.jsonl", jsonl([
            userLine(),
            assistantLine(input: 10, cacheRead: 100, cacheCreation: 5),
            userLine(),
            assistantLine(input: 2, cacheRead: 700_000, cacheCreation: 1_000),
        ]))
        #expect(TranscriptReader.lastContextUsage(at: url)
                == ContextUsage(tokens: 701_002, model: "claude-opus-5-5"))
    }

    @Test func skipsSidechainAndNonAssistant() throws {
        let dir = try TempDir()
        let url = try dir.write("s.jsonl", jsonl([
            assistantLine(input: 1, cacheRead: 1, cacheCreation: 1),
            assistantLine(input: 9, cacheRead: 9, cacheCreation: 9, sidechain: true),
            userLine(),
        ]))
        #expect(TranscriptReader.lastContextUsage(at: url)?.tokens == 3)
    }

    @Test func ignoresTruncatedLastLine() throws {
        let dir = try TempDir()
        let url = try dir.write("s.jsonl", jsonl([
            assistantLine(input: 1, cacheRead: 2, cacheCreation: 3),
        ]) + #"{"type":"assistant","mess"#)
        #expect(TranscriptReader.lastContextUsage(at: url)?.tokens == 6)
    }

    @Test func expandsBeyondTail() throws {
        let dir = try TempDir()
        let big = String(repeating: "x", count: 600_000)
        let url = try dir.write("s.jsonl", jsonl([
            assistantLine(input: 4, cacheRead: 5, cacheCreation: 6),
            userLine(big),
        ]))
        #expect(TranscriptReader.lastContextUsage(at: url, initialTailBytes: 1024)?.tokens == 15)
    }

    @Test func noAssistantReturnsNil() throws {
        let dir = try TempDir()
        let url = try dir.write("s.jsonl", jsonl([userLine(), userLine()]))
        #expect(TranscriptReader.lastContextUsage(at: url) == nil)
    }

    @Test func missingFileReturnsNil() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).jsonl")
        #expect(TranscriptReader.lastContextUsage(at: url) == nil)
    }

    @Test func locatesByEncodedPath() throws {
        let dir = try TempDir()
        let file = try dir.write("-tmp-demo-mi-api/abc.jsonl", jsonl([userLine()]))
        #expect(TranscriptReader.locate(projectsDir: dir.url, cwd: "/tmp/demo/mi-api", sessionId: "abc")?
            .standardizedFileURL == file.standardizedFileURL)
    }

    @Test func locateFallsBackToSearch() throws {
        let dir = try TempDir()
        let file = try dir.write("otro-nombre/abc.jsonl", jsonl([userLine()]))
        #expect(TranscriptReader.locate(projectsDir: dir.url, cwd: "/tmp/demo/mi-api", sessionId: "abc")?
            .standardizedFileURL == file.standardizedFileURL)
        #expect(TranscriptReader.locate(projectsDir: dir.url, cwd: "/tmp/x", sessionId: "zzz") == nil)
    }

    @Test func cacheRereadsOnChange() throws {
        let dir = try TempDir()
        let url = try dir.write("s.jsonl", jsonl([assistantLine(input: 1, cacheRead: 0, cacheCreation: 0)]))
        let cache = TranscriptCache()
        #expect(cache.usage(at: url)?.tokens == 1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((assistantLine(input: 50, cacheRead: 0, cacheCreation: 0) + "\n").utf8))
        try handle.close()
        #expect(cache.usage(at: url)?.tokens == 50)
    }
}
