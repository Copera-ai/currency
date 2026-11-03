import Foundation

/// Quality of the rates currently shown.
///
/// `loading` is only used before any data exists; refreshes over existing data
/// keep the current state and set ``CurrencyStore/isRefreshing`` instead.
public enum LoadState: Equatable, Sendable {
    /// Nothing attempted yet.
    case idle
    /// First load in flight, no data to show.
    case loading
    /// Fresh data from every source.
    case loaded
    /// Showing data, but the last refresh failed fully or partially.
    case stale
    /// No connectivity. Previously loaded data (if any) is still shown.
    case offline
    /// Failed with nothing to show.
    case error(CurrencyKitError)

    /// Whether the UI should show a warning badge.
    public var isDegraded: Bool {
        switch self {
        case .stale, .offline, .error: true
        case .idle, .loading, .loaded: false
        }
    }
}
