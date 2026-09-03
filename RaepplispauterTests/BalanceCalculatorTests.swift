import XCTest
@testable import Raepplispauter

/// Tests zur Bilanzlogik – inklusive der beiden Schlüssel
/// (Auslage-Aufteilung bei "Gemeinsam" und Kostenschlüssel der Reise).
final class BalanceCalculatorTests: XCTestCase {

    private func snapshot(_ amount: String,
                          payer: Payer,
                          splitA: Decimal = 50,
                          chf: String? = nil,
                          category: ExpenseCategory = .restaurant) -> ExpenseSnapshot {
        ExpenseSnapshot(id: UUID(),
                        amountOriginal: Decimal(string: amount)!,
                        currencyCode: "EUR",
                        amountTrip: Decimal(string: amount)!,
                        amountCHF: chf.map { Decimal(string: $0)! },
                        payer: payer,
                        splitPercentA: splitA,
                        category: category)
    }

    // MARK: - Einzelne Zahler

    func testPayerAPaysEverythingSoBOwesHalf() {
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .a)],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.total, Decimal(100))
        XCTAssertEqual(result.a.paid, Decimal(100))
        XCTAssertEqual(result.b.paid, Decimal(0))
        XCTAssertEqual(result.a.share, Decimal(50))
        XCTAssertEqual(result.netA, Decimal(50))
    }

    func testPayerBPaysEverything() {
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("80", payer: .b)],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.netA, Decimal(-40))
    }

    // MARK: - "Gemeinsam"

    func testSharedFiftyFiftyIsNeutral() {
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .shared, splitA: 50)],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.a.paid, Decimal(50))
        XCTAssertEqual(result.b.paid, Decimal(50))
        XCTAssertEqual(result.netA, Decimal(0))
    }

    func testSharedSixtyFortyShiftsBalance() {
        // A legt 60 % aus, trägt aber nur 50 % → A steht mit 10 im Plus.
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .shared, splitA: 60)],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.a.paid, Decimal(60))
        XCTAssertEqual(result.b.paid, Decimal(40))
        XCTAssertEqual(result.netA, Decimal(10))
    }

    // MARK: - Kostenschlüssel der Reise

    func testCustomCostShareChangesWhoBearsWhat() {
        // A zahlt 100, trägt aber 70 % der Kosten → nur 30 im Plus.
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .a)],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 70)
        XCTAssertEqual(result.a.share, Decimal(70))
        XCTAssertEqual(result.b.share, Decimal(30))
        XCTAssertEqual(result.netA, Decimal(30))
    }

    // MARK: - Mehrere Posten

    func testMixedExpensesNetOut() {
        let snapshots = [
            snapshot("100", payer: .a),
            snapshot("60", payer: .b),
            snapshot("40", payer: .shared, splitA: 25)
        ]
        let result = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.total, Decimal(200))
        XCTAssertEqual(result.a.paid, Decimal(110))   // 100 + 25 % von 40
        XCTAssertEqual(result.b.paid, Decimal(90))    // 60 + 75 % von 40
        XCTAssertEqual(result.netA, Decimal(10))
        XCTAssertEqual(result.a.net + result.b.net, Decimal(0))
    }

    // MARK: - CHF-Bilanz

    func testCHFBalanceSkipsExpensesWithoutRate() {
        let snapshots = [
            snapshot("100", payer: .a, chf: "94.00"),
            snapshot("50", payer: .b, chf: nil)          // kein Kurs vorhanden
        ]
        let chf = BalanceCalculator.chfBalance(snapshots: snapshots, costSharePercentA: 50)
        XCTAssertEqual(chf.skippedCount, 1)
        XCTAssertEqual(chf.total, Decimal(string: "94.00"))
        XCTAssertEqual(chf.netA, Decimal(string: "47.00"))
    }

    func testEmptyTripIsBalanced() {
        let result = BalanceCalculator.tripBalance(snapshots: [],
                                                   tripCurrency: "EUR",
                                                   costSharePercentA: 50)
        XCTAssertEqual(result.total, Decimal(0))
        XCTAssertEqual(result.netA, Decimal(0))
    }
}
