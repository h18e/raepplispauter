import XCTest
@testable import Raepplispauter

/// Tests zur Bilanzlogik mit beliebig vielen Personen.
final class BalanceCalculatorTests: XCTestCase {

    // Drei feste Personen, damit die IDs über die Testfälle stabil bleiben.
    private let anna = ParticipantSnapshot(id: UUID(), name: "Anna", costSharePercent: 50, colorIndex: 0, sortIndex: 0)
    private let beat = ParticipantSnapshot(id: UUID(), name: "Beat", costSharePercent: 50, colorIndex: 1, sortIndex: 1)
    private let cem = ParticipantSnapshot(id: UUID(), name: "Cem", costSharePercent: 0, colorIndex: 2, sortIndex: 2)

    private func withShares(_ people: [ParticipantSnapshot], _ percentages: [Decimal]) -> [ParticipantSnapshot] {
        zip(people, percentages).map {
            ParticipantSnapshot(id: $0.id, name: $0.name, costSharePercent: $1,
                                colorIndex: $0.colorIndex, sortIndex: $0.sortIndex)
        }
    }

    private func snapshot(_ amount: String,
                          paidBy payer: ParticipantSnapshot,
                          chf: String? = nil) -> ExpenseSnapshot {
        ExpenseSnapshot(id: UUID(),
                        amountOriginal: Decimal(string: amount)!,
                        currencyCode: "EUR",
                        amountTrip: Decimal(string: amount)!,
                        amountCHF: chf.map { Decimal(string: $0)! },
                        paymentPercentages: [payer.id: 100],
                        singlePayerID: payer.id,
                        categoryName: "Test")
    }

    private func splitSnapshot(_ amount: String,
                               shares: [UUID: Decimal],
                               chf: String? = nil) -> ExpenseSnapshot {
        ExpenseSnapshot(id: UUID(),
                        amountOriginal: Decimal(string: amount)!,
                        currencyCode: "EUR",
                        amountTrip: Decimal(string: amount)!,
                        amountCHF: chf.map { Decimal(string: $0)! },
                        paymentPercentages: shares,
                        singlePayerID: nil,
                        categoryName: "Test")
    }

    // MARK: - Zwei Personen

    func testSinglePayerWithTwoPeople() {
        let people = [anna, beat]
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", paidBy: anna)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.total, Decimal(100))
        XCTAssertEqual(result.balance(for: anna.id)?.paid, Decimal(100))
        XCTAssertEqual(result.balance(for: anna.id)?.share, Decimal(50))
        XCTAssertEqual(result.balance(for: anna.id)?.net, Decimal(50))
        XCTAssertEqual(result.balance(for: beat.id)?.net, Decimal(-50))
    }

    // MARK: - Drei Personen

    func testThreePeopleEqualShares() {
        let people = withShares([anna, beat, cem], [Decimal(string: "33.4")!, Decimal(string: "33.3")!, Decimal(string: "33.3")!])
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("300", paidBy: anna)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.share, Decimal(string: "100.20"))
        XCTAssertEqual(result.balance(for: beat.id)?.share, Decimal(string: "99.90"))
        XCTAssertEqual(result.balance(for: cem.id)?.net, Decimal(string: "-99.90"))

        // Die Summe aller Salden muss null ergeben.
        let sum = result.balances.reduce(Decimal(0)) { $0 + $1.net }
        XCTAssertEqual(sum, Decimal(0))
    }

    func testUnevenCostShareWithThreePeople() {
        // Anna trägt die Hälfte, Beat und Cem je einen Viertel.
        let people = withShares([anna, beat, cem], [50, 25, 25])
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("400", paidBy: beat)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.net, Decimal(-200))
        XCTAssertEqual(result.balance(for: beat.id)?.net, Decimal(300))   // 400 gezahlt, 100 getragen
        XCTAssertEqual(result.balance(for: cem.id)?.net, Decimal(-100))
    }

    // MARK: - Gemeinsam bezahlt

    func testSplitPaymentAcrossThreePeople() {
        let people = withShares([anna, beat, cem], [Decimal(string: "33.4")!, Decimal(string: "33.3")!, Decimal(string: "33.3")!])
        let shares: [UUID: Decimal] = [anna.id: 50, beat.id: 30, cem.id: 20]
        let result = BalanceCalculator.tripBalance(snapshots: [splitSnapshot("100", shares: shares)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.paid, Decimal(50))
        XCTAssertEqual(result.balance(for: beat.id)?.paid, Decimal(30))
        XCTAssertEqual(result.balance(for: cem.id)?.paid, Decimal(20))
        XCTAssertEqual(result.balance(for: anna.id)?.net, Decimal(string: "16.60"))
    }

    func testSplitPaymentMatchingCostShareIsNeutral() {
        let people = withShares([anna, beat], [60, 40])
        let shares: [UUID: Decimal] = [anna.id: 60, beat.id: 40]
        let result = BalanceCalculator.tripBalance(snapshots: [splitSnapshot("200", shares: shares)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.net, Decimal(0))
        XCTAssertEqual(result.balance(for: beat.id)?.net, Decimal(0))
    }

    // MARK: - Gemischt

    func testMixedExpensesNetToZero() {
        let people = withShares([anna, beat, cem], [40, 40, 20])
        let snapshots = [
            snapshot("300", paidBy: anna),
            snapshot("150", paidBy: beat),
            splitSnapshot("50", shares: [anna.id: 50, cem.id: 50])
        ]
        let result = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.total, Decimal(500))
        XCTAssertEqual(result.balance(for: anna.id)?.paid, Decimal(325))
        XCTAssertEqual(result.balance(for: cem.id)?.paid, Decimal(25))
        let sum = result.balances.reduce(Decimal(0)) { $0 + $1.net }
        XCTAssertEqual(sum, Decimal(0))
    }

    // MARK: - CHF-Bilanz

    func testCHFBalanceSkipsExpensesWithoutRate() {
        let people = [anna, beat]
        let snapshots = [
            snapshot("100", paidBy: anna, chf: "94.00"),
            snapshot("50", paidBy: beat, chf: nil)          // kein Kurs vorhanden
        ]
        let chf = BalanceCalculator.chfBalance(snapshots: snapshots, participants: people)
        XCTAssertEqual(chf.skippedCount, 1)
        XCTAssertEqual(chf.total, Decimal(string: "94.00"))
        XCTAssertEqual(chf.balance(for: anna.id)?.net, Decimal(string: "47.00"))
    }

    // MARK: - Randfälle

    func testEmptyTripIsBalanced() {
        let result = BalanceCalculator.tripBalance(snapshots: [],
                                                   participants: [anna, beat],
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.total, Decimal(0))
        XCTAssertTrue(result.balances.allSatisfy { $0.net == 0 })
    }

    func testSingleParticipantCarriesEverything() {
        let people = withShares([anna], [100])
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("80", paidBy: anna)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.net, Decimal(0))
    }

    func testZeroCostSharesFallBackToEqualSplit() {
        // Altdaten oder Fehleingabe: keine Anteile gesetzt → gleichmässig teilen,
        // statt falsch zu rechnen.
        let people = withShares([anna, beat], [0, 0])
        let result = BalanceCalculator.tripBalance(snapshots: [snapshot("100", paidBy: anna)],
                                                   participants: people,
                                                   tripCurrency: "EUR")
        XCTAssertEqual(result.balance(for: anna.id)?.share, Decimal(50))
        XCTAssertEqual(result.balance(for: beat.id)?.share, Decimal(50))
    }
}
