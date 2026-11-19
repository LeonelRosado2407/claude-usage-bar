import Foundation
import Testing
@testable import UsageCore

private func record(_ id: String, kind: String = "interactive") -> SessionRecord {
    SessionRecord(pid: 1, sessionId: id, cwd: "/tmp/demo/\(id)", kind: kind, name: nil, entrypoint: "cli")
}

private func limits(_ fiveHour: Double?) -> UsageLimits {
    UsageLimits(fiveHour: LimitWindow(utilization: fiveHour, resetsAt: nil), sevenDay: nil)
}

@Suite struct SnapshotTests {
    @Test func splitsAndSortsGroups() {
        let usage: [String: ContextUsage] = [
            "a": ContextUsage(tokens: 100_000, model: nil),  // 10%
            "c": ContextUsage(tokens: 910_000, model: nil),  // 91%
            "bg": ContextUsage(tokens: 500_000, model: nil),
        ]
        let rows = Snapshot.build(
            records: [record("a"), record("b"), record("c"), record("bg", kind: "bg")],
            usage: { usage[$0.sessionId] }, config: AppConfig())
        #expect(rows.interactive.map(\.id) == ["c", "a", "b"])
        #expect(rows.interactive.last?.percent == nil)
        #expect(rows.background.map(\.id) == ["bg"])
        #expect(rows.background.first?.isInteractive == false)
    }

    @Test func percentUsesModelWindow() {
        var config = AppConfig()
        config.modelContextWindows = ["claude-haiku": 200_000]
        let haiku = Snapshot.build(records: [record("a")],
                                   usage: { _ in ContextUsage(tokens: 150_000, model: "claude-haiku-5-5") },
                                   config: config)
        #expect(haiku.interactive.first?.percent == 75)
        let opus = Snapshot.build(records: [record("a")],
                                  usage: { _ in ContextUsage(tokens: 150_000, model: "claude-opus-5-5") },
                                  config: config)
        #expect(opus.interactive.first?.percent == 15)
    }

    @Test func percentCanExceed100() {
        let row = SessionRow(id: "a", name: "a", model: nil, tokens: 250_000, window: 200_000, isInteractive: true)
        #expect(row.percent == 125)
    }

    @Test func barLevelThresholds() {
        let c = AppConfig()
        #expect(Snapshot(limits: limits(69.9)).barLevel(config: c) == .normal)
        #expect(Snapshot(limits: limits(70)).barLevel(config: c) == .warn)
        #expect(Snapshot(limits: limits(90)).barLevel(config: c) == .critical)
        #expect(Snapshot().barLevel(config: c) == .normal)
    }

    @Test func warningIgnoresBackground() {
        let c = AppConfig()
        let bg = SessionRow(id: "b", name: "b", model: nil, tokens: 950_000, window: 1_000_000, isInteractive: false)
        let low = SessionRow(id: "a", name: "a", model: nil, tokens: 790_000, window: 1_000_000, isInteractive: true)
        #expect(Snapshot(interactive: [low], background: [bg]).hasContextWarning(config: c) == false)
        let high = SessionRow(id: "a", name: "a", model: nil, tokens: 800_000, window: 1_000_000, isInteractive: true)
        #expect(Snapshot(interactive: [high]).hasContextWarning(config: c) == true)
    }

    @Test func barTitleFormats() {
        #expect(Snapshot(limits: limits(42.4)).barTitle == "◐ 42%")
        #expect(Snapshot(limits: limits(nil)).barTitle == "◐ —")
        #expect(Snapshot().barTitle == "◐ —")
    }

    @Test func demoHasNoRealNames() {
        let demo = DemoData.snapshot(now: Date())
        #expect(demo.interactive.map(\.name) == ["mi-api", "portafolio"])
        #expect(demo.background.map(\.name) == ["suite-pruebas"])
        #expect(demo.interactive.first.flatMap(\.percent).map { $0.rounded() } == 91)
        #expect(demo.limits?.fiveHour?.utilization == 78)
        #expect(demo.limits?.sevenDay?.utilization == 31)
    }
}
