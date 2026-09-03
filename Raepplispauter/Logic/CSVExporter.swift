import Foundation

/// Erzeugt den CSV-Export einer Reise für die iOS-Freigabefunktion.
///
/// Aufbau der Datei (drei Blöcke, durch Leerzeilen getrennt):
/// 1. **Einzeltransaktionen** – jede Ausgabe mit Original-, Reise- und CHF-Betrag,
///    Kurs, Kursdatum und Kursquelle
/// 2. **Kategorie-Summen**
/// 3. **Schlusssaldo** – Auslagen, Kostenanteile und die Schuldbeziehung
///
/// Trennzeichen ist das Semikolon (Excel de-CH öffnet die Datei damit direkt),
/// Zahlen verwenden den Punkt als Dezimaltrennzeichen. Ein UTF-8-BOM stellt
/// sicher, dass Umlaute auch in Excel korrekt erscheinen.
public enum CSVExporter {

    public static let separator = ";"

    public struct ExportResult {
        public let fileName: String
        public let csv: String
    }

    public static func makeCSV(tripName: String,
                               tripCurrency: String,
                               startDate: Date?,
                               endDate: Date?,
                               nameA: String,
                               nameB: String,
                               snapshots: [ExpenseSnapshot],
                               report: TripReport) -> ExportResult {
        var lines: [String] = []

        // --- Kopf ---------------------------------------------------------
        lines.append(row([L.csvHeaderTrip, tripName]))
        lines.append(row([L.csvHeaderPeriod, formatDateRange(startDate, endDate)]))
        lines.append(row([L.csvHeaderCurrency, tripCurrency]))
        lines.append(row([L.csvHeaderExported, Formatters.dateTime.string(from: Date())]))
        lines.append("")

        // --- Block 1: Einzeltransaktionen ---------------------------------
        lines.append(row([L.csvSectionTransactions]))
        lines.append(row([
            L.csvColDate, L.csvColTime, L.csvColCategory, L.csvColPurpose,
            L.csvColPayer, L.csvColSplitA,
            L.csvColAmount, L.csvColCurrency,
            L.csvColAmountTrip(tripCurrency),
            L.csvColRate, L.csvColAmountCHF,
            L.csvColRateDate, L.csvColRateSource
        ]))

        for snapshot in snapshots.sorted(by: { $0.date < $1.date }) {
            lines.append(row([
                Formatters.dateOnly.string(from: snapshot.date),
                Formatters.timeOnly.string(from: snapshot.date),
                snapshot.category.displayName,
                snapshot.note,
                payerLabel(snapshot.payer, nameA: nameA, nameB: nameB),
                snapshot.payer == .shared ? Money.csvNumber(snapshot.splitPercentA, fractionDigits: 0) : "",
                Money.csvNumber(snapshot.amountOriginal),
                snapshot.currencyCode,
                Money.csvNumber(snapshot.amountTrip),
                snapshot.rateToCHF.map { Money.csvNumber($0, fractionDigits: 6) } ?? "",
                snapshot.amountCHF.map { Money.csvNumber($0) } ?? "",
                snapshot.rateDate.map { Formatters.dateOnly.string(from: $0) } ?? "",
                snapshot.rateSource.displayName
            ]))
        }
        lines.append("")

        // --- Block 2: Kategorie-Summen ------------------------------------
        lines.append(row([L.csvSectionCategories]))
        lines.append(row([
            L.csvColCategory, L.csvColCount,
            L.csvColAmountTrip(tripCurrency), L.csvColAmountCHF,
            L.csvColPaidBy(nameA), L.csvColPaidBy(nameB)
        ]))
        for category in report.categories {
            lines.append(row([
                category.category.displayName,
                String(category.count),
                Money.csvNumber(category.totalTrip),
                Money.csvNumber(category.totalCHF),
                Money.csvNumber(category.paidATrip),
                Money.csvNumber(category.paidBTrip)
            ]))
        }
        lines.append(row([
            L.csvTotal,
            String(report.expenseCount),
            Money.csvNumber(report.tripBalance.total),
            Money.csvNumber(report.chfBalance.total),
            Money.csvNumber(report.tripBalance.a.paid),
            Money.csvNumber(report.tripBalance.b.paid)
        ]))
        lines.append("")

        // --- Block 3: Schlusssaldo ----------------------------------------
        lines.append(row([L.csvSectionSettlement]))
        lines.append(row([L.csvColItem, tripCurrency, Currencies.home]))
        lines.append(row([L.csvRowPaid(nameA),
                          Money.csvNumber(report.tripBalance.a.paid),
                          Money.csvNumber(report.chfBalance.a.paid)]))
        lines.append(row([L.csvRowPaid(nameB),
                          Money.csvNumber(report.tripBalance.b.paid),
                          Money.csvNumber(report.chfBalance.b.paid)]))
        lines.append(row([L.csvRowShare(nameA),
                          Money.csvNumber(report.tripBalance.a.share),
                          Money.csvNumber(report.chfBalance.a.share)]))
        lines.append(row([L.csvRowShare(nameB),
                          Money.csvNumber(report.tripBalance.b.share),
                          Money.csvNumber(report.chfBalance.b.share)]))
        lines.append(row([L.csvRowNet(nameA),
                          Money.csvNumber(report.tripBalance.netA),
                          Money.csvNumber(report.chfBalance.netA)]))
        lines.append(row([L.csvRowSettlement,
                          settlementText(report.settlementTrip, nameA: nameA, nameB: nameB),
                          settlementText(report.settlementCHF, nameA: nameA, nameB: nameB)]))

        if report.provisionalCount > 0 {
            lines.append("")
            lines.append(row([L.csvNoteMissingRates(report.provisionalCount)]))
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        return ExportResult(fileName: makeFileName(tripName: tripName), csv: csv)
    }

    /// Schreibt den Export in eine temporäre Datei und gibt deren URL zurück
    /// (Eingabe für `ShareLink` bzw. `UIActivityViewController`).
    public static func writeTemporaryFile(_ result: ExportResult) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(result.fileName)
        try? FileManager.default.removeItem(at: url)
        try result.csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Hilfsfunktionen

    static func makeFileName(tripName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = tripName.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { partial, character in
                if character == "-" && partial.hasSuffix("-") { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = slug.isEmpty ? "Reise" : slug
        return "Raepplispauter-\(stem)-\(Formatters.fileDate.string(from: Date())).csv"
    }

    /// Maskiert Felder nach RFC 4180 (Anführungszeichen verdoppeln, bei
    /// Trennzeichen/Zeilenumbruch/Anführungszeichen in Quotes setzen).
    static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(separator)
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: separator)
    }

    static func payerLabel(_ payer: Payer, nameA: String, nameB: String) -> String {
        switch payer {
        case .a: return nameA
        case .b: return nameB
        case .shared: return L.payerShared
        }
    }

    static func settlementText(_ settlement: Settlement, nameA: String, nameB: String) -> String {
        guard let debtor = settlement.debtor, let creditor = settlement.creditor else {
            return L.settlementBalanced
        }
        let debtorName = debtor == .a ? nameA : nameB
        let creditorName = creditor == .a ? nameA : nameB
        return "\(debtorName) → \(creditorName): \(Money.csvNumber(settlement.amount)) \(settlement.currencyCode)"
    }

    static func formatDateRange(_ start: Date?, _ end: Date?) -> String {
        switch (start, end) {
        case let (start?, end?):
            return "\(Formatters.dateOnly.string(from: start)) – \(Formatters.dateOnly.string(from: end))"
        case let (start?, nil):
            return Formatters.dateOnly.string(from: start)
        case let (nil, end?):
            return Formatters.dateOnly.string(from: end)
        default:
            return ""
        }
    }
}

/// Zentrale Datumsformate (de-CH).
public enum Formatters {
    public static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    public static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    public static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// ISO-Tagesdatum in UTC – Schlüssel des Wechselkurs-Caches und des EZB-Feeds.
    public static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
