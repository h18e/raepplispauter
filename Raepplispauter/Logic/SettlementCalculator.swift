import Foundation

/// Eine einzelne Ausgleichszahlung: `from` zahlt `amount` an `to`.
public struct Transfer: Equatable, Identifiable, Sendable {
    public let from: ParticipantSnapshot
    public let to: ParticipantSnapshot
    public let amount: Decimal
    public let currencyCode: String

    public var id: String { "\(from.id)-\(to.id)" }

    public init(from: ParticipantSnapshot, to: ParticipantSnapshot, amount: Decimal, currencyCode: String) {
        self.from = from
        self.to = to
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

/// Schlussabrechnung: die Liste der nötigen Zahlungen.
public struct Settlement: Equatable, Sendable {
    public let transfers: [Transfer]
    public let currencyCode: String

    public var isBalanced: Bool { transfers.isEmpty }

    public init(transfers: [Transfer], currencyCode: String) {
        self.transfers = transfers
        self.currencyCode = currencyCode
    }
}

/// Eine Zeile der Kategorie-Auswertung.
public struct CategoryBreakdownRow: Identifiable, Equatable, Sendable {
    public let categoryID: UUID?
    public let name: String
    public let symbolName: String
    public let colorIndex: Int
    public let count: Int
    public let totalTrip: Decimal
    public let totalCHF: Decimal

    public var id: String { categoryID?.uuidString ?? "ohne-\(name)" }
}

/// Eine Zeile der Zahler-Auswertung.
public struct PayerBreakdownRow: Identifiable, Equatable, Sendable {
    public let participant: ParticipantSnapshot
    /// Anzahl Ausgaben, an denen diese Person als Zahlerin beteiligt war.
    public let count: Int
    public let totalTrip: Decimal
    public let totalCHF: Decimal

    public var id: UUID { participant.id }
}

/// Vollständige Auswertung einer Kassä – Grundlage für Abrechnung und CSV.
public struct TripReport: Sendable {
    public let tripCurrency: String
    public let participants: [ParticipantSnapshot]
    public let tripBalance: BalanceResult
    public let chfBalance: BalanceResult
    public let settlementTrip: Settlement
    public let settlementCHF: Settlement
    public let categories: [CategoryBreakdownRow]
    public let payers: [PayerBreakdownRow]
    public let expenseCount: Int
    /// Anzahl Ausgaben ohne gültigen Wechselkurs (nur Kassä-Währung verwertbar).
    public let provisionalCount: Int
}

public enum SettlementCalculator {

    /// Leitet aus einer Bilanz die nötigen Ausgleichszahlungen ab.
    ///
    /// Verfahren: Gläubiger (Plus) und Schuldner (Minus) werden nach Betrag
    /// sortiert und wiederholt gegeneinander verrechnet – jeweils der grösste
    /// Schuldner gegen den grössten Gläubiger. Das ergibt bei n Personen
    /// **höchstens n−1 Zahlungen** statt jeder-mit-jedem.
    ///
    /// Beträge werden währungsgerecht gerundet (CHF auf 5 Rappen); Restbeträge
    /// unterhalb der kleinsten Einheit entfallen.
    public static func settlement(from balance: BalanceResult) -> Settlement {
        let currency = balance.currencyCode

        var creditors: [(participant: ParticipantSnapshot, amount: Decimal)] = []
        var debtors: [(participant: ParticipantSnapshot, amount: Decimal)] = []

        for entry in balance.balances {
            let net = Money.roundForCurrency(entry.net, currencyCode: currency)
            if net > 0 {
                creditors.append((entry.participant, net))
            } else if net < 0 {
                debtors.append((entry.participant, -net))
            }
        }

        creditors.sort { $0.amount > $1.amount }
        debtors.sort { $0.amount > $1.amount }

        var transfers: [Transfer] = []
        var creditorIndex = 0
        var debtorIndex = 0

        while creditorIndex < creditors.count && debtorIndex < debtors.count {
            let amount = min(creditors[creditorIndex].amount, debtors[debtorIndex].amount)
            let rounded = Money.roundForCurrency(amount, currencyCode: currency)

            if !Money.isZero(rounded) {
                transfers.append(Transfer(from: debtors[debtorIndex].participant,
                                          to: creditors[creditorIndex].participant,
                                          amount: rounded,
                                          currencyCode: currency))
            }

            creditors[creditorIndex].amount -= amount
            debtors[debtorIndex].amount -= amount

            if Money.isZero(creditors[creditorIndex].amount) { creditorIndex += 1 }
            if Money.isZero(debtors[debtorIndex].amount) { debtorIndex += 1 }
        }

        return Settlement(transfers: transfers, currencyCode: currency)
    }

    /// Erstellt die komplette Auswertung einer Kassä.
    public static func report(snapshots: [ExpenseSnapshot],
                              participants: [ParticipantSnapshot],
                              tripCurrency: String) -> TripReport {
        let tripBalance = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                        participants: participants,
                                                        tripCurrency: tripCurrency)
        let chfBalance = BalanceCalculator.chfBalance(snapshots: snapshots,
                                                      participants: participants)

        // --- Kategorien ---------------------------------------------------
        // Reihenfolge nach erstem Auftreten, damit sie der Kategorienliste der
        // Kassä folgt und nicht bei jeder Neuberechnung springt.
        var categoryOrder: [String] = []
        var categoryData: [String: (row: CategoryBreakdownRow, key: String)] = [:]

        for snapshot in snapshots {
            let key = snapshot.categoryID?.uuidString ?? "ohne-\(snapshot.categoryName)"
            if let existing = categoryData[key] {
                let row = existing.row
                categoryData[key] = (CategoryBreakdownRow(categoryID: row.categoryID,
                                                          name: row.name,
                                                          symbolName: row.symbolName,
                                                          colorIndex: row.colorIndex,
                                                          count: row.count + 1,
                                                          totalTrip: row.totalTrip + snapshot.amountTrip,
                                                          totalCHF: row.totalCHF + (snapshot.amountCHF ?? 0)),
                                     key)
            } else {
                categoryOrder.append(key)
                categoryData[key] = (CategoryBreakdownRow(categoryID: snapshot.categoryID,
                                                          name: snapshot.categoryName,
                                                          symbolName: snapshot.categorySymbol,
                                                          colorIndex: snapshot.categoryColorIndex,
                                                          count: 1,
                                                          totalTrip: snapshot.amountTrip,
                                                          totalCHF: snapshot.amountCHF ?? 0),
                                     key)
            }
        }

        let categories = categoryOrder.compactMap { key -> CategoryBreakdownRow? in
            guard let row = categoryData[key]?.row else { return nil }
            return CategoryBreakdownRow(categoryID: row.categoryID,
                                        name: row.name,
                                        symbolName: row.symbolName,
                                        colorIndex: row.colorIndex,
                                        count: row.count,
                                        totalTrip: Money.round(row.totalTrip, scale: 2),
                                        totalCHF: Money.round(row.totalCHF, scale: 2))
        }
        .sorted { $0.totalTrip > $1.totalTrip }

        // --- Zahler -------------------------------------------------------
        let payers = participants.compactMap { participant -> PayerBreakdownRow? in
            var totalTrip = Decimal(0)
            var totalCHF = Decimal(0)
            var count = 0

            for snapshot in snapshots {
                guard let percent = snapshot.paymentPercentages[participant.id], percent > 0 else { continue }
                count += 1
                totalTrip += snapshot.amountTrip * percent / 100
                totalCHF += (snapshot.amountCHF ?? 0) * percent / 100
            }

            guard count > 0 else { return nil }
            return PayerBreakdownRow(participant: participant,
                                     count: count,
                                     totalTrip: Money.round(totalTrip, scale: 2),
                                     totalCHF: Money.round(totalCHF, scale: 2))
        }

        return TripReport(tripCurrency: tripCurrency,
                          participants: participants,
                          tripBalance: tripBalance,
                          chfBalance: chfBalance,
                          settlementTrip: settlement(from: tripBalance),
                          settlementCHF: settlement(from: chfBalance),
                          categories: categories,
                          payers: payers,
                          expenseCount: snapshots.count,
                          provisionalCount: snapshots.filter { $0.amountCHF == nil }.count)
    }
}
