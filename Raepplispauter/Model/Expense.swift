import CoreData
import Foundation

/// Eine einzelne Ausgabe innerhalb einer Reise.
///
/// Beträge werden dreifach abgelegt, damit alle Ansichten offline und ohne
/// Neuberechnung funktionieren:
/// 1. `amount` / `currencyCode` – exakt so, wie erfasst
/// 2. `amountTrip`             – umgerechnet in die Reisewährung (2 Nachkommastellen)
/// 3. `amountCHF`              – umgerechnet in CHF, auf 5 Rappen gerundet
///
/// Die verwendeten Kurse werden zusammen mit Kursdatum und Quelle eingefroren,
/// damit eine Ausgabe später nicht plötzlich einen anderen CHF-Wert hat.
@objc(Expense)
public final class Expense: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var currencyCode: String?
    @NSManaged public var amountTrip: NSDecimalNumber?
    @NSManaged public var amountCHF: NSDecimalNumber?
    /// Kurs Ausgabewährung → CHF zum Erfassungsdatum.
    @NSManaged public var rateToCHF: NSDecimalNumber?
    /// Kurs Reisewährung → CHF zum selben Datum (für die Anzeige in Reisewährung).
    @NSManaged public var rateTripToCHF: NSDecimalNumber?
    @NSManaged public var rateDate: Date?
    @NSManaged public var rateSourceRaw: String?
    /// true, solange kein echter Kurs vorlag (offline ohne Cache). Der Betrag wird
    /// dann nicht in die CHF-Bilanz eingerechnet und in der UI markiert.
    @NSManaged public var isRateProvisional: Bool
    @NSManaged public var payerRaw: String?
    /// Auslage-Anteil von Person A in Prozent – nur relevant bei Zahler "Gemeinsam".
    @NSManaged public var splitPercentA: Double
    @NSManaged public var categoryRaw: String?
    @NSManaged public var note: String?
    @NSManaged public var date: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    /// Gerätename/Person der letzten Änderung – Basis für die Konflikt-Nachvollziehbarkeit.
    @NSManaged public var lastEditedBy: String?
    @NSManaged public var trip: Trip?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        NSFetchRequest<Expense>(entityName: "Expense")
    }

    // MARK: - Typisierte Zugriffe

    public var payer: Payer {
        get { Payer(rawValue: payerRaw ?? "") ?? .a }
        set { payerRaw = newValue.rawValue }
    }

    public var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw ?? "") ?? .restaurant }
        set { categoryRaw = newValue.rawValue }
    }

    public var rateSource: RateSource {
        get { RateSource(rawValue: rateSourceRaw ?? "") ?? .unknown }
        set { rateSourceRaw = newValue.rawValue }
    }

    public var currency: String { currencyCode ?? trip?.currency ?? "EUR" }

    public var amountDecimal: Decimal { amount?.decimalValue ?? 0 }
    public var amountTripDecimal: Decimal { amountTrip?.decimalValue ?? amountDecimal }
    public var amountCHFDecimal: Decimal? { isRateProvisional ? nil : amountCHF?.decimalValue }

    public var displayNote: String {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.displayName : trimmed
    }

    // MARK: - Factory

    @discardableResult
    public static func create(in context: NSManagedObjectContext, trip: Trip) -> Expense {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.trip = trip
        expense.date = Date()
        expense.createdAt = Date()
        expense.updatedAt = Date()
        expense.currencyCode = trip.currency
        expense.category = .restaurant
        expense.payer = .a
        expense.splitPercentA = 50
        expense.note = ""
        expense.amount = 0
        // Bei zwei Stores (privat/geteilt) muss eine neue Ausgabe explizit in
        // denselben Store wie ihre Reise – sonst schlägt das Speichern fehl.
        if let store = trip.objectID.persistentStore {
            context.assign(expense, to: store)
        }
        return expense
    }

    /// Setzt alle abgeleiteten Betragsfelder anhand eines Umrechnungsergebnisses.
    public func applyConversion(_ conversion: CurrencyConversion) {
        amount = NSDecimalNumber(decimal: conversion.originalAmount)
        currencyCode = conversion.originalCurrency
        amountTrip = NSDecimalNumber(decimal: conversion.amountInTripCurrency)
        amountCHF = NSDecimalNumber(decimal: conversion.amountInCHF)
        rateToCHF = NSDecimalNumber(decimal: conversion.rateToCHF)
        rateTripToCHF = NSDecimalNumber(decimal: conversion.rateTripToCHF)
        rateDate = conversion.rateDate
        rateSource = conversion.source
        isRateProvisional = conversion.isProvisional
    }
}

/// Rolle einer Person innerhalb einer Reise.
public enum Person: String, CaseIterable, Identifiable, Sendable {
    case a = "A"
    case b = "B"

    public var id: String { rawValue }

    /// Vorgabe gemäss Projektentscheid: Person A = Raphi, Person B = Gini.
    public static let defaultNameA = "Raphi"
    public static let defaultNameB = "Gini"

    public var other: Person { self == .a ? .b : .a }
}

/// Wer hat die Ausgabe ausgelegt?
public enum Payer: String, CaseIterable, Identifiable, Sendable {
    /// Person A hat den ganzen Betrag ausgelegt.
    case a = "A"
    /// Person B hat den ganzen Betrag ausgelegt.
    case b = "B"
    /// Beide haben ausgelegt – aufgeteilt nach `Expense.splitPercentA`.
    case shared = "SHARED"

    public var id: String { rawValue }
}

/// Herkunft des verwendeten Wechselkurses – wird pro Ausgabe eingefroren.
public enum RateSource: String, CaseIterable, Sendable {
    /// Frisch von der EZB geladener Referenzkurs des Erfassungstages.
    case ecbLive = "ecb"
    /// Aus dem lokalen Kurs-Cache (evtl. Kurs eines früheren Bankarbeitstages).
    case ecbCached = "ecb_cached"
    /// Kurs 1:1, weil Ausgabewährung = Zielwährung.
    case identity = "identity"
    /// Manuell erfasster Kurs.
    case manual = "manual"
    /// Kein Kurs verfügbar (offline und kein Cache) – Betrag ist provisorisch.
    case unavailable = "unavailable"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .ecbLive: return L.rateSourceEcbLive
        case .ecbCached: return L.rateSourceEcbCached
        case .identity: return L.rateSourceIdentity
        case .manual: return L.rateSourceManual
        case .unavailable: return L.rateSourceUnavailable
        case .unknown: return L.rateSourceUnknown
        }
    }
}
