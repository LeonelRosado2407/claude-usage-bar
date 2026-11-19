import Foundation

/// One line of the session list.
public struct SessionRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var model: String?
    /// `nil` until the session has an assistant reply.
    public var tokens: Int?
    public var window: Int
    public var isInteractive: Bool
    public var jobId: String?
    public var cwd: String?
    public var status: String?

    public init(id: String, name: String, model: String?, tokens: Int?, window: Int, isInteractive: Bool,
                jobId: String? = nil, cwd: String? = nil, status: String? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.tokens = tokens
        self.window = window
        self.isInteractive = isInteractive
        self.jobId = jobId
        self.cwd = cwd
        self.status = status
    }

    /// Share of the context window in use; may exceed 100 if the window is misconfigured.
    public var percent: Double? {
        guard let tokens, window > 0 else { return nil }
        return Double(tokens) / Double(window) * 100
    }
}

public enum BarLevel: Sendable {
    case normal, warn, critical

    public static func level(for percent: Double?, config: AppConfig) -> BarLevel {
        guard let percent else { return .normal }
        if percent >= config.barCritical { return .critical }
        if percent >= config.barWarn { return .warn }
        return .normal
    }
}

/// Everything the menu bar and panel render.
public struct Snapshot: Equatable, Sendable {
    public var interactive: [SessionRow]
    public var background: [SessionRow]
    public var limits: UsageLimits?
    public var limitsUpdatedAt: Date?
    public var limitsError: LimitsError?

    public init(interactive: [SessionRow] = [], background: [SessionRow] = [],
                limits: UsageLimits? = nil, limitsUpdatedAt: Date? = nil, limitsError: LimitsError? = nil) {
        self.interactive = interactive
        self.background = background
        self.limits = limits
        self.limitsUpdatedAt = limitsUpdatedAt
        self.limitsError = limitsError
    }

    public static func build(
        records: [SessionRecord],
        usage: (SessionRecord) -> ContextUsage?,
        config: AppConfig
    ) -> (interactive: [SessionRow], background: [SessionRow]) {
        let rows = records.map { record -> SessionRow in
            let u = usage(record)
            return SessionRow(id: record.sessionId, name: record.displayName, model: u?.model,
                              tokens: u?.tokens, window: config.contextWindow(for: u?.model),
                              isInteractive: record.isInteractive, jobId: record.jobId, cwd: record.cwd,
                              status: record.status)
        }
        let sorted = rows.sorted { ($0.percent ?? -1) > ($1.percent ?? -1) }
        return (sorted.filter(\.isInteractive), sorted.filter { !$0.isInteractive })
    }

    public func barLevel(config: AppConfig) -> BarLevel {
        BarLevel.level(for: limits?.fiveHour?.utilization, config: config)
    }

    public func hasContextWarning(config: AppConfig) -> Bool {
        guard let first = config.contextThresholds.min() else { return false }
        return interactive.contains { ($0.percent ?? 0) >= first }
    }

    public var barTitle: String {
        guard let u = limits?.fiveHour?.utilization else { return "◐ —" }
        return "◐ \(Int(u.rounded()))%"
    }
}
