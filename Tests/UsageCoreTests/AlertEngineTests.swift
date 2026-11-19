import Foundation
import Testing
@testable import UsageCore

private func snap(_ sessions: [(String, Double)], background: [(String, Double)] = [],
                  fiveHour: Double? = nil, resetsAt: Date? = nil) -> Snapshot {
    func rows(_ list: [(String, Double)], interactive: Bool) -> [SessionRow] {
        list.map { name, pct in
            SessionRow(id: "id-\(name)", name: name, model: nil, tokens: Int(pct * 10_000),
                       window: 1_000_000, isInteractive: interactive)
        }
    }
    return Snapshot(interactive: rows(sessions, interactive: true),
                    background: rows(background, interactive: false),
                    limits: fiveHour.map { UsageLimits(fiveHour: LimitWindow(utilization: $0, resetsAt: resetsAt), sevenDay: nil) })
}

@Suite struct AlertEngineTests {
    @Test func firstEvaluationIsSilent() {
        var engine = AlertEngine(config: AppConfig())
        #expect(engine.evaluate(snap([("mi-api", 85)])).isEmpty)
        #expect(engine.evaluate(snap([("mi-api", 85)])).isEmpty)
    }

    @Test func firesOncePerThreshold() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([("mi-api", 50)]))
        let alerts = engine.evaluate(snap([("mi-api", 82)]))
        #expect(alerts.map(\.title) == ["Contexto al 80% en mi-api"])
        #expect(alerts.first?.body == "Considera iniciar un chat nuevo.")
        #expect(engine.evaluate(snap([("mi-api", 84)])).isEmpty)
    }

    @Test func secondThresholdAfterFirst() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([("mi-api", 50)]))
        _ = engine.evaluate(snap([("mi-api", 82)]))
        let alerts = engine.evaluate(snap([("mi-api", 91)]))
        #expect(alerts.map(\.title) == ["Contexto al 90% en mi-api"])
        #expect(alerts.first?.body == "Inicia un chat nuevo.")
    }

    @Test func jumpEmitsOnlyHighest() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([("mi-api", 50)]))
        #expect(engine.evaluate(snap([("mi-api", 95)])).map(\.title) == ["Contexto al 90% en mi-api"])
        #expect(engine.evaluate(snap([("mi-api", 96)])).isEmpty)
    }

    @Test func rearmsAfterCompact() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([("mi-api", 50)]))
        #expect(engine.evaluate(snap([("mi-api", 85)])).count == 1)
        #expect(engine.evaluate(snap([("mi-api", 30)])).isEmpty)
        #expect(engine.evaluate(snap([("mi-api", 85)])).count == 1)
    }

    @Test func ignoresBackgroundSessions() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([], background: [("suite", 50)]))
        #expect(engine.evaluate(snap([], background: [("suite", 95)])).isEmpty)
    }

    @Test func limitFiresOncePerResetWindow() {
        var engine = AlertEngine(config: AppConfig())
        let r1 = Date(timeIntervalSince1970: 1_000_000)
        let r2 = Date(timeIntervalSince1970: 2_000_000)
        _ = engine.evaluate(snap([], fiveHour: 50, resetsAt: r1))
        let alerts = engine.evaluate(snap([], fiveHour: 92, resetsAt: r1))
        #expect(alerts.map(\.title) == ["Llevas 90% del límite de 5 horas"])
        #expect(alerts.first?.body.hasPrefix("Reinicia a las ") == true)
        #expect(engine.evaluate(snap([], fiveHour: 95, resetsAt: r1)).isEmpty)
        #expect(engine.evaluate(snap([], fiveHour: 91, resetsAt: r2)).count == 1)
    }

    @Test func limitWithoutResetDate() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([], fiveHour: 50))
        #expect(engine.evaluate(snap([], fiveHour: 92)).first?.body == "Reinicia pronto.")
    }

    @Test func sessionGoneDropsState() {
        var engine = AlertEngine(config: AppConfig())
        _ = engine.evaluate(snap([("mi-api", 85)]))
        _ = engine.evaluate(snap([]))
        #expect(engine.evaluate(snap([("mi-api", 85)])).isEmpty)
        // A session that first appears after launch below the threshold alerts when it crosses.
        #expect(engine.evaluate(snap([("mi-api", 85), ("nueva", 50)])).isEmpty)
        #expect(engine.evaluate(snap([("mi-api", 85), ("nueva", 82)])).map(\.title)
                == ["Contexto al 80% en nueva"])
    }
}
