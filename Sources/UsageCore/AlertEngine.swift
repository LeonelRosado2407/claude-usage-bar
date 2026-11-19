import Foundation

public struct Alert: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

/// Decides which notifications to send. Each threshold fires once per crossing and re-arms
/// when usage drops back below it (e.g. after `/compact`). Anything already above a threshold
/// when first seen — at launch, or a session that reappears — is recorded silently.
public struct AlertEngine: Sendable {
    private let config: AppConfig
    /// Session id → thresholds already notified (or already exceeded when first seen).
    private var fired: [String: Set<Double>] = [:]
    private var limitSeeded = false
    /// `resetsAt` of the 5-hour window already notified (`.some(nil)` = window without a date).
    private var limitFiredWindow: Date?? = nil

    public init(config: AppConfig) {
        self.config = config
    }

    public mutating func evaluate(_ snapshot: Snapshot) -> [Alert] {
        sessionAlerts(snapshot.interactive) + limitAlerts(snapshot.limits?.fiveHour)
    }

    private mutating func sessionAlerts(_ rows: [SessionRow]) -> [Alert] {
        let thresholds = Set(config.contextThresholds)
        var next: [String: Set<Double>] = [:]
        var alerts: [Alert] = []

        for row in rows {
            let pct = row.percent ?? 0
            let reached = thresholds.filter { pct >= $0 }
            guard let previous = fired[row.id] else {
                next[row.id] = reached  // first sighting: seed silently
                continue
            }
            let stillFired = previous.intersection(reached)  // drop thresholds we fell below
            let newlyCrossed = reached.subtracting(stillFired)
            if let top = newlyCrossed.max() {
                alerts.append(contextAlert(row: row, threshold: top, isHighest: top == thresholds.max()))
            }
            next[row.id] = reached
        }
        fired = next  // sessions that disappeared lose their state
        return alerts
    }

    private func contextAlert(row: SessionRow, threshold: Double, isHighest: Bool) -> Alert {
        let t = config.strings
        return Alert(id: "context-\(row.id)-\(Int(threshold))",
                     title: t.contextTitle(Int(threshold), row.name),
                     body: isHighest ? t.startNewChat : t.considerNewChat)
    }

    private mutating func limitAlerts(_ window: LimitWindow?) -> [Alert] {
        guard let window, let utilization = window.utilization else { return [] }
        let reached = utilization >= config.limitThreshold
        defer { limitSeeded = true }

        guard limitSeeded else {
            if reached { limitFiredWindow = .some(window.resetsAt) }
            return []
        }
        guard reached, limitFiredWindow != .some(window.resetsAt) else { return [] }
        limitFiredWindow = .some(window.resetsAt)

        let t = config.strings
        let body = window.resetsAt.map { t.resetsAt(t.time($0)) } ?? t.resetsSoon
        return [Alert(id: "limit-5h-\(window.resetsAt?.timeIntervalSince1970 ?? 0)",
                      title: t.limitTitle(Int(config.limitThreshold)),
                      body: body)]
    }
}
