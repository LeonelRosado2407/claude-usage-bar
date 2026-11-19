import Foundation

public struct LimitWindow: Equatable, Sendable {
    /// Percentage used, 0–100.
    public var utilization: Double?
    public var resetsAt: Date?

    public init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageLimits: Equatable, Sendable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public enum LimitsError: Error, Equatable, Sendable {
    case noToken, tokenExpired, http(Int), network, badFormat
}

public enum LimitsParser {
    public static func parse(_ data: Data) throws(LimitsError) -> UsageLimits {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw .badFormat }
        return UsageLimits(fiveHour: window(root["five_hour"]), sevenDay: window(root["seven_day"]))
    }

    /// Pulls the OAuth access token out of Claude Code's Keychain item.
    public static func accessToken(fromKeychainJSON data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    private static func window(_ value: Any?) -> LimitWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
        let resetsAt = (dict["resets_at"] as? String).flatMap(parseDate)
        return LimitWindow(utilization: utilization, resetsAt: resetsAt)
    }

    private static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

public protocol TokenProvider: Sendable {
    func token() -> String?
}

/// Reads the token Claude Code stores in the login Keychain. Never logs or persists it.
public struct KeychainTokenProvider: TokenProvider {
    public init() {}

    public func token() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return LimitsParser.accessToken(fromKeychainJSON: data)
    }
}

public struct LimitsClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let tokenProvider: TokenProvider
    private let session: URLSession

    public init(tokenProvider: TokenProvider, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public func fetch() async throws(LimitsError) -> UsageLimits {
        guard let token = tokenProvider.token() else { throw .noToken }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw .network }
        guard let http = response as? HTTPURLResponse else { throw .network }
        switch http.statusCode {
        case 200..<300: return try LimitsParser.parse(data)
        case 401, 403: throw .tokenExpired
        default: throw .http(http.statusCode)
        }
    }
}
