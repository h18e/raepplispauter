import Foundation

/// Bilanz einer Person in **einer** Währung.
public struct PersonBalance: Equatable, Identifiable, Sendable {
    public let participant: ParticipantSnapshot
    /// Wie viel diese Person ausgelegt hat.
    public let paid: Decimal
    /// Wie viel diese Person gemäss Kostenschlüssel tragen müsste.
    public let share: Decimal
    /// Positiv = hat zu viel ausgelegt (steht im Plus), negativ = schuldet noch.
    public var net: Decimal { paid - share }

    public var id: UUID { participant.id }
    public var name: String { participant.name }

    public init(participant: ParticipantSnapshot, paid: Decimal, share: Decimal) {
        self.participant = participant
        self.paid = paid
        self.share = share
    }
}

/// Gesamtbilanz einer Reise in **einer** Währung.
public struct BalanceResult: Equatable, Sendable {
    public let currencyCode: String
    public let total: Decimal
    /// Bilanz je Person, in der Reihenfolge der Personenliste.
    public let balances: [PersonBalance]
    /// Anzahl Ausgaben, die mangels Wechselkurs nicht einfliessen konnten.
    public let skippedCount: Int

    public init(currencyCode: String, total: Decimal, balances: [PersonBalance], skippedCount: Int = 0) {
        self.currencyCode = currencyCode
        self.total = total
        self.balances = balances
        self.skippedCount = skippedCount
    }

    public func balance(for participantID: UUID) -> PersonBalance? {
        balances.first { $0.id == participantID }
    }

    /// Nettosalden als Abbildung – Eingabe für die Schlussabrechnung.
    public var netByParticipant: [UUID: Decimal] {
        balances.reduce(into: [:]) { $0[$1.id] = $1.net }
    }
}

/// Kernstück der Berechnungslogik – für beliebig viele Personen.
///
/// **Modell:**
///
/// * *Zahler* beschreibt, **wer ausgelegt** hat. Entweder eine einzelne Person
///   (100 %) oder mehrere, aufgeteilt nach den Anteilen der Ausgabe.
///
/// * *Kostenschlüssel* beschreibt, **wer trägt**: Jede Person der Reise hat einen
///   Prozentsatz (`Participant.costSharePercent`), die Summe ergibt immer 100 %.
///   Standard ist die gleichmässige Verteilung.
///
/// Daraus folgt die Bilanz: `netto(Person) = ausgelegt(Person) − getragen(Person)`.
///
/// Beispiel mit drei Personen zu je ⅓ und einer Ausgabe von 90 €, die Anna
/// allein bezahlt hat: Anna +60, Beat −30, Cem −30.
public enum BalanceCalculator {

    /// Ein einzelner Rechnungsposten, reduziert auf das für die Bilanz Nötige.
    public struct Item: Sendable {
        public let amount: Decimal
        /// Auslage je Person in Prozent (Summe 100).
        public let paymentPercentages: [UUID: Decimal]

        public init(amount: Decimal, paymentPercentages: [UUID: Decimal]) {
            self.amount = amount
            self.paymentPercentages = paymentPercentages
        }
    }

    /// Bilanz über beliebige Posten in einer Währung.
    public static func balance(items: [Item],
                               participants: [ParticipantSnapshot],
                               currencyCode: String,
                               skippedCount: Int = 0) -> BalanceResult {
        var total = Decimal(0)
        var paid: [UUID: Decimal] = [:]

        for item in items {
            total += item.amount
            for (participantID, percent) in item.paymentPercentages {
                paid[participantID, default: 0] += item.amount * percent / 100
            }
        }

        // Kostenschlüssel normalisieren: Sollte die Summe der Anteile (etwa durch
        // Altdaten) nicht 100 ergeben, wird proportional gerechnet statt falsch.
        let shareSum = participants.reduce(Decimal(0)) { $0 + $1.costSharePercent }
        let divisor = shareSum > 0 ? shareSum : Decimal(max(participants.count, 1))

        let balances = participants.map { participant -> PersonBalance in
            let weight = shareSum > 0 ? participant.costSharePercent : 1
            return PersonBalance(participant: participant,
                                 paid: Money.round(paid[participant.id] ?? 0, scale: 2),
                                 share: Money.round(total * weight / divisor, scale: 2))
        }

        return BalanceResult(currencyCode: currencyCode,
                             total: Money.round(total, scale: 2),
                             balances: balances,
                             skippedCount: skippedCount)
    }

    /// Bilanz in der Reisewährung.
    public static func tripBalance(snapshots: [ExpenseSnapshot],
                                   participants: [ParticipantSnapshot],
                                   tripCurrency: String) -> BalanceResult {
        let items = snapshots.map {
            Item(amount: $0.amountTrip, paymentPercentages: $0.paymentPercentages)
        }
        return balance(items: items, participants: participants, currencyCode: tripCurrency)
    }

    /// Bilanz in CHF. Ausgaben ohne gültigen Kurs werden übersprungen und gezählt,
    /// damit die UI transparent darauf hinweisen kann.
    public static func chfBalance(snapshots: [ExpenseSnapshot],
                                  participants: [ParticipantSnapshot]) -> BalanceResult {
        var items: [Item] = []
        var skipped = 0
        for snapshot in snapshots {
            guard let chf = snapshot.amountCHF else {
                skipped += 1
                continue
            }
            items.append(Item(amount: chf, paymentPercentages: snapshot.paymentPercentages))
        }
        return balance(items: items,
                       participants: participants,
                       currencyCode: Currencies.home,
                       skippedCount: skipped)
    }
}
