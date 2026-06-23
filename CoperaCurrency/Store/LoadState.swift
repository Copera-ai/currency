import Foundation

/// The lifecycle state of the rates data shown in the UI.
enum LoadState: Equatable, Sendable {
    /// No fetch attempted yet.
    case idle
    /// A fetch is in flight.
    case loading
    /// Fresh data was loaded successfully.
    case loaded
    /// A fetch failed but previously-good data is still being shown.
    case stale(since: Date?)
    /// The device appears offline and no data could be retrieved.
    case offline
    /// An error occurred; carries a user-facing message.
    case error(String)
}
