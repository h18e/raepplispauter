import XCTest
@testable import Raepplispauter

/// Tests zur 5-Rappen-Rundung und zur Betragserfassung.
final class MoneyTests: XCTestCase {

    func testRoundToFiveRappenRoundsDown() {
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "12.32")!), Decimal(string: "12.30")!)
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "0.01")!), Decimal(string: "0.00")!)
    }

    func testRoundToFiveRappenRoundsUp() {
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "12.33")!), Decimal(string: "12.35")!)
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "0.03")!), Decimal(string: "0.05")!)
    }

    func testRoundToFiveRappenHalfwayGoesUp() {
        // 12.325 liegt exakt zwischen 12.30 und 12.35 → kaufmännisch aufwärts.
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "12.325")!), Decimal(string: "12.35")!)
    }

    func testRoundToFiveRappenKeepsExactValues() {
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "12.35")!), Decimal(string: "12.35")!)
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "100.00")!), Decimal(string: "100.00")!)
    }

    func testRoundToFiveRappenHandlesNegativeAmounts() {
        XCTAssertEqual(Money.roundToFiveRappen(Decimal(string: "-12.33")!), Decimal(string: "-12.35")!)
    }

    func testRoundForCurrencyUsesFiveRappenOnlyForCHF() {
        XCTAssertEqual(Money.roundForCurrency(Decimal(string: "12.33")!, currencyCode: "CHF"),
                       Decimal(string: "12.35")!)
        XCTAssertEqual(Money.roundForCurrency(Decimal(string: "12.334")!, currencyCode: "EUR"),
                       Decimal(string: "12.33")!)
    }

    func testParseAcceptsCommaAndApostrophe() {
        XCTAssertEqual(Money.parse("12,50"), Decimal(string: "12.50"))
        XCTAssertEqual(Money.parse("1'234.55"), Decimal(string: "1234.55"))
        XCTAssertEqual(Money.parse("42"), Decimal(42))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
    }

    func testCSVNumberUsesPointAndNoGrouping() {
        XCTAssertEqual(Money.csvNumber(Decimal(string: "1234.5")!), "1234.50")
    }

    func testIsZeroToleratesRoundingNoise() {
        XCTAssertTrue(Money.isZero(Decimal(string: "0.001")!))
        XCTAssertFalse(Money.isZero(Decimal(string: "0.01")!))
    }
}
