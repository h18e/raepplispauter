import CoreData
import Foundation

/// Core-Data-freie Momentaufnahme einer Person.
public struct ParticipantSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// Anteil an den gemeinsamen Kosten in Prozent.
    public let costSharePercent: Decimal
    public let colorIndex: Int
    public let sortIndex: Int

    public init(id: UUID, name: String, costSharePercent: Decimal, colorIndex: Int = 0, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.costSharePercent = costSharePercent
        self.colorIndex = colorIndex
        self.sortIndex = sortIndex
    }

    public init(participant: Participant) {
        self.init(id: participant.id ?? UUID(),
                  name: participant.displayName,
                  costSharePercent: participant.costShareDecimal,
                  colorIndex: Int(participant.colorIndex),
                  sortIndex: Int(participant.sortIndex))
    }
}

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
    /// Betrag in der Kassä-Währung.
    public let amountTrip: Decimal
    /// Betrag in CHF (5-Rappen-gerundet). `nil`, wenn kein Kurs vorlag.
    public let amountCHF: Decimal?

    public let rateToCHF: Decimal?
    public let rateTripToCHF: Decimal?
    public let rateDate: Date?
    public let rateSource: RateSource
    public let isRateProvisional: Bool

    /// Auslage je Person in Prozent. Bei einem einzelnen Zahler enthält die
    /// Abbildung genau einen Eintrag mit 100.
    public let paymentPercentages: [UUID: Decimal]
    /// Gesetzt, wenn genau eine Person ausgelegt hat.
    public let singlePayerID: UUID?

    public let categoryID: UUID?
    public let categoryName: String
    public let categorySymbol: String
    public let categoryColorIndex: Int

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
                paymentPercentages: [UUID: Decimal],
                singlePayerID: UUID? = nil,
                categoryID: UUID? = nil,
                categoryName: String = "",
                categorySymbol: String = "tag.fill",
                categoryColorIndex: Int = 0,
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
        self.paymentPercentages = paymentPercentages
        self.singlePayerID = singlePayerID
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categorySymbol = categorySymbol
        self.categoryColorIndex = categoryColorIndex
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
                  paymentPercentages: expense.paymentPercentages,
                  singlePayerID: expense.payer?.id,
                  categoryID: expense.category?.id,
                  categoryName: expense.categoryName,
                  categorySymbol: expense.category?.symbol ?? "tag.fill",
                  categoryColorIndex: Int(expense.category?.colorIndex ?? 0),
                  note: expense.note ?? "",
                  date: expense.date ?? Date(),
                  lastEditedBy: expense.lastEditedBy)
    }

    /// Wer hat wie viel ausgelegt, in Geld statt Prozent.
    public func paidAmounts(total: Decimal) -> [UUID: Decimal] {
        paymentPercentages.mapValues { total * $0 / 100 }
    }

    /// Haben mehrere Personen zusammen bezahlt?
    public var isSplitPayment: Bool { singlePayerID == nil }
}
