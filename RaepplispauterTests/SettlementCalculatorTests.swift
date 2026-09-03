import XCTest
@testable import Raepplispauter

/// Tests zur Schlussabrechnung und zur Auswertung.
final class SettlementCalculatorTests: XCTestCase {

    private func snapshot(_ amount: String,
                          payer: Payer,
                          splitA: Decimal = 50,
                          chf: String?,
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

    func testSettlementPointsFromBToAWhenAPaidMore() {
        let balance = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .a, chf: "94")],
                                                    tripCurrency: "EUR",
                                                    costSharePercentA: 50)
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertEqual(settlement.debtor, .b)
        XCTAssertEqual(settlement.creditor, .a)
        XCTAssertEqual(settlement.amount, Decimal(50))
        XCTAssertFalse(settlement.isBalanced)
    }

    func testSettlementPointsFromAToBWhenBPaidMore() {
        let balance = BalanceCalculator.tripBalance(snapshots: [snapshot("100", payer: .b, chf: "94")],
                                                    tripCurrency: "EUR",
                                                    costSharePercentA: 50)
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertEqual(settlement.debtor, .a)
        XCTAssertEqual(settlement.creditor, .b)
        XCTAssertEqual(settlement.amount, Decimal(50))
    }

    func testSettlementIsBalancedWhenEven() {
        let snapshots = [
            snapshot("100", payer: .a, chf: "94"),
            snapshot("100", payer: .b, chf: "94")
        ]
        let balance = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                    tripCurrency: "EUR",
                                                    costSharePercentA: 50)
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertTrue(settlement.isBalanced)
        XCTAssertNil(settlement.debtor)
    }

    func testCHFSettlementIsRoundedToFiveRappen() {
        // 33.33 CHF von A bezahlt → B schuldet 16.665 → gerundet 16.65
        let balance = BalanceCalculator.chfBalance(snapshots: [snapshot("35", payer: .a, chf: "33.33")],
                                                   costSharePercentA: 50)
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertEqual(settlement.currencyCode, "CHF")
        XCTAssertEqual(settlement.amount, Decimal(string: "16.65"))
    }

    func testReportGroupsByCategoryAndPayer() {
        let snapshots = [
            snapshot("100", payer: .a, chf: "94", category: .unterkunft),
            snapshot("40", payer: .b, chf: "37.60", category: .restaurant),
            snapshot("20", payer: .b, chf: "18.80", category: .restaurant),
            snapshot("10", payer: .shared, splitA: 50, chf: "9.40", category: .oev)
        ]
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 tripCurrency: "EUR",
                                                 costSharePercentA: 50)

        XCTAssertEqual(report.expenseCount, 4)
        XCTAssertEqual(report.categories.count, 3)

        let restaurant = report.categories.first { $0.category == .restaurant }
        XCTAssertEqual(restaurant?.count, 2)
        XCTAssertEqual(restaurant?.totalTrip, Decimal(60))
        XCTAssertEqual(restaurant?.paidBTrip, Decimal(60))
        XCTAssertEqual(restaurant?.paidATrip, Decimal(0))

        // Kategorien erscheinen in der fixen Reihenfolge der Liste.
        XCTAssertEqual(report.categories.map(\.category), [.unterkunft, .restaurant, .oev])

        let sharedRow = report.payers.first { $0.payer == .shared }
        XCTAssertEqual(sharedRow?.totalTrip, Decimal(10))
    }

    func testReportCountsExpensesWithoutRate() {
        let snapshots = [
            snapshot("100", payer: .a, chf: "94"),
            snapshot("50", payer: .b, chf: nil)
        ]
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 tripCurrency: "EUR",
                                                 costSharePercentA: 50)
        XCTAssertEqual(report.provisionalCount, 1)
        XCTAssertEqual(report.chfBalance.skippedCount, 1)
        // Die Reisewährungs-Bilanz bleibt vollständig.
        XCTAssertEqual(report.tripBalance.total, Decimal(150))
    }
}
