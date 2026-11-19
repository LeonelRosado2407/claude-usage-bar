import Foundation
import Testing
@testable import UsageCore

private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct LimitsParserTests {
    @Test func parsesBothWindows() throws {
        let json = #"{"five_hour":{"utilization":78.0,"resets_at":"2026-11-19T21:40:00.123Z"},"seven_day":{"utilization":31,"resets_at":"2026-11-23T15:00:00Z"},"seven_day_opus":null}"#
        let limits = try LimitsParser.parse(Data(json.utf8))
        #expect(limits.fiveHour?.utilization == 78)
        #expect(limits.sevenDay?.utilization == 31)
        let fiveReset = try #require(limits.fiveHour?.resetsAt)
        #expect(abs(fiveReset.timeIntervalSince(date("2026-11-19T21:40:00Z")) - 0.123) < 0.001)
        #expect(limits.sevenDay?.resetsAt == date("2026-11-23T15:00:00Z"))
    }

    @Test func toleratesNulls() throws {
        let json = #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":null}"#
        let limits = try LimitsParser.parse(Data(json.utf8))
        #expect(limits.fiveHour == LimitWindow(utilization: nil, resetsAt: nil))
        #expect(limits.sevenDay == nil)
    }

    @Test func rejectsNonObject() {
        #expect(throws: LimitsError.badFormat) { try LimitsParser.parse(Data("[]".utf8)) }
        #expect(throws: LimitsError.badFormat) { try LimitsParser.parse(Data("nope".utf8)) }
    }

    @Test func extractsTokenFromKeychainJSON() {
        let ok = #"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r"}}"#
        #expect(LimitsParser.accessToken(fromKeychainJSON: Data(ok.utf8)) == "tok-123")
        #expect(LimitsParser.accessToken(fromKeychainJSON: Data(#"{"other":1}"#.utf8)) == nil)
    }
}

// MARK: - Client (HTTP stubbed with URLProtocol)

private struct FixedToken: TokenProvider {
    var value: String?
    func token() -> String? { value }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)
    nonisolated(unsafe) static var failTransport = false
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        if Self.failTransport {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct LimitsClientTests {
    private func client(token: String? = "tok-123") -> LimitsClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return LimitsClient(tokenProvider: FixedToken(value: token), session: URLSession(configuration: config))
    }

    private func reset(status: Int = 200, body: String = "{}", fail: Bool = false) {
        StubProtocol.status = status
        StubProtocol.body = Data(body.utf8)
        StubProtocol.failTransport = fail
        StubProtocol.lastRequest = nil
    }

    @Test func fetchSendsHeaders() async throws {
        reset(body: #"{"five_hour":{"utilization":10,"resets_at":null}}"#)
        let limits = try await client().fetch()
        #expect(limits.fiveHour?.utilization == 10)
        let req = try #require(StubProtocol.lastRequest)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test func fetchMaps401ToTokenExpired() async {
        reset(status: 401)
        await #expect(throws: LimitsError.tokenExpired) { try await client().fetch() }
    }

    @Test func fetchMaps500ToHttp() async {
        reset(status: 500)
        await #expect(throws: LimitsError.http(500)) { try await client().fetch() }
    }

    @Test func fetchMapsTransportErrorToNetwork() async {
        reset(fail: true)
        await #expect(throws: LimitsError.network) { try await client().fetch() }
    }

    @Test func fetchWithoutTokenIsNoToken() async {
        reset()
        await #expect(throws: LimitsError.noToken) { try await client(token: nil).fetch() }
        #expect(StubProtocol.lastRequest == nil)
    }
}
