import Foundation

/// Coinbase market data: live fiat exchange rates, batched live tickers and OHLC candles.
struct CoinbaseService: Sendable {
    let http: any HTTPClient

    /// Live tickers for `productIDs`, keyed by base code (e.g. `"BTC"`).
    ///
    /// One batched request. If Coinbase rejects the batch with a client error, each
    /// product is retried on its own so a single bad ID can't drop the rest. Products
    /// missing from the response are simply absent from the result.
    func tickers(_ productIDs: [String]) async throws -> [String: CoinbaseTicker] {
        guard !productIDs.isEmpty else { return [:] }
        do {
            return index(try CoinbaseTicker.decodeList(try await http.fetch(Endpoints.coinbaseProducts(productIDs))))
        } catch CurrencyKitError.httpStatus(let status) where (400..<500).contains(status) && status != 429 && productIDs.count > 1 {
            Log.network.notice("Coinbase batch rejected (HTTP \(status)); retrying products individually")
            return try await individually(productIDs)
        }
    }

    /// Live exchange rates as units per 1 USD, keyed by uppercase code.
    func exchangeRates() async throws -> [String: Double] {
        try CoinbaseExchangeRates.decode(try await http.fetch(Endpoints.coinbaseExchangeRates))
    }

    /// Candles for `productID` between `start` and `end`, oldest first.
    func candles(productID: String, granularity: Int, start: Date, end: Date) async throws -> [Candle] {
        let url = Endpoints.coinbaseCandles(productID: productID, granularity: granularity, start: start, end: end)
        return try Candle.decodeList(try await http.fetch(url))
    }

    private func individually(_ productIDs: [String]) async throws -> [String: CoinbaseTicker] {
        let results = await withTaskGroup(of: Result<[CoinbaseTicker], CurrencyKitError>.self) { group in
            for id in productIDs {
                group.addTask {
                    do {
                        return .success(try CoinbaseTicker.decodeList(try await http.fetch(Endpoints.coinbaseProducts([id]))))
                    } catch {
                        return .failure(CurrencyKitError(error))
                    }
                }
            }
            var collected: [Result<[CoinbaseTicker], CurrencyKitError>] = []
            for await result in group { collected.append(result) }
            return collected
        }
        let tickers = results.flatMap { (try? $0.get()) ?? [] }
        if tickers.isEmpty, let failure = results.lazy.compactMap({ result -> CurrencyKitError? in
            if case .failure(let error) = result { return error }
            return nil
        }).first {
            throw failure
        }
        return index(tickers)
    }

    private func index(_ tickers: [CoinbaseTicker]) -> [String: CoinbaseTicker] {
        var result: [String: CoinbaseTicker] = [:]
        for ticker in tickers { result[ticker.baseCode] = ticker }
        return result
    }
}
