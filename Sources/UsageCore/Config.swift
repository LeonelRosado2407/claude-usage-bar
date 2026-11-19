import Foundation

/// User-tunable settings, stored as JSON. Missing keys fall back to their defaults.
public struct AppConfig: Codable, Equatable, Sendable {
    public var barWarn: Double = 70
    public var barCritical: Double = 90
    public var contextThresholds: [Double] = [80, 90]
    public var limitThreshold: Double = 90
    public var sessionPollSeconds: Double = 5
    public var limitsPollSeconds: Double = 300
    public var defaultContextWindow: Int = 1_000_000
    /// Context window per model-id prefix, e.g. `"claude-haiku": 200000`.
    public var modelContextWindows: [String: Int] = [:]
    /// Notify when a session finishes working or is waiting for the user.
    public var notifyActivity: Bool = true
    /// Minimum time a session must have been working before "finished" notifies.
    public var notifyFinishedAfterSeconds: Double = 30
    /// How long a session must be waiting for the user before notifying.
    public var notifyWaitingAfterSeconds: Double = 15
    /// UI and notification language. Unknown values fall back to Spanish.
    public var language: AppLanguage = .es

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        barWarn = try c.decodeIfPresent(Double.self, forKey: .barWarn) ?? d.barWarn
        barCritical = try c.decodeIfPresent(Double.self, forKey: .barCritical) ?? d.barCritical
        contextThresholds = try c.decodeIfPresent([Double].self, forKey: .contextThresholds) ?? d.contextThresholds
        limitThreshold = try c.decodeIfPresent(Double.self, forKey: .limitThreshold) ?? d.limitThreshold
        sessionPollSeconds = try c.decodeIfPresent(Double.self, forKey: .sessionPollSeconds) ?? d.sessionPollSeconds
        limitsPollSeconds = try c.decodeIfPresent(Double.self, forKey: .limitsPollSeconds) ?? d.limitsPollSeconds
        defaultContextWindow = try c.decodeIfPresent(Int.self, forKey: .defaultContextWindow) ?? d.defaultContextWindow
        modelContextWindows = try c.decodeIfPresent([String: Int].self, forKey: .modelContextWindows) ?? d.modelContextWindows
        notifyActivity = try c.decodeIfPresent(Bool.self, forKey: .notifyActivity) ?? d.notifyActivity
        notifyFinishedAfterSeconds = try c.decodeIfPresent(Double.self, forKey: .notifyFinishedAfterSeconds) ?? d.notifyFinishedAfterSeconds
        notifyWaitingAfterSeconds = try c.decodeIfPresent(Double.self, forKey: .notifyWaitingAfterSeconds) ?? d.notifyWaitingAfterSeconds
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? d.language
    }

    /// Context window for a model id: the longest matching prefix wins, else the default.
    public func contextWindow(for model: String?) -> Int {
        guard let model else { return defaultContextWindow }
        let match = modelContextWindows
            .filter { model.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }
        return match?.value ?? defaultContextWindow
    }

    /// Loads the config, writing defaults if the file does not exist.
    /// An unreadable or invalid file yields defaults and is left untouched.
    public static func loadOrCreate(at url: URL) -> AppConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let config = AppConfig()
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            write(config, to: url)
            return config
        }
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }

        // Add settings introduced by newer versions, so they show up when the file is opened.
        let presentKeys = Set(((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?.keys ?? [:].keys)
        if !Set(CodingKeys.allCases.map(\.stringValue)).isSubset(of: presentKeys) {
            write(config, to: url)
        }
        return config
    }

    private static func write(_ config: AppConfig, to url: URL) {
        try? config.save(to: url)
    }

    /// Writes the config as pretty, sorted JSON.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public var strings: Strings { Strings.for(language) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case barWarn, barCritical, contextThresholds, limitThreshold, sessionPollSeconds,
             limitsPollSeconds, defaultContextWindow, modelContextWindows, notifyActivity,
             notifyFinishedAfterSeconds, notifyWaitingAfterSeconds, language
    }

    /// `~/Library/Application Support/ClaudeUsageBar/config.json`
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeUsageBar/config.json")
    }
}
