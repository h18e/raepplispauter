import XCTest
@testable import Raepplispauter

/// Tests zum CSV-Export.
final class CSVExporterTests: XCTestCase {

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
                            payer: .a,
                            category: .unterkunft,
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
                            payer: .shared,
                            splitPercentA: 60,
                            category: .restaurant,
                            note: "Znacht",
                            date: Date(timeIntervalSince1970: 1_760_086_400))
        ]
    }

    private func makeExport() -> CSVExporter.ExportResult {
        let snapshots = makeSnapshots()
        let report = SettlementCalculator.report(snapshots: snapshots,
                                                 tripCurrency: "EUR",
                                                 costSharePercentA: 50)
        return CSVExporter.makeCSV(tripName: "Toskana 2026",
                                   tripCurrency: "EUR",
                                   startDate: Date(timeIntervalSince1970: 1_760_000_000),
                                   endDate: Date(timeIntervalSince1970: 1_760_600_000),
                                   nameA: "Raphi",
                                   nameB: "Gini",
                                   snapshots: snapshots,
                                   report: report)
    }

    func testCSVContainsAllThreeBlocks() {
        let csv = makeExport().csv
        XCTAssertTrue(csv.contains(L.csvSectionTransactions))
        XCTAssertTrue(csv.contains(L.csvSectionCategories))
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

    func testCSVContainsPersonNames() {
        let csv = makeExport().csv
        XCTAssertTrue(csv.contains("Raphi"))
        XCTAssertTrue(csv.contains("Gini"))
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
