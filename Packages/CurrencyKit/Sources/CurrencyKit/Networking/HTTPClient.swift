import Foundation

/// The single seam between CurrencyKit and the network. Tests inject a fake.
public protocol HTTPClient: Sendable {
    /// Performs `request` and returns the body plus the HTTP response, for any status code.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// ``HTTPClient`` backed by `URLSession`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = URLSessionHTTPClient.makeSession()) {
        self.session = session
    }

    /// An ephemeral session with short timeouts. CurrencyKit keeps its own disk
    /// cache for immutable data, so no `URLCache` is involved at all.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "CoperaCurrency (macOS)", "Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CurrencyKitError.transport("Non-HTTP response")
        }
        return (data, http)
    }
}

extension HTTPClient {
    /// Fetches `url` and returns the body of a 2xx response. Errors are always ``CurrencyKitError``.
    func fetch(_ url: URL, cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let mapped = CurrencyKitError(error)
            Log.network.error("GET \(url.absoluteString, privacy: .public) failed: \(mapped.localizedDescription, privacy: .public)")
            throw mapped
        }
        guard (200..<300).contains(response.statusCode) else {
            Log.network.error("GET \(url.absoluteString, privacy: .public) → HTTP \(response.statusCode)")
            throw CurrencyKitError.httpStatus(response.statusCode)
        }
        return data
    }
}
