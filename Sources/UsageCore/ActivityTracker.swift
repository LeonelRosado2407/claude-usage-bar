import Foundation

/// Watches each session's `status` and notifies when it finishes a long piece of work
/// (`busy` → `idle`) or has been waiting on the user (`waiting` / `blocked`) for a while.
/// Sessions are seeded silently when first seen; unknown statuses are ignored.
public struct ActivityTracker: Sendable {
    private struct State {
        var status: String?
        var busySince: Date?
        var waitingSince: Date?
        var waitingNotified = false
    }

    private static let attentionStatuses: Set<String> = ["waiting", "blocked"]

    private let config: AppConfig
    private var states: [String: State] = [:]

    public init(config: AppConfig) {
        self.config = config
    }

    public mutating func evaluate(_ rows: [SessionRow], now: Date) -> [Alert] {
        var next: [String: State] = [:]
        var alerts: [Alert] = []

        for row in rows {
            guard var state = states[row.id] else {
                next[row.id] = seed(row.status, now: now)
                continue
            }
            switch row.status {
            case "busy":
                // Keep the start time across a permission prompt; reset it after idle.
                if state.status != "busy", !Self.isAttention(state.status) || state.busySince == nil {
                    state.busySince = now
                }
                state.waitingSince = nil
                state.waitingNotified = false
                state.status = "busy"
            case "idle":
                if state.status == "busy", let since = state.busySince,
                   now.timeIntervalSince(since) >= config.notifyFinishedAfterSeconds {
                    alerts.append(Alert(id: "done-\(row.id)-\(Int(now.timeIntervalSince1970))",
                                        title: config.strings.finishedTitle(row.name),
                                        body: config.strings.finishedBody))
                }
                state = State(status: "idle")
            case let status? where Self.isAttention(status):
                if !Self.isAttention(state.status) {
                    state.waitingSince = now
                    state.waitingNotified = false
                }
                state.status = status
                if !state.waitingNotified, let since = state.waitingSince,
                   now.timeIntervalSince(since) >= config.notifyWaitingAfterSeconds {
                    state.waitingNotified = true
                    alerts.append(Alert(id: "wait-\(row.id)-\(Int(now.timeIntervalSince1970))",
                                        title: config.strings.waitingTitle(row.name),
                                        body: config.strings.waitingBody))
                }
            default:
                break  // unknown or missing status: leave state untouched
            }
            next[row.id] = state
        }
        states = next  // sessions that disappeared lose their state
        return config.notifyActivity ? alerts : []
    }

    private func seed(_ status: String?, now: Date) -> State {
        var state = State(status: status)
        if status == "busy" { state.busySince = now }
        if Self.isAttention(status) {
            state.waitingSince = now
            state.waitingNotified = true  // already waiting at launch: don't notify
        }
        return state
    }

    private static func isAttention(_ status: String?) -> Bool {
        status.map(attentionStatuses.contains) ?? false
    }
}
