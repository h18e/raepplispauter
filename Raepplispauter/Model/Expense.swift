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
///
/// **Zahler:** Ist `payer` gesetzt, hat genau diese Person ausgelegt. Ist `payer`
/// leer, haben mehrere bezahlt – dann gilt die Aufteilung in `paymentShares`.
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
    @NSManaged public var note: String?
    @NSManaged public var date: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    /// Wer hat zuletzt geändert – Basis für die Konflikt-Nachvollziehbarkeit.
    @NSManaged public var lastEditedBy: String?
    @NSManaged public var trip: Trip?
    @NSManaged public var category: ExpenseCategory?
    /// Alleiniger Zahler. `nil` = mehrere haben bezahlt (siehe `paymentShares`).
    @NSManaged public var payer: Participant?
    @NSManaged public var paymentShares: NSSet?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Expense> {
        NSFetchRequest<Expense>(entityName: "Expense")
    }

    // MARK: - Typisierte Zugriffe

    public var rateSource: RateSource {
        get { RateSource(rawValue: rateSourceRaw ?? "") ?? .unknown }
        set { rateSourceRaw = newValue.rawValue }
    }

    public var currency: String { currencyCode ?? trip?.currency ?? "EUR" }

    public var amountDecimal: Decimal { amount?.decimalValue ?? 0 }
    public var amountTripDecimal: Decimal { amountTrip?.decimalValue ?? amountDecimal }
    public var amountCHFDecimal: Decimal? { isRateProvisional ? nil : amountCHF?.decimalValue }

    /// Haben mehrere Personen zusammen ausgelegt?
    public var isSplitPayment: Bool { payer == nil }

    public var shareList: [PaymentShare] {
        let all = (paymentShares as? Set<PaymentShare>) ?? []
        return all.sorted {
            ($0.participant?.sortIndex ?? 0) < ($1.participant?.sortIndex ?? 0)
        }
    }

    /// Auslage je Person in Prozent – unabhängig davon, ob eine oder mehrere
    /// Personen bezahlt haben.
    public var paymentPercentages: [UUID: Decimal] {
        if let payer, let id = payer.id {
            return [id: 100]
        }
        var result: [UUID: Decimal] = [:]
        for share in shareList {
            guard let id = share.participant?.id, share.percent > 0 else { continue }
            result[id, default: 0] += Decimal(share.percent)
        }
        return result
    }

    public var displayNote: String {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (category?.displayName ?? L.expenseFallbackName) : trimmed
    }

    public var categoryName: String { category?.displayName ?? L.categoryUnnamed }

    /// Bezeichnung des Zahlers für Listen und Export.
    public var payerDescription: String {
        if let payer { return payer.displayName }
        let names = shareList
            .filter { $0.percent > 0 }
            .compactMap { $0.participant?.displayName }
        return names.isEmpty ? L.payerShared : names.joined(separator: " + ")
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
        expense.category = trip.categoryList.first
        expense.payer = trip.participantList.first
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

    /// Ersetzt die Auslage-Aufteilung. Bei einem einzelnen Zahler werden alle
    /// Anteile entfernt, damit keine widersprüchlichen Daten zurückbleiben.
    public func setPayment(singlePayer: Participant?,
                           shares: [UUID: Double],
                           in context: NSManagedObjectContext) {
        for existing in shareList {
            context.delete(existing)
        }
        payer = singlePayer
        guard singlePayer == nil, let trip else { return }
        for participant in trip.participantList {
            guard let id = participant.id, let percent = shares[id], percent > 0 else { continue }
            PaymentShare.create(in: context, expense: self, participant: participant, percent: percent)
        }
    }
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
