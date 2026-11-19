import Foundation
import Testing
@testable import UsageCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func english() -> AppConfig {
    var c = AppConfig()
    c.language = .en
    return c
}

private func row(_ pct: Double, status: String? = nil) -> SessionRow {
    SessionRow(id: "id-a", name: "my-api", model: nil, tokens: Int(pct * 10_000), window: 1_000_000,
               isInteractive: true, status: status)
}

@Suite struct LanguageTests {
    @Test func defaultsToSpanish() {
        #expect(AppConfig().language == .es)
    }

    @Test func decodesLanguageAndFallsBackOnUnknown() throws {
        let en = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"language": "en"}"#.utf8))
        #expect(en.language == .en)
        let unknown = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"language": "fr", "barWarn": 60}"#.utf8))
        #expect(unknown.language == .es)
        #expect(unknown.barWarn == 60)
    }

    @Test func saveWritesLanguage() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("config.json")
        try english().save(to: url)
        #expect(AppConfig.loadOrCreate(at: url).language == .en)
    }

    @Test func contextAlertsInEnglish() {
        var engine = AlertEngine(config: english())
        _ = engine.evaluate(Snapshot(interactive: [row(50)]))
        let a = engine.evaluate(Snapshot(interactive: [row(82)]))
        #expect(a.map(\.title) == ["Context at 80% in my-api"])
        #expect(a.first?.body == "Consider starting a new chat.")
        let b = engine.evaluate(Snapshot(interactive: [row(91)]))
        #expect(b.first?.body == "Start a new chat.")
    }

    @Test func limitAlertInEnglish() {
        var engine = AlertEngine(config: english())
        let limits = { (u: Double) in
            UsageLimits(fiveHour: LimitWindow(utilization: u, resetsAt: nil), sevenDay: nil)
        }
        _ = engine.evaluate(Snapshot(limits: limits(50)))
        let a = engine.evaluate(Snapshot(limits: limits(92)))
        #expect(a.map(\.title) == ["You've used 90% of your 5-hour limit"])
        #expect(a.first?.body == "Resets soon.")
    }

    @Test func activityAlertsInEnglish() {
        var tracker = ActivityTracker(config: english())
        _ = tracker.evaluate([row(10, status: "busy")], now: t0)
        #expect(tracker.evaluate([row(10, status: "idle")], now: t0 + 60).map(\.title) == ["✓ my-api finished"])
        _ = tracker.evaluate([row(10, status: "busy")], now: t0 + 70)
        let w = tracker.evaluate([row(10, status: "waiting")], now: t0 + 75)
        #expect(w.isEmpty)
        let w2 = tracker.evaluate([row(10, status: "waiting")], now: t0 + 95)
        #expect(w2.map(\.title) == ["⏸ my-api needs your input"])
        #expect(w2.first?.body == "Claude is waiting for your permission or answer.")
    }

    @Test func timeFormatFollowsLanguage() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 15, minute: 40))!
        #expect(Strings.for(.es).time(date) == "3:40 p.m.")
        #expect(Strings.for(.en).time(date) == "3:40 PM")
        #expect(Strings.for(.es).weekdayTime(date) == "lun 15:40")
        #expect(Strings.for(.en).weekdayTime(date) == "Mon 15:40")
    }

    @Test func panelStringsDiffer() {
        let es = Strings.for(.es), en = Strings.for(.en)
        #expect(es.fiveHourLimit == "Límite 5h" && en.fiveHourLimit == "5h limit")
        #expect(es.updatedMinutesAgo(3) == "Actualizado hace 3 min")
        #expect(en.updatedMinutesAgo(3) == "Updated 3 min ago")
        #expect(en.resets("Mon 9:00") == "resets Mon 9:00")
    }
}
