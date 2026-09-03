import Foundation

/// Schlussabrechnung: wer schuldet wem wie viel.
public struct Settlement: Equatable, Sendable {
    /// `nil`, wenn die Bilanz ausgeglichen ist.
    public let debtor: Person?
    public let creditor: Person?
    /// Immer positiv; in CHF auf 5 Rappen, sonst auf 2 Stellen gerundet.
    public let amount: Decimal
    public let currencyCode: String

    public var isBalanced: Bool { debtor == nil || Money.isZero(amount) }

    public init(debtor: Person?, creditor: Person?, amount: Decimal, currencyCode: String) {
        self.debtor = debtor
        self.creditor = creditor
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

/// Eine Zeile der Kategorie-Auswertung.
public struct CategoryBreakdownRow: Identifiable, Equatable, Sendable {
    public let category: ExpenseCategory
    public let count: Int
    public let totalTrip: Decimal
    public let totalCHF: Decimal
    /// Vom jeweiligen Zahler ausgelegte Beträge (Reisewährung).
    public let paidATrip: Decimal
    public let paidBTrip: Decimal

    public var id: String { category.rawValue }
}

/// Eine Zeile der Zahler-Auswertung.
public struct PayerBreakdownRow: Identifiable, Equatable, Sendable {
    public let payer: Payer
    public let count: Int
    public let totalTrip: Decimal
    public let totalCHF: Decimal

    public var id: String { payer.rawValue }
}

/// Vollständige Auswertung einer Reise – Grundlage für Abrechnungs-Ansicht und CSV.
public struct TripReport: Sendable {
    public let tripCurrency: String
    public let tripBalance: BalanceResult
    public let chfBalance: BalanceResult
    public let settlementTrip: Settlement
    public let settlementCHF: Settlement
    public let categories: [CategoryBreakdownRow]
    public let payers: [PayerBreakdownRow]
    public let expenseCount: Int
    /// Anzahl Ausgaben ohne gültigen Wechselkurs (nur Reisewährung verwertbar).
    public let provisionalCount: Int
}

public enum SettlementCalculator {

    /// Leitet aus einer Bilanz die Schuldbeziehung ab.
    public static func settlement(from balance: BalanceResult) -> Settlement {
        let net = balance.netA
        let rounded = Money.roundForCurrency(abs(net), currencyCode: balance.currencyCode)

        if Money.isZero(rounded) {
            return Settlement(debtor: nil, creditor: nil, amount: 0, currencyCode: balance.currencyCode)
        }
        // net > 0  → A hat zu viel ausgelegt → B schuldet A.
        // net < 0  → B hat zu viel ausgelegt → A schuldet B.
        return net > 0
            ? Settlement(debtor: .b, creditor: .a, amount: rounded, currencyCode: balance.currencyCode)
            : Settlement(debtor: .a, creditor: .b, amount: rounded, currencyCode: balance.currencyCode)
    }

    /// Erstellt die komplette Auswertung einer Reise.
    public static func report(snapshots: [ExpenseSnapshot],
                              tripCurrency: String,
                              costSharePercentA: Decimal) -> TripReport {
        let tripBalance = BalanceCalculator.tripBalance(snapshots: snapshots,
                                                        tripCurrency: tripCurrency,
                                                        costSharePercentA: costSharePercentA)
        let chfBalance = BalanceCalculator.chfBalance(snapshots: snapshots,
                                                      costSharePercentA: costSharePercentA)

        var categories: [CategoryBreakdownRow] = []
        for category in ExpenseCategory.ordered {
            let matching = snapshots.filter { $0.category == category }
            guard !matching.isEmpty else { continue }

            var totalTrip = Decimal(0)
            var totalCHF = Decimal(0)
            var paidATrip = Decimal(0)
            var paidBTrip = Decimal(0)

            for snapshot in matching {
                totalTrip += snapshot.amountTrip
                totalCHF += snapshot.amountCHF ?? 0
                let paid = snapshot.paidAmounts(total: snapshot.amountTrip)
                paidATrip += paid.a
                paidBTrip += paid.b
            }

            categories.append(CategoryBreakdownRow(category: category,
                                                   count: matching.count,
                                                   totalTrip: Money.round(totalTrip, scale: 2),
                                                   totalCHF: Money.round(totalCHF, scale: 2),
                                                   paidATrip: Money.round(paidATrip, scale: 2),
                                                   paidBTrip: Money.round(paidBTrip, scale: 2)))
        }

        var payers: [PayerBreakdownRow] = []
        for payer in Payer.allCases {
            let matching = snapshots.filter { $0.payer == payer }
            guard !matching.isEmpty else { continue }
            let totalTrip = matching.reduce(Decimal(0)) { $0 + $1.amountTrip }
            let totalCHF = matching.reduce(Decimal(0)) { $0 + ($1.amountCHF ?? 0) }
            payers.append(PayerBreakdownRow(payer: payer,
                                            count: matching.count,
                                            totalTrip: Money.round(totalTrip, scale: 2),
                                            totalCHF: Money.round(totalCHF, scale: 2)))
        }

        return TripReport(tripCurrency: tripCurrency,
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
