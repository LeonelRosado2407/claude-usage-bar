import Foundation
import Testing
@testable import UsageCore

@Suite struct SessionRegistryTests {
    @Test func listsOnlyAlivePids() throws {
        let dir = try TempDir()
        try dir.write("100.json", sessionJSON(pid: 100, sessionId: "a"))
        try dir.write("200.json", sessionJSON(pid: 200, sessionId: "b"))
        let live = SessionRegistry.liveSessions(in: dir.url, isAlive: { $0 == 100 })
        #expect(live.map(\.pid) == [100])
        #expect(live.first?.sessionId == "a")
    }

    @Test func skipsMalformedAndIncomplete() throws {
        let dir = try TempDir()
        try dir.write("1.json", sessionJSON(pid: 1, sessionId: "ok"))
        try dir.write("2.json", "{")
        try dir.write("3.json", #"{"pid": 3, "cwd": "/tmp", "kind": "interactive"}"#)
        let live = SessionRegistry.liveSessions(in: dir.url, isAlive: { _ in true })
        #expect(live.map(\.sessionId) == ["ok"])
    }

    @Test func ignoresNonJSONFiles() throws {
        let dir = try TempDir()
        try dir.write("100.json", sessionJSON(pid: 100, sessionId: "a"))
        try dir.write("100.abc.key", "not json")
        #expect(SessionRegistry.liveSessions(in: dir.url, isAlive: { _ in true }).count == 1)
    }

    @Test func displayNameFallsBackToCwd() {
        let noName = SessionRecord(pid: 1, sessionId: "a", cwd: "/tmp/demo/mi-api",
                                   kind: "interactive", name: nil, entrypoint: "cli")
        #expect(noName.displayName == "mi-api")
        let named = SessionRecord(pid: 1, sessionId: "a", cwd: "/tmp/demo/mi-api",
                                  kind: "interactive", name: "Suite", entrypoint: "cli")
        #expect(named.displayName == "Suite")
        let empty = SessionRecord(pid: 1, sessionId: "a", cwd: "/tmp/demo/mi-api",
                                  kind: "interactive", name: "", entrypoint: "cli")
        #expect(empty.displayName == "mi-api")
    }

    @Test func bgIsNotInteractive() throws {
        let dir = try TempDir()
        try dir.write("1.json", sessionJSON(pid: 1, sessionId: "bg1", kind: "bg"))
        let live = SessionRegistry.liveSessions(in: dir.url, isAlive: { _ in true })
        #expect(live.first?.isInteractive == false)
    }

    @Test func missingDirReturnsEmpty() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(SessionRegistry.liveSessions(in: url).isEmpty)
    }

    @Test func currentProcessIsAlive() {
        #expect(SessionRegistry.processIsAlive(getpid()))
    }
}

@Suite struct BackgroundCommandsTests {
    @Test func parsesJobId() throws {
        let dir = try TempDir()
        try dir.write("1.json", #"{"pid": 1, "sessionId": "s", "cwd": "/tmp/a", "kind": "bg", "jobId": "1a2b3c4d"}"#)
        #expect(SessionRegistry.liveSessions(in: dir.url, isAlive: { _ in true }).first?.jobId == "1a2b3c4d")
    }

    @Test func attachScriptRunsClaudeAttach() {
        let script = BackgroundCommands.attachScript(jobId: "1a2b3c4d", cwd: "/tmp/demo/mi api")
        #expect(script == "#!/bin/zsh -l\ncd '/tmp/demo/mi api' 2>/dev/null\nexec claude attach 1a2b3c4d\n")
    }

    @Test func stopArgumentsUseLoginShell() {
        #expect(BackgroundCommands.stopArguments(jobId: "1a2b3c4d")
                == ["/bin/zsh", "-lc", "claude stop 1a2b3c4d"])
    }

    @Test func rejectsUnsafeIds() {
        #expect(BackgroundCommands.attachScript(jobId: "abc; rm -rf ~", cwd: "/tmp") == nil)
        #expect(BackgroundCommands.stopArguments(jobId: "$(whoami)") == nil)
        #expect(BackgroundCommands.stopArguments(jobId: "") == nil)
    }

    @Test func quotesCwdWithSingleQuote() {
        let script = BackgroundCommands.attachScript(jobId: "abc", cwd: "/tmp/it's")
        #expect(script?.contains(#"cd '/tmp/it'\''s'"#) == true)
    }

    @Test func rowCarriesJobId() {
        let rec = SessionRecord(pid: 1, sessionId: "s", cwd: "/tmp/a", kind: "bg", name: nil,
                                entrypoint: "cli", jobId: "1a2b3c4d")
        let rows = Snapshot.build(records: [rec], usage: { _ in nil }, config: AppConfig())
        #expect(rows.background.first?.jobId == "1a2b3c4d")
        #expect(rows.background.first?.cwd == "/tmp/a")
    }
}
