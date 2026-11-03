import Foundation

/// Fetches the daily currency API, trying each host in order.
struct FiatRatesService: Sendable {
    let http: any HTTPClient
    let cache: DiskCache
    let now: @Sendable () -> Date

    /// Today's rates. Always bypasses any HTTP cache.
    func latest() async throws -> FiatSnapshot {
        try await firstSuccess(Endpoints.FiatHost.allCases.map(Endpoints.fiatLatest)) { data in
            try FiatSnapshot.decode(data)
        }
    }

    /// The rates published for `day`. Past days are immutable and cached on disk forever.
    func snapshot(for day: CalendarDay) async throws -> FiatSnapshot {
        let fileName = "fiat-usd-\(day).json"
        if let data = cache.read(fileName), let cached = try? FiatSnapshot.decode(data), cached.day == day {
            return cached
        }
        guard day >= Endpoints.earliestFiatDay else { throw CurrencyKitError.historyUnavailable }
        let urls = Endpoints.FiatHost.allCases.map { Endpoints.fiatSnapshot(day, $0) }
        var raw = Data()
        let snapshot = try await firstSuccess(urls) { data in
            let decoded = try FiatSnapshot.decode(data)
            guard decoded.day == day else { throw CurrencyKitError.decoding("Expected \(day), got \(decoded.day)") }
            raw = data
            return decoded
        }
        // Today's file may still be republished; only finished days are immutable.
        if day < CalendarDay(now()) {
            cache.write(raw, to: fileName)
        }
        return snapshot
    }

    /// Tries `urls` in order and returns the first payload that downloads and decodes.
    /// Throws the most meaningful failure (connectivity wins) when every host fails.
    private func firstSuccess<T>(_ urls: [URL], decode: (Data) throws -> T) async throws -> T {
        var failures: [CurrencyKitError] = []
        for url in urls {
            try Task.checkCancellation()
            do {
                return try decode(try await http.fetch(url))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mapped = CurrencyKitError(error)
                failures.append(mapped)
                Log.network.notice("Fiat host failed (\(url.host() ?? "?", privacy: .public)), trying next")
            }
        }
        throw failures.first(where: \.isConnectivity) ?? failures.last ?? CurrencyKitError.noData
    }
}
