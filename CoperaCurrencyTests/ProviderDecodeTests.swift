import Foundation
import Testing
@testable import CoperaCurrency

/// Provider decode tests — pure decode functions, no network.
struct ProviderDecodeTests {
    @Test func fawazDecodeInvertsAndUppercases() throws {
        let json = """
        {"date":"2025-06-01","usd":{"brl":5.15,"eur":0.87,"jpy":156.2,"gbp":0.78,"btc":0.0000152,"eth":0.00031}}
        """
        let data = Data(json.utf8)
        let result = try FawazFiatProvider.decode(data)

        #expect(result.date == "2025-06-01")
        #expect(result.usdPerUnit["USD"] == 1)

        let brl = try #require(result.usdPerUnit["BRL"])
        #expect(abs(brl - (1 / 5.15)) < 1e-12)

        let eur = try #require(result.usdPerUnit["EUR"])
        #expect(abs(eur - (1 / 0.87)) < 1e-12)

        // Keys uppercased; lowercase keys must not survive.
        #expect(result.usdPerUnit["brl"] == nil)
    }

    @Test func coinbaseDecodeBtcNoInvert() throws {
        let json = """
        {"data":{"currency":"BTC","rates":{"USD":"62537.68","ETH":"37.5"}}}
        """
        let data = Data(json.utf8)
        let result = try CoinbaseCryptoProvider.decode(data)
        #expect(result.currency == "BTC")
        #expect(result.usdPerUnit == 62537.68)
    }

    @Test func coinbaseDecodeEthNoInvert() throws {
        let json = """
        {"data":{"currency":"ETH","rates":{"USD":"3401.22"}}}
        """
        let data = Data(json.utf8)
        let result = try CoinbaseCryptoProvider.decode(data)
        #expect(result.currency == "ETH")
        #expect(result.usdPerUnit == 3401.22)
    }
}
