import Foundation
import Testing
@testable import UsageCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func row(_ status: String?, name: String = "mi-api", interactive: Bool = true) -> SessionRow {
    SessionRow(id: "id-\(name)", name: name, model: nil, tokens: nil, window: 1_000_000,
               isInteractive: interactive, status: status)
}

@Suite struct ActivityTrackerTests {
    @Test func firstSightingIsSilent() {
        var tracker = ActivityTracker(config: AppConfig())
        #expect(tracker.evaluate([row("waiting")], now: t0).isEmpty)
        #expect(tracker.evaluate([row("waiting")], now: t0 + 60).isEmpty)
    }

    @Test func finishedAfterLongBusy() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("idle")], now: t0)
        _ = tracker.evaluate([row("busy")], now: t0 + 5)
        _ = tracker.evaluate([row("busy")], now: t0 + 30)
        let alerts = tracker.evaluate([row("idle")], now: t0 + 40)
        #expect(alerts.map(\.title) == ["✓ mi-api terminó"])
        #expect(alerts.first?.body == "Listo para tu siguiente mensaje.")
        #expect(tracker.evaluate([row("idle")], now: t0 + 45).isEmpty)
    }

    @Test func shortBusyIsSilent() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("idle")], now: t0)
        _ = tracker.evaluate([row("busy")], now: t0 + 5)
        #expect(tracker.evaluate([row("idle")], now: t0 + 20).isEmpty)
    }

    @Test func waitingAlertsAfterDelayOnce() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("idle")], now: t0)
        _ = tracker.evaluate([row("busy")], now: t0 + 5)
        #expect(tracker.evaluate([row("waiting")], now: t0 + 10).isEmpty)
        #expect(tracker.evaluate([row("waiting")], now: t0 + 20).isEmpty)
        let alerts = tracker.evaluate([row("waiting")], now: t0 + 26)
        #expect(alerts.map(\.title) == ["⏸ mi-api necesita tu respuesta"])
        #expect(alerts.first?.body == "Claude está esperando tu permiso o respuesta.")
        #expect(tracker.evaluate([row("waiting")], now: t0 + 60).isEmpty)
    }

    @Test func answeredQuicklyIsSilent() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("busy")], now: t0)
        _ = tracker.evaluate([row("blocked")], now: t0 + 5)
        #expect(tracker.evaluate([row("busy")], now: t0 + 10).isEmpty)
        #expect(tracker.evaluate([row("blocked")], now: t0 + 30).isEmpty)
        #expect(tracker.evaluate([row("blocked")], now: t0 + 46).count == 1)
    }

    @Test func busyTimeSurvivesPermissionPrompt() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("idle")], now: t0)
        _ = tracker.evaluate([row("busy")], now: t0 + 1)
        _ = tracker.evaluate([row("waiting")], now: t0 + 10)
        _ = tracker.evaluate([row("busy")], now: t0 + 12)
        #expect(tracker.evaluate([row("idle")], now: t0 + 35).map(\.title) == ["✓ mi-api terminó"])
    }

    @Test func unknownStatusIsIgnored() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("busy")], now: t0)
        #expect(tracker.evaluate([row("starting")], now: t0 + 60).isEmpty)
        #expect(tracker.evaluate([row(nil)], now: t0 + 90).isEmpty)
        #expect(tracker.evaluate([row("idle")], now: t0 + 95).count == 1)
    }

    @Test func backgroundSessionsAlsoNotify() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("busy", name: "suite", interactive: false)], now: t0)
        #expect(tracker.evaluate([row("idle", name: "suite", interactive: false)], now: t0 + 60)
            .map(\.title) == ["✓ suite terminó"])
    }

    @Test func disabledInConfig() {
        var config = AppConfig()
        config.notifyActivity = false
        var tracker = ActivityTracker(config: config)
        _ = tracker.evaluate([row("busy")], now: t0)
        #expect(tracker.evaluate([row("idle")], now: t0 + 60).isEmpty)
    }

    @Test func alertIdsAreUniquePerEvent() {
        var tracker = ActivityTracker(config: AppConfig())
        _ = tracker.evaluate([row("busy")], now: t0)
        let first = tracker.evaluate([row("idle")], now: t0 + 60)
        _ = tracker.evaluate([row("busy")], now: t0 + 70)
        let second = tracker.evaluate([row("idle")], now: t0 + 130)
        #expect(first.count == 1 && second.count == 1)
        #expect(first.first?.id != second.first?.id)
    }

    @Test func registryParsesStatus() throws {
        let dir = try TempDir()
        try dir.write("1.json", #"{"pid": 1, "sessionId": "s", "cwd": "/tmp/a", "kind": "interactive", "status": "busy"}"#)
        let records = SessionRegistry.liveSessions(in: dir.url, isAlive: { _ in true })
        #expect(records.first?.status == "busy")
        let rows = Snapshot.build(records: records, usage: { _ in nil }, config: AppConfig())
        #expect(rows.interactive.first?.status == "busy")
    }

    @Test func configDefaults() {
        let c = AppConfig()
        #expect(c.notifyActivity == true)
        #expect(c.notifyFinishedAfterSeconds == 30)
        #expect(c.notifyWaitingAfterSeconds == 15)
    }
}
