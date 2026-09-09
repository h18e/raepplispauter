import XCTest
@testable import Raepplispauter

/// Tests zum CSV-Export.
final class CSVExporterTests: XCTestCase {

    private let anna = ParticipantSnapshot(id: UUID(), name: "Anna", costSharePercent: 40, sortIndex: 0)
    private let beat = ParticipantSnapshot(id: UUID(), name: "Beat", costSharePercent: 35, sortIndex: 1)
    private let cem = ParticipantSnapshot(id: UUID(), name: "Cem", costSharePercent: 25, sortIndex: 2)

    private var participants: [ParticipantSnapshot] { [anna, beat, cem] }

    private func makeSnapshots() -> [ExpenseSnapshot] {
        [
            ExpenseSnapshot(id: UUID(),
                            amountOriginal: Decimal(string: "120")!,
                            currencyCode: "EUR",
                            amountTrip: Decimal(string: "120")!,
                            amountCHF: Decimal(string: "112.80")!,
                            rateToCHF: Decimal(string: "0.94")!,
                            rateTripToCHF: Decimal(string: "0.94")!,
                            rateDate: Date(timeIntervalSince1970: 1_760_000_000),
                            rateSource: .ecbLive,
                            paymentPercentages: [anna.id: 100],
                            singlePayerID: anna.id,
                            categoryName: "Unterkunft",
                            note: "Agriturismo; mit Frühstück",
                            date: Date(timeIntervalSince1970: 1_760_000_000)),
            ExpenseSnapshot(id: UUID(),
                            amountOriginal: Decimal(string: "40")!,
                            currencyCode: "EUR",
                            amountTrip: Decimal(string: "40")!,
                            amountCHF: Decimal(string: "37.60")!,
                            rateToCHF: Decimal(string: "0.94")!,
                            rateTripToCHF: Decimal(string: "0.94")!,
                            rateDate: Date(timeIntervalSince1970: 1_760_086_400),
                            rateSource: .ecbCached,
                            paymentPercentages: [beat.id: 60, cem.id: 40],
                            singlePayerID: nil,
                            categoryName: "Restaurant",
                            note: "Znacht",
                            date: Date(timeIntervalSince1970: 1_760_086_400))
        ]
    }

    private func makeExport() -> CSVExporter.ExportResult {
        let snapshots = makeSnapshots()
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 participants: participants,
                                                 tripCurrency: "EUR")
        return CSVExporter.makeCSV(tripName: "Toskana 2026",
                                   tripCurrency: "EUR",
                                   startDate: Date(timeIntervalSince1970: 1_760_000_000),
                                   endDate: Date(timeIntervalSince1970: 1_760_600_000),
                                   snapshots: snapshots,
                                   report: report)
    }

    func testCSVContainsAllFourBlocks() {
        let csv = makeExport().csv
        XCTAssertTrue(csv.contains(L.csvSectionTransactions))
        XCTAssertTrue(csv.contains(L.csvSectionCategories))
        XCTAssertTrue(csv.contains(L.csvSectionBalance))
        XCTAssertTrue(csv.contains(L.csvSectionSettlement))
    }

    func testCSVStartsWithBOMForExcel() {
        XCTAssertTrue(makeExport().csv.hasPrefix("\u{FEFF}"))
    }

    func testCSVEscapesSeparatorInsideField() {
        let csv = makeExport().csv
        // Der Verwendungszweck enthält ein Semikolon und muss deshalb gequotet sein.
        XCTAssertTrue(csv.contains("\"Agriturismo; mit Frühstück\""))
    }

    func testEscapeDoublesQuotes() {
        XCTAssertEqual(CSVExporter.escape("Sag \"hoi\""), "\"Sag \"\"hoi\"\"\"")
        XCTAssertEqual(CSVExporter.escape("ohni"), "ohni")
    }

    func testCSVContainsBothCurrencies() {
        let csv = makeExport().csv
        XCTAssertTrue(csv.contains("112.80"))   // CHF
        XCTAssertTrue(csv.contains("120.00"))   // EUR
    }

    func testCSVContainsEveryParticipant() {
        let csv = makeExport().csv
        for participant in participants {
            XCTAssertTrue(csv.contains(participant.name), "\(participant.name) fehlt im Export")
        }
    }

    func testCSVHasOneColumnPerParticipant() {
        let csv = makeExport().csv
        for participant in participants {
            XCTAssertTrue(csv.contains(L.csvColPaidBy(participant.name)))
        }
    }

    func testSplitPaymentIsBrokenDownPerParticipant() {
        let csv = makeExport().csv
        // 40 EUR, 60/40 geteilt → 24.00 und 16.00 in den Personenspalten.
        XCTAssertTrue(csv.contains("24.00"))
        XCTAssertTrue(csv.contains("16.00"))
        // Und beide Namen stehen in der Zahler-Spalte.
        XCTAssertTrue(csv.contains("Beat + Cem"))
    }

    func testFileNameIsSafeAndDated() {
        let name = CSVExporter.makeFileName(tripName: "Toskana 2026 / Süden")
        XCTAssertTrue(name.hasPrefix("Raepplispauter-"))
        XCTAssertTrue(name.hasSuffix(".csv"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(" "))
    }

    func testWriteTemporaryFileProducesReadableFile() throws {
        let result = makeExport()
        let url = try CSVExporter.writeTemporaryFile(result)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("Toskana 2026"))
        XCTAssertEqual(url.lastPathComponent, result.fileName)
    }
}
