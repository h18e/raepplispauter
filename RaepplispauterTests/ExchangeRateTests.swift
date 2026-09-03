import XCTest
@testable import Raepplispauter

/// Tests zum EZB-Parser, zu den Kreuzkursen und zum lokalen Kurs-Cache.
final class ExchangeRateTests: XCTestCase {

    private let sampleFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <gesmes:subject>Reference rates</gesmes:subject>
      <gesmes:Sender><gesmes:name>European Central Bank</gesmes:name></gesmes:Sender>
      <Cube>
        <Cube time='2026-09-02'>
          <Cube currency='USD' rate='1.0812'/>
          <Cube currency='CHF' rate='0.9412'/>
          <Cube currency='GBP' rate='0.8534'/>
        </Cube>
        <Cube time='2026-09-01'>
          <Cube currency='USD' rate='1.0800'/>
          <Cube currency='CHF' rate='0.9400'/>
        </Cube>
      </Cube>
    </gesmes:Envelope>
    """

    // MARK: - Parser

    func testParserReadsAllDays() throws {
        let days = try ECBRatesParser().parse(data: Data(sampleFeed.utf8))
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.day, "2026-09-02")
        XCTAssertEqual(days.first?.ratesPerEUR["CHF"], Decimal(string: "0.9412"))
        XCTAssertEqual(days.last?.ratesPerEUR["USD"], Decimal(string: "1.0800"))
    }

    func testParserAddsEuroAsBaseCurrency() throws {
        let days = try ECBRatesParser().parse(data: Data(sampleFeed.utf8))
        XCTAssertEqual(days.first?.ratesPerEUR["EUR"], Decimal(1))
    }

    func testParserRejectsGarbage() {
        XCTAssertThrowsError(try ECBRatesParser().parse(data: Data("kei XML".utf8)))
    }

    // MARK: - Kreuzkurse

    func testCrossRateFromEuroToCHF() throws {
        let day = try XCTUnwrap(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)).first)
        XCTAssertEqual(day.crossRate(from: "EUR", to: "CHF"), Decimal(string: "0.9412"))
    }

    func testCrossRateBetweenTwoForeignCurrencies() throws {
        let day = try XCTUnwrap(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)).first)
        // USD → CHF = CHF_pro_EUR / USD_pro_EUR = 0.9412 / 1.0812
        let rate = try XCTUnwrap(day.crossRate(from: "USD", to: "CHF"))
        let expected = Decimal(string: "0.9412")! / Decimal(string: "1.0812")!
        XCTAssertEqual(rate, expected)
        // Plausibilitätsprüfung: rund 0.87
        XCTAssertEqual(NSDecimalNumber(decimal: rate).doubleValue, 0.8705, accuracy: 0.001)
    }

    func testCrossRateForIdenticalCurrencyIsOne() throws {
        let day = try XCTUnwrap(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)).first)
        XCTAssertEqual(day.crossRate(from: "CHF", to: "CHF"), Decimal(1))
    }

    func testCrossRateForUnknownCurrencyIsNil() throws {
        let day = try XCTUnwrap(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)).first)
        XCTAssertNil(day.crossRate(from: "XYZ", to: "CHF"))
    }

    // MARK: - Cache

    func testStoreFindsLatestRatesBeforeGivenDay() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RateStore(fileURL: url)
        store.store(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)))

        // Am Wochenende publiziert die EZB nichts → jüngerer Vortag wird verwendet.
        XCTAssertEqual(store.latestRates(onOrBefore: "2026-09-05")?.day, "2026-09-02")
        XCTAssertEqual(store.rates(for: "2026-09-01")?.day, "2026-09-01")
        XCTAssertNil(store.latestRates(onOrBefore: "2026-08-01"))
        XCTAssertEqual(store.newestDay, "2026-09-02")
        XCTAssertEqual(store.cachedDayCount, 2)
    }

    func testStorePersistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        RateStore(fileURL: url).store(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)))

        let reloaded = RateStore(fileURL: url)
        XCTAssertEqual(reloaded.rates(for: "2026-09-02")?.ratesPerEUR["CHF"],
                       Decimal(string: "0.9412"))
    }

    // MARK: - Umrechnung

    func testConversionFromCacheAppliesRoundingAndMarkup() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RateStore(fileURL: url)
        store.store(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)))

        let service = ExchangeRateService(store: store, markupProvider: { 0 })
        let date = try XCTUnwrap(ExchangeRateService.date(fromDay: "2026-09-02"))

        let conversion = try XCTUnwrap(service.convertFromCache(amount: Decimal(100),
                                                                from: "EUR",
                                                                tripCurrency: "EUR",
                                                                on: date))
        // 100 EUR × 0.9412 = 94.12 → auf 5 Rappen: 94.10
        XCTAssertEqual(conversion.amountInCHF, Decimal(string: "94.10"))
        XCTAssertEqual(conversion.amountInTripCurrency, Decimal(100))
        XCTAssertFalse(conversion.isProvisional)
    }

    func testMarkupIncreasesRate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RateStore(fileURL: url)
        store.store(try ECBRatesParser().parse(data: Data(sampleFeed.utf8)))

        let service = ExchangeRateService(store: store, markupProvider: { 2 })
        let date = try XCTUnwrap(ExchangeRateService.date(fromDay: "2026-09-02"))

        let conversion = try XCTUnwrap(service.convertFromCache(amount: Decimal(100),
                                                                from: "EUR",
                                                                tripCurrency: "EUR",
                                                                on: date))
        // 0.9412 × 1.02 = 0.960024 → 100 × 0.960024 = 96.0024 → 96.00
        XCTAssertEqual(conversion.amountInCHF, Decimal(string: "96.00"))
    }

    func testConversionFromCacheReturnsNilWithoutRates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rates-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let service = ExchangeRateService(store: RateStore(fileURL: url), markupProvider: { 0 })
        XCTAssertNil(service.convertFromCache(amount: Decimal(10),
                                              from: "EUR",
                                              tripCurrency: "EUR",
                                              on: Date()))
    }
}
