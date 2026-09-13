import XCTest
@testable import Raepplispauter

/// Tests zur Schlussabrechnung (Ausgleich über beliebig viele Personen)
/// und zur Auswertung.
final class SettlementCalculatorTests: XCTestCase {

    private let anna = ParticipantSnapshot(id: UUID(), name: "Anna", costSharePercent: 50, sortIndex: 0)
    private let beat = ParticipantSnapshot(id: UUID(), name: "Beat", costSharePercent: 50, sortIndex: 1)
    private let cem = ParticipantSnapshot(id: UUID(), name: "Cem", costSharePercent: 0, sortIndex: 2)

    private func withShares(_ people: [ParticipantSnapshot], _ percentages: [Decimal]) -> [ParticipantSnapshot] {
        zip(people, percentages).map {
            ParticipantSnapshot(id: $0.id, name: $0.name, costSharePercent: $1,
                                colorIndex: $0.colorIndex, sortIndex: $0.sortIndex)
        }
    }

    private func snapshot(_ amount: String,
                          paidBy payer: ParticipantSnapshot,
                          chf: String?,
                          category: String = "Restaurant",
                          categoryID: UUID? = nil) -> ExpenseSnapshot {
        ExpenseSnapshot(id: UUID(),
                        amountOriginal: Decimal(string: amount)!,
                        currencyCode: "EUR",
                        amountTrip: Decimal(string: amount)!,
                        amountCHF: chf.map { Decimal(string: $0)! },
                        paymentPercentages: [payer.id: 100],
                        singlePayerID: payer.id,
                        categoryID: categoryID,
                        categoryName: category)
    }

    // MARK: - Zwei Personen

    func testSettlementBetweenTwoPeople() {
        let people = [anna, beat]
        let balance = BalanceCalculator.tripBalance(snapshots: [snapshot("100", paidBy: anna, chf: "94")],
                                                    participants: people,
                                                    tripCurrency: "EUR")
        let settlement = SettlementCalculator.settlement(from: balance)

        XCTAssertEqual(settlement.transfers.count, 1)
        XCTAssertEqual(settlement.transfers.first?.from.id, beat.id)
        XCTAssertEqual(settlement.transfers.first?.to.id, anna.id)
        XCTAssertEqual(settlement.transfers.first?.amount, Decimal(50))
    }

    func testSettlementIsBalancedWhenEven() {
        let people = [anna, beat]
        let snapshots = [
            snapshot("100", paidBy: anna, chf: "94"),
            snapshot("100", paidBy: beat, chf: "94")
        ]
        let balance = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                    participants: people,
                                                    tripCurrency: "EUR")
        XCTAssertTrue(SettlementCalculator.settlement(from: balance).isBalanced)
    }

    // MARK: - Drei Personen

    func testSettlementNeedsAtMostOneTransferPerPersonMinusOne() {
        // Anna zahlt alles, Beat und Cem schulden ihr je einen Drittel.
        let people = withShares([anna, beat, cem], [Decimal(string: "33.4")!, Decimal(string: "33.3")!, Decimal(string: "33.3")!])
        let balance = BalanceCalculator.tripBalance(snapshots: [snapshot("300", paidBy: anna, chf: nil)],
                                                    participants: people,
                                                    tripCurrency: "EUR")
        let settlement = SettlementCalculator.settlement(from: balance)

        XCTAssertEqual(settlement.transfers.count, 2)
        XCTAssertTrue(settlement.transfers.allSatisfy { $0.to.id == anna.id })
        let sum = settlement.transfers.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(sum, Decimal(string: "199.80"))
    }

    func testSettlementMatchesDebtorsWithCreditors() {
        // Anna legt 200 aus, trägt aber nur 20 % → Anna +160, Beat −100, Cem −60.
        let people = withShares([anna, beat, cem], [20, 50, 30])
        let balance = BalanceCalculator.tripBalance(snapshots: [snapshot("200", paidBy: anna, chf: nil)],
                                                    participants: people,
                                                    tripCurrency: "EUR")
        let settlement = SettlementCalculator.settlement(from: balance)

        XCTAssertEqual(settlement.transfers.count, 2)
        // Grösster Schuldner zuerst.
        XCTAssertEqual(settlement.transfers.first?.from.id, beat.id)
        XCTAssertEqual(settlement.transfers.first?.amount, Decimal(100))
        XCTAssertEqual(settlement.transfers.last?.from.id, cem.id)
        XCTAssertEqual(settlement.transfers.last?.amount, Decimal(60))
    }

    func testEveryTransferHasPositiveAmount() {
        let people = withShares([anna, beat, cem], [40, 30, 30])
        let snapshots = [
            snapshot("100", paidBy: anna, chf: nil),
            snapshot("40", paidBy: beat, chf: nil),
            snapshot("10", paidBy: cem, chf: nil)
        ]
        let balance = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                    participants: people,
                                                    tripCurrency: "EUR")
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertTrue(settlement.transfers.allSatisfy { $0.amount > 0 })
        XCTAssertTrue(settlement.transfers.allSatisfy { $0.from.id != $0.to.id })
    }

    func testCHFSettlementIsRoundedToFiveRappen() {
        let people = [anna, beat]
        let balance = BalanceCalculator.chfBalance(snapshots: [snapshot("35", paidBy: anna, chf: "33.33")],
                                                   participants: people)
        let settlement = SettlementCalculator.settlement(from: balance)
        XCTAssertEqual(settlement.currencyCode, "CHF")
        XCTAssertEqual(settlement.transfers.first?.amount, Decimal(string: "16.65"))
    }

    // MARK: - Auswertung

    func testReportGroupsByCategoryAndPayer() {
        let people = [anna, beat]
        let restaurantID = UUID()
        let hotelID = UUID()
        let snapshots = [
            snapshot("100", paidBy: anna, chf: "94", category: "Unterkunft", categoryID: hotelID),
            snapshot("40", paidBy: beat, chf: "37.60", category: "Restaurant", categoryID: restaurantID),
            snapshot("20", paidBy: beat, chf: "18.80", category: "Restaurant", categoryID: restaurantID)
        ]
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 participants: people,
                                                 tripCurrency: "EUR")

        XCTAssertEqual(report.expenseCount, 3)
        XCTAssertEqual(report.categories.count, 2)

        // Nach Betrag absteigend: Unterkunft 100 vor Restaurant 60.
        XCTAssertEqual(report.categories.first?.name, "Unterkunft")
        let restaurant = report.categories.first { $0.categoryID == restaurantID }
        XCTAssertEqual(restaurant?.count, 2)
        XCTAssertEqual(restaurant?.totalTrip, Decimal(60))

        let beatRow = report.payers.first { $0.participant.id == beat.id }
        XCTAssertEqual(beatRow?.count, 2)
        XCTAssertEqual(beatRow?.totalTrip, Decimal(60))
    }

    func testReportSplitsPayerTotalsProportionally() {
        let people = [anna, beat]
        let split = ExpenseSnapshot(id: UUID(),
                                    amountOriginal: 100,
                                    currencyCode: "EUR",
                                    amountTrip: 100,
                                    amountCHF: 94,
                                    paymentPercentages: [anna.id: 70, beat.id: 30],
                                    singlePayerID: nil,
                                    categoryName: "Restaurant")
        let report = SettlementCalculator.report(snapshots: [split],
                                                 participants: people,
                                                 tripCurrency: "EUR")
        XCTAssertEqual(report.payers.first { $0.participant.id == anna.id }?.totalTrip, Decimal(70))
        XCTAssertEqual(report.payers.first { $0.participant.id == beat.id }?.totalTrip, Decimal(30))
    }

    func testReportCountsExpensesWithoutRate() {
        let people = [anna, beat]
        let snapshots = [
            snapshot("100", paidBy: anna, chf: "94"),
            snapshot("50", paidBy: beat, chf: nil)
        ]
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 participants: people,
                                                 tripCurrency: "EUR")
        XCTAssertEqual(report.provisionalCount, 1)
        XCTAssertEqual(report.chfBalance.skippedCount, 1)
        // Die Kassä-Währungs-Bilanz bleibt vollständig.
        XCTAssertEqual(report.tripBalance.total, Decimal(150))
    }
}
