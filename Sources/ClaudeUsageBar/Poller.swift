import AppKit
import Foundation
import UsageCore

/// Owns the refresh timers and publishes the latest snapshot.
@MainActor
final class Poller: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    @Published private(set) var isFetchingLimits = false
    @Published private(set) var config: AppConfig

    private let demo: Bool
    private let configURL: URL?
    private var configModified: Date?
    private let cache = TranscriptCache()
    private let limitsClient = LimitsClient(tokenProvider: KeychainTokenProvider())
    private var alerts: AlertEngine
    private var activity: ActivityTracker
    private var timers: [Timer] = []

    init(config: AppConfig, demo: Bool, configURL: URL? = nil) {
        self.config = config
        self.demo = demo
        self.configURL = demo ? nil : configURL
        self.configModified = configURL.flatMap(Self.modificationDate)
        self.alerts = AlertEngine(config: config)
        self.activity = ActivityTracker(config: config)
        self.snapshot = demo ? DemoData.snapshot(now: Date()) : Snapshot()
        guard !demo else { return }

        refreshSessions()
        refreshLimits()
        scheduleTimers()
    }

    func refreshNow() {
        guard !demo else { return }
        refreshSessions()
        refreshLimits()
    }

    /// Opens config.json in the user's editor, creating it with defaults if needed.
    func openConfig() {
        let url = configURL ?? AppConfig.defaultURL
        _ = AppConfig.loadOrCreate(at: url)
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Switches the UI/notification language and persists it to config.json.
    func setLanguage(_ language: AppLanguage) {
        guard language != config.language else { return }
        var next = config
        next.language = language
        if let url = configURL {
            try? next.save(to: url)
            configModified = Self.modificationDate(url)
        }
        apply(next)
    }

    /// Stops a background session, then refreshes so it disappears from the list.
    func stopSession(jobId: String) async -> Bool {
        guard !demo else { return false }
        let ok = await SessionActions.stop(jobId: jobId)
        refreshSessions()
        return ok
    }

    func openInTerminal(_ row: SessionRow) {
        guard !demo, let jobId = row.jobId else { return }
        SessionActions.openInTerminal(jobId: jobId, cwd: row.cwd ?? NSHomeDirectory())
    }

    private func scheduleTimers() {
        timers.forEach { $0.invalidate() }
        timers = [
            Timer.scheduledTimer(withTimeInterval: max(config.sessionPollSeconds, 1), repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshSessions() }
            },
            Timer.scheduledTimer(withTimeInterval: max(config.limitsPollSeconds, 60), repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshLimits() }
            },
        ]
    }

    /// Applies edits to config.json without restarting the app.
    private func reloadConfigIfChanged() {
        guard let url = configURL else { return }
        let modified = Self.modificationDate(url)
        guard modified != configModified else { return }
        configModified = modified
        let next = AppConfig.loadOrCreate(at: url)
        guard next != config else { return }
        apply(next, refresh: false)  // called from refreshSessions, which continues with the new config
    }

    private func apply(_ next: AppConfig, refresh: Bool = true) {
        config = next
        alerts = AlertEngine(config: next)       // re-seeds silently
        activity = ActivityTracker(config: next)
        guard !demo else { return }
        scheduleTimers()
        if refresh { refreshSessions() }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func refreshSessions() {
        reloadConfigIfChanged()
        let projects = TranscriptReader.defaultProjectsDirectory
        let records = SessionRegistry.liveSessions(in: SessionRegistry.defaultDirectory)
        var seen = Set<URL>()
        let rows = Snapshot.build(records: records, usage: { record in
            guard let url = TranscriptReader.locate(projectsDir: projects, cwd: record.cwd,
                                                    sessionId: record.sessionId) else { return nil }
            seen.insert(url)
            return self.cache.usage(at: url)
        }, config: config)
        cache.retain(only: seen)

        var next = snapshot
        next.interactive = rows.interactive
        next.background = rows.background
        for alert in activity.evaluate(rows.interactive + rows.background, now: Date()) {
            Notifier.post(alert)
        }
        publish(next)
    }

    private func refreshLimits() {
        guard !isFetchingLimits else { return }
        isFetchingLimits = true
        Task {
            var next = snapshot
            do {
                next.limits = try await limitsClient.fetch()
                next.limitsUpdatedAt = Date()
                next.limitsError = nil
            } catch {
                next.limitsError = (error as? LimitsError) ?? .network  // keep the last good values
            }
            // Sessions may have refreshed while the request was in flight.
            next.interactive = snapshot.interactive
            next.background = snapshot.background
            isFetchingLimits = false
            publish(next)
        }
    }

    private func publish(_ next: Snapshot) {
        snapshot = next
        for alert in alerts.evaluate(next) { Notifier.post(alert) }
    }
}
