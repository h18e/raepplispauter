import CoreData
import Foundation

/// Core-Data-freie Momentaufnahme einer Ausgabe.
///
/// Die gesamte Berechnungslogik (Bilanz, Abrechnung, Auswertung, CSV) arbeitet
/// ausschliesslich auf diesen Werten. Damit ist sie ohne Persistenzschicht
/// testbar und kann gefahrlos auf Hintergrund-Queues laufen.
public struct ExpenseSnapshot: Identifiable {

    public let id: UUID
    public let objectID: NSManagedObjectID?

    /// Betrag in der Währung, in der er erfasst wurde.
    public let amountOriginal: Decimal
    public let currencyCode: String
    /// Betrag in der Reisewährung.
    public let amountTrip: Decimal
    /// Betrag in CHF (5-Rappen-gerundet). `nil`, wenn kein Kurs vorlag.
    public let amountCHF: Decimal?

    public let rateToCHF: Decimal?
    public let rateTripToCHF: Decimal?
    public let rateDate: Date?
    public let rateSource: RateSource
    public let isRateProvisional: Bool

    public let payer: Payer
    /// Auslage-Anteil Person A in Prozent (nur bei `payer == .shared` relevant).
    public let splitPercentA: Decimal
    public let category: ExpenseCategory
    public let note: String
    public let date: Date
    public let lastEditedBy: String?

    public init(id: UUID,
                objectID: NSManagedObjectID? = nil,
                amountOriginal: Decimal,
                currencyCode: String,
                amountTrip: Decimal,
                amountCHF: Decimal?,
                rateToCHF: Decimal? = nil,
                rateTripToCHF: Decimal? = nil,
                rateDate: Date? = nil,
                rateSource: RateSource = .unknown,
                isRateProvisional: Bool = false,
                payer: Payer,
                splitPercentA: Decimal = 50,
                category: ExpenseCategory,
                note: String = "",
                date: Date = Date(),
                lastEditedBy: String? = nil) {
        self.id = id
        self.objectID = objectID
        self.amountOriginal = amountOriginal
        self.currencyCode = currencyCode
        self.amountTrip = amountTrip
        self.amountCHF = amountCHF
        self.rateToCHF = rateToCHF
        self.rateTripToCHF = rateTripToCHF
        self.rateDate = rateDate
        self.rateSource = rateSource
        self.isRateProvisional = isRateProvisional
        self.payer = payer
        self.splitPercentA = splitPercentA
        self.category = category
        self.note = note
        self.date = date
        self.lastEditedBy = lastEditedBy
    }

    public init(expense: Expense) {
        self.init(id: expense.id ?? UUID(),
                  objectID: expense.objectID,
                  amountOriginal: expense.amountDecimal,
                  currencyCode: expense.currency,
                  amountTrip: expense.amountTripDecimal,
                  amountCHF: expense.amountCHFDecimal,
                  rateToCHF: expense.rateToCHF?.decimalValue,
                  rateTripToCHF: expense.rateTripToCHF?.decimalValue,
                  rateDate: expense.rateDate,
                  rateSource: expense.rateSource,
                  isRateProvisional: expense.isRateProvisional,
                  payer: expense.payer,
                  splitPercentA: Decimal(expense.splitPercentA),
                  category: expense.category,
                  note: expense.note ?? "",
                  date: expense.date ?? Date(),
                  lastEditedBy: expense.lastEditedBy)
    }

    /// Wer hat wie viel ausgelegt? – abhängig vom Zahler und (bei "Gemeinsam")
    /// vom Aufteilungsschlüssel.
    public func paidAmounts(total: Decimal) -> (a: Decimal, b: Decimal) {
        switch payer {
        case .a:
            return (total, 0)
        case .b:
            return (0, total)
        case .shared:
            let shareA = total * splitPercentA / 100
            return (shareA, total - shareA)
        }
    }
}
