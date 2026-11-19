import Foundation
import Testing
@testable import UsageCore

@Suite struct ConfigTests {
    @Test func defaultsMatchSpec() {
        let c = AppConfig()
        #expect(c.barWarn == 70)
        #expect(c.barCritical == 90)
        #expect(c.contextThresholds == [80, 90])
        #expect(c.limitThreshold == 90)
        #expect(c.sessionPollSeconds == 5)
        #expect(c.limitsPollSeconds == 300)
        #expect(c.defaultContextWindow == 1_000_000)
        #expect(c.modelContextWindows.isEmpty)
    }

    @Test func windowUsesLongestPrefix() {
        var c = AppConfig()
        c.modelContextWindows = ["claude-haiku": 200_000, "claude-haiku-5-5": 300_000]
        #expect(c.contextWindow(for: "claude-haiku-5-5") == 300_000)
        #expect(c.contextWindow(for: "claude-haiku-4") == 200_000)
        #expect(c.contextWindow(for: "claude-opus-5-5") == 1_000_000)
        #expect(c.contextWindow(for: nil) == 1_000_000)
    }

    @Test func loadOrCreateWritesDefaults() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("sub/config.json")
        #expect(AppConfig.loadOrCreate(at: url) == AppConfig())
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func partialJSONKeepsDefaults() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("config.json")
        try Data(#"{"limitsPollSeconds": 600}"#.utf8).write(to: url)
        let c = AppConfig.loadOrCreate(at: url)
        #expect(c.limitsPollSeconds == 600)
        #expect(c.barWarn == 70)
    }

    @Test func invalidJSONReturnsDefaultsAndKeepsFile() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("config.json")
        try Data("{oops".utf8).write(to: url)
        #expect(AppConfig.loadOrCreate(at: url) == AppConfig())
        #expect(try String(contentsOf: url, encoding: .utf8) == "{oops")
    }

    @Test func loadAddsMissingKeysKeepingValues() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("config.json")
        try Data(#"{"limitsPollSeconds": 600}"#.utf8).write(to: url)
        _ = AppConfig.loadOrCreate(at: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"notifyActivity\""))
        #expect(text.contains("\"limitsPollSeconds\" : 600"))
    }
}
