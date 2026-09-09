import Foundation

/// Erzeugt den CSV-Export einer Reise für die iOS-Freigabefunktion.
///
/// Aufbau der Datei (vier Blöcke, durch Leerzeilen getrennt):
/// 1. **Einzeltransaktionen** – jede Ausgabe mit Original-, Reise- und CHF-Betrag,
///    Kurs, Kursdatum, Kursquelle sowie einer Spalte je Person mit deren Auslage
/// 2. **Kategorie-Summen**
/// 3. **Bilanz je Person** – Auslage, Kostenanteil, Saldo
/// 4. **Schlussabrechnung** – wer zahlt wem wie viel
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
                               snapshots: [ExpenseSnapshot],
                               report: TripReport) -> ExportResult {
        var lines: [String] = []
        let participants = report.participants

        // --- Kopf ---------------------------------------------------------
        lines.append(row([L.csvHeaderTrip, tripName]))
        lines.append(row([L.csvHeaderPeriod, formatDateRange(startDate, endDate)]))
        lines.append(row([L.csvHeaderCurrency, tripCurrency]))
        lines.append(row([L.csvHeaderParticipants,
                          participants.map(\.name).joined(separator: ", ")]))
        lines.append(row([L.csvHeaderExported, Formatters.dateTime.string(from: Date())]))
        lines.append("")

        // --- Block 1: Einzeltransaktionen ---------------------------------
        lines.append(row([L.csvSectionTransactions]))
        var header = [
            L.csvColDate, L.csvColTime, L.csvColCategory, L.csvColPurpose,
            L.csvColPayer,
            L.csvColAmount, L.csvColCurrency,
            L.csvColAmountTrip(tripCurrency),
            L.csvColRate, L.csvColAmountCHF,
            L.csvColRateDate, L.csvColRateSource
        ]
        // Eine Spalte je Person: wie viel hat sie an dieser Ausgabe ausgelegt?
        header.append(contentsOf: participants.map { L.csvColPaidBy($0.name) })
        lines.append(row(header))

        for snapshot in snapshots.sorted(by: { $0.date < $1.date }) {
            var fields = [
                Formatters.dateOnly.string(from: snapshot.date),
                Formatters.timeOnly.string(from: snapshot.date),
                snapshot.categoryName,
                snapshot.note,
                payerLabel(snapshot, participants: participants),
                Money.csvNumber(snapshot.amountOriginal),
                snapshot.currencyCode,
                Money.csvNumber(snapshot.amountTrip),
                snapshot.rateToCHF.map { Money.csvNumber($0, fractionDigits: 6) } ?? "",
                snapshot.amountCHF.map { Money.csvNumber($0) } ?? "",
                snapshot.rateDate.map { Formatters.dateOnly.string(from: $0) } ?? "",
                snapshot.rateSource.displayName
            ]
            let paid = snapshot.paidAmounts(total: snapshot.amountTrip)
            for participant in participants {
                let amount = paid[participant.id] ?? 0
                fields.append(amount > 0 ? Money.csvNumber(Money.round(amount, scale: 2)) : "")
            }
            lines.append(row(fields))
        }
        lines.append("")

        // --- Block 2: Kategorie-Summen ------------------------------------
        lines.append(row([L.csvSectionCategories]))
        lines.append(row([L.csvColCategory, L.csvColCount,
                          L.csvColAmountTrip(tripCurrency), L.csvColAmountCHF]))
        for category in report.categories {
            lines.append(row([
                category.name,
                String(category.count),
                Money.csvNumber(category.totalTrip),
                Money.csvNumber(category.totalCHF)
            ]))
        }
        lines.append(row([L.csvTotal,
                          String(report.expenseCount),
                          Money.csvNumber(report.tripBalance.total),
                          Money.csvNumber(report.chfBalance.total)]))
        lines.append("")

        // --- Block 3: Bilanz je Person ------------------------------------
        lines.append(row([L.csvSectionBalance]))
        lines.append(row([
            L.csvColPerson, L.csvColCostShare,
            L.csvColPaidTrip(tripCurrency), L.csvColShareTrip(tripCurrency), L.csvColNetTrip(tripCurrency),
            L.csvColPaidCHF, L.csvColShareCHF, L.csvColNetCHF
        ]))
        for participant in participants {
            let trip = report.tripBalance.balance(for: participant.id)
            let chf = report.chfBalance.balance(for: participant.id)
            lines.append(row([
                participant.name,
                Money.csvNumber(participant.costSharePercent, fractionDigits: 1),
                Money.csvNumber(trip?.paid ?? 0),
                Money.csvNumber(trip?.share ?? 0),
                Money.csvNumber(trip?.net ?? 0),
                Money.csvNumber(chf?.paid ?? 0),
                Money.csvNumber(chf?.share ?? 0),
                Money.csvNumber(chf?.net ?? 0)
            ]))
        }
        lines.append("")

        // --- Block 4: Schlussabrechnung -----------------------------------
        lines.append(row([L.csvSectionSettlement]))
        if report.settlementTrip.isBalanced {
            lines.append(row([L.settlementBalanced]))
        } else {
            lines.append(row([L.csvColFrom, L.csvColTo,
                              L.csvColAmountTrip(tripCurrency), L.csvColAmountCHF]))
            // Die CHF-Abrechnung kann aufgrund der Rundung anders aufgeteilt sein;
            // sie wird deshalb separat und vollständig ausgewiesen.
            for transfer in report.settlementTrip.transfers {
                lines.append(row([transfer.from.name, transfer.to.name,
                                  Money.csvNumber(transfer.amount), ""]))
            }
            for transfer in report.settlementCHF.transfers {
                lines.append(row([transfer.from.name, transfer.to.name,
                                  "", Money.csvNumber(transfer.amount)]))
            }
        }

        if report.provisionalCount > 0 {
            lines.append("")
            lines.append(row([L.csvNoteMissingRates(report.provisionalCount)]))
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        return ExportResult(fileName: makeFileName(tripName: tripName), csv: csv)
    }

    /// Schreibt den Export in eine temporäre Datei und gibt deren URL zurück
    /// (Eingabe für die iOS-Freigabefunktion).
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

    static func payerLabel(_ snapshot: ExpenseSnapshot, participants: [ParticipantSnapshot]) -> String {
        if let singleID = snapshot.singlePayerID {
            return participants.first { $0.id == singleID }?.name ?? L.participantUnnamed
        }
        let names = participants
            .filter { (snapshot.paymentPercentages[$0.id] ?? 0) > 0 }
            .map(\.name)
        return names.isEmpty ? L.payerShared : names.joined(separator: " + ")
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
}
