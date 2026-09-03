import Foundation

/// Bilanz einer Person in **einer** Währung.
public struct PersonBalance: Equatable, Sendable {
    /// Wie viel diese Person ausgelegt hat.
    public let paid: Decimal
    /// Wie viel diese Person gemäss Kostenschlüssel tragen müsste.
    public let share: Decimal
    /// Positiv = hat zu viel ausgelegt (steht im Plus), negativ = schuldet noch.
    public var net: Decimal { paid - share }

    public init(paid: Decimal, share: Decimal) {
        self.paid = paid
        self.share = share
    }
}

/// Gesamtbilanz einer Reise in **einer** Währung.
public struct BalanceResult: Equatable, Sendable {
    public let currencyCode: String
    public let total: Decimal
    public let a: PersonBalance
    public let b: PersonBalance
    /// Anzahl Ausgaben, die mangels Wechselkurs nicht einfliessen konnten.
    public let skippedCount: Int

    public init(currencyCode: String, total: Decimal, a: PersonBalance, b: PersonBalance, skippedCount: Int = 0) {
        self.currencyCode = currencyCode
        self.total = total
        self.a = a
        self.b = b
        self.skippedCount = skippedCount
    }

    /// Nettosaldo aus Sicht von Person A (positiv = A steht im Plus).
    public var netA: Decimal { a.net }

    public func balance(for person: Person) -> PersonBalance {
        person == .a ? a : b
    }
}

/// Kernstück der Berechnungslogik.
///
/// **Modell (bewusst so festgelegt, siehe README):**
///
/// * *Zahler* beschreibt, **wer ausgelegt** hat:
///   - `A` → Person A hat 100 % des Betrags bezahlt
///   - `B` → Person B hat 100 % des Betrags bezahlt
///   - `Gemeinsam` → beide haben bezahlt, im Verhältnis `splitPercentA` (Standard 50/50)
///
/// * *Kostenträger* ist immer die gemeinsame Ferienkasse: jede Ausgabe wird nach
///   dem Reise-Schlüssel `costSharePercentA` getragen (Standard 50/50, pro Reise
///   anpassbar).
///
/// Daraus folgt die Bilanz: `netto(A) = ausgelegt(A) − getragen(A)`.
/// Beispiel: 100 € von A bezahlt, Kostenschlüssel 50/50 → A steht mit 50 € im Plus,
/// B schuldet A 50 €. Eine "Gemeinsam 60/40"-Ausgabe von 100 € bei 50/50-Kosten
/// ergibt für A ein Plus von 10 €.
public enum BalanceCalculator {

    /// Ein einzelner Rechnungsposten, reduziert auf das für die Bilanz Nötige.
    public struct Item: Sendable {
        public let amount: Decimal
        public let payer: Payer
        public let splitPercentA: Decimal

        public init(amount: Decimal, payer: Payer, splitPercentA: Decimal = 50) {
            self.amount = amount
            self.payer = payer
            self.splitPercentA = splitPercentA
        }
    }

    /// Bilanz über beliebige Posten in einer Währung.
    public static func balance(items: [Item],
                               costSharePercentA: Decimal,
                               currencyCode: String,
                               skippedCount: Int = 0) -> BalanceResult {
        var total = Decimal(0)
        var paidA = Decimal(0)
        var paidB = Decimal(0)

        for item in items {
            total += item.amount
            switch item.payer {
            case .a:
                paidA += item.amount
            case .b:
                paidB += item.amount
            case .shared:
                let a = item.amount * item.splitPercentA / 100
                paidA += a
                paidB += item.amount - a
            }
        }

        let shareA = total * costSharePercentA / 100
        let shareB = total - shareA

        // Zwischenresultate immer auf 2 Stellen; die 5-Rappen-Rundung greift erst
        // beim Festschreiben eines Betrags (Ausgabe) und beim Schlusssaldo.
        let scale = 2
        return BalanceResult(currencyCode: currencyCode,
                             total: Money.round(total, scale: scale),
                             a: PersonBalance(paid: Money.round(paidA, scale: scale),
                                              share: Money.round(shareA, scale: scale)),
                             b: PersonBalance(paid: Money.round(paidB, scale: scale),
                                              share: Money.round(shareB, scale: scale)),
                             skippedCount: skippedCount)
    }

    /// Bilanz in der Reisewährung.
    public static func tripBalance(snapshots: [ExpenseSnapshot],
                                   tripCurrency: String,
                                   costSharePercentA: Decimal) -> BalanceResult {
        let items = snapshots.map {
            Item(amount: $0.amountTrip, payer: $0.payer, splitPercentA: $0.splitPercentA)
        }
        return balance(items: items, costSharePercentA: costSharePercentA, currencyCode: tripCurrency)
    }

    /// Bilanz in CHF. Ausgaben ohne gültigen Kurs werden übersprungen und gezählt,
    /// damit die UI transparent darauf hinweisen kann.
    public static func chfBalance(snapshots: [ExpenseSnapshot],
                                  costSharePercentA: Decimal) -> BalanceResult {
        var items: [Item] = []
        var skipped = 0
        for snapshot in snapshots {
            guard let chf = snapshot.amountCHF else {
                skipped += 1
                continue
            }
            items.append(Item(amount: chf, payer: snapshot.payer, splitPercentA: snapshot.splitPercentA))
        }
        return balance(items: items,
                       costSharePercentA: costSharePercentA,
                       currencyCode: Currencies.home,
                       skippedCount: skipped)
    }
}
