@testable import CurrencyKit
import Foundation
import Synchronization

/// A temporary directory for one test, removed on deinit.
final class Sandbox: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "CurrencyKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ relative: String) -> URL {
        url.appending(path: relative)
    }

    var cache: DiskCache { DiskCache(directory: path("Caches")) }
    var stateStore: StateStore { StateStore(directory: path("Support"), migratesLegacyDefaults: false) }

    func files(in relative: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path(relative).path)) ?? []
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error { case missing(String) }

    /// A minimal currency-API payload for `day`.
    static func fiat(_ day: String, _ rates: [String: Double]) -> Data {
        let body = rates.map { "\"\($0.key.lowercased())\":\($0.value)" }.joined(separator: ",")
        return Data("{\"date\":\"\(day)\",\"usd\":{\(body)}}".utf8)
    }

    /// A Coinbase candles payload (newest first, like the real API).
    static func candles(_ rows: [(time: Date, close: Double)]) -> Data {
        let body = rows.sorted { $0.time > $1.time }
            .map { "[\(Int($0.time.timeIntervalSince1970)),\($0.close),\($0.close),\($0.close),\($0.close),1.0]" }
            .joined(separator: ",")
        return Data("[\(body)]".utf8)
    }
}

/// USD/BRL in the live exchange-rates fixture (the daily fixture has 5.44059239).
let liveUSDBRL = 5.499

/// 2026-11-03T12:00:00Z — the day the fixtures were captured.
let fixtureNow = Date(timeIntervalSince1970: 1_793_707_200)

/// In-memory ``HTTPClient``. Routes match by URL substring; the most recently added
/// matching route wins. Unmatched requests get a 404.
final class FakeHTTPClient: HTTPClient {
    enum Reply: Sendable {
        case data(Data, status: Int)
        case failure(URLError.Code)

        static func json(_ data: Data) -> Reply { .data(data, status: 200) }
        static func status(_ code: Int) -> Reply { .data(Data("{}".utf8), status: code) }
    }

    typealias Handler = @Sendable (URL) -> Reply?

    private struct State {
        var routes: [(pattern: String, handler: Handler)] = []
        var requests: [URLRequest] = []
    }

    private let state = Mutex(State())
    private let latency: Duration

    init(latency: Duration = .zero) {
        self.latency = latency
    }

    func route(_ pattern: String, _ reply: Reply) {
        route(pattern) { _ in reply }
    }

    func route(_ pattern: String, handler: @escaping Handler) {
        state.withLock { $0.routes.append((pattern, handler)) }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func requestCount(_ pattern: String) -> Int {
        requests.filter { $0.url?.absoluteString.contains(pattern) == true }.count
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try require(request.url)
        let routes = state.withLock { state in
            state.requests.append(request)
            return state.routes
        }
        if latency > .zero { try await Task.sleep(for: latency) }
        let reply = routes.reversed().lazy
            .filter { $0.pattern.isEmpty || url.absoluteString.contains($0.pattern) }
            .compactMap { $0.handler(url) }
            .first ?? .status(404)
        switch reply {
        case .data(let data, let status):
            let response = try require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil))
            return (data, response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw URLError(.badURL) }
    return value
}

extension FakeHTTPClient {
    static let latestPattern = "latest.currency-api.pages.dev/v1/currencies/usd"
    static let jsdelivrLatestPattern = "currency-api@latest"
    static let previousDayPattern = "2026-11-02.currency-api.pages.dev"
    static let productsPattern = "api.coinbase.com/api/v3/brokerage/market/products"
    static let exchangeRatesPattern = "api.coinbase.com/v2/exchange-rates"

    /// Routes serving the captured fixtures for latest, previous day, Coinbase products
    /// and Coinbase live exchange rates.
    static func withFixtures(latency: Duration = .zero) throws -> FakeHTTPClient {
        let client = FakeHTTPClient(latency: latency)
        client.route(latestPattern, .json(try Fixture.data("fiat-latest")))
        client.route(jsdelivrLatestPattern, .json(try Fixture.data("fiat-latest-jsdelivr")))
        client.route(previousDayPattern, .json(try Fixture.data("fiat-2026-11-02")))
        client.route(productsPattern, .json(try Fixture.data("coinbase-products")))
        client.route(exchangeRatesPattern, .json(try Fixture.data("coinbase-exchange-rates")))
        return client
    }
}

func approx(_ lhs: Double?, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    guard let lhs else { return false }
    return abs(lhs - rhs) <= tolerance * max(1, abs(rhs))
}
