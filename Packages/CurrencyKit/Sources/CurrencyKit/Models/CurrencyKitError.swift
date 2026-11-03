import Foundation

/// Every error surfaced by CurrencyKit.
public enum CurrencyKitError: Error, Hashable, Sendable, LocalizedError {
    /// The device has no usable network connection.
    case offline
    /// The request timed out.
    case timedOut
    /// Any other transport failure (DNS, TLS, connection reset, …).
    case transport(String)
    /// The server answered with a non-2xx status.
    case httpStatus(Int)
    /// The payload did not have the expected shape.
    case decoding(String)
    /// History is not available for this pair and range (e.g. 24H for fiat pairs).
    case historyUnavailable
    /// A rate needed for the computation is missing.
    case missingRate(String)
    /// Nothing could be fetched and there is no cached data to fall back to.
    case noData

    public var errorDescription: String? {
        switch self {
        case .offline: "You're offline."
        case .timedOut: "The request timed out."
        case .transport(let detail): "Network error: \(detail)"
        case .httpStatus(let code): "The server returned HTTP \(code)."
        case .decoding(let detail): "Unexpected response: \(detail)"
        case .historyUnavailable: "History isn't available for this range."
        case .missingRate(let code): "No rate available for \(code)."
        case .noData: "No rates available yet."
        }
    }

    /// Whether this error means "no connectivity" (as opposed to a server or data problem).
    public var isConnectivity: Bool {
        switch self {
        case .offline, .timedOut: true
        default: false
        }
    }

    /// Maps any thrown error into a ``CurrencyKitError``.
    public init(_ error: any Error) {
        if let error = error as? CurrencyKitError {
            self = error
        } else if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            case .timedOut:
                self = .timedOut
            default:
                self = .transport(error.code.description)
            }
        } else if error is DecodingError {
            self = .decoding(String(describing: error))
        } else {
            self = .transport(error.localizedDescription)
        }
    }
}

private extension URLError.Code {
    var description: String { "URLError \(rawValue)" }
}
