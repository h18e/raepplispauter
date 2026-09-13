import CoreData
import Foundation

/// Eine Person, die zu einer Kassä gehört.
///
/// Eine Kassä kennt beliebig viele Personen. Gemeinsame Ausgaben werden
/// gleichmässig auf alle verteilt: `costSharePercent` ist deshalb immer
/// `100 / Anzahl Personen` und wird beim Speichern der Kassä gesetzt
/// (`SplitCalculator.equalShares`), nicht von Hand eingestellt.
///
/// Das Feld bleibt trotzdem erhalten, statt die Gleichteilung fest
/// einzurechnen: Es steht so im CloudKit-Schema, und ein Attribut zu entfernen
/// hiesse, das Schema zu ändern und alle bestehenden Daten zu migrieren. Die
/// Berechnung (`BalanceCalculator`) arbeitet weiterhin mit den Prozentwerten
/// und käme damit auch mit ungleichen Anteilen aus älteren Kassä zurecht.
@objc(Participant)
public final class Participant: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    /// Kostenanteil in Prozent (0…100). Wird beim Speichern gleichmässig gesetzt.
    @NSManaged public var costSharePercent: Double
    /// Reihenfolge in Listen und Auswertungen.
    @NSManaged public var sortIndex: Int16
    /// Index in die Farbpalette (`Theme.participantColor`).
    @NSManaged public var colorIndex: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var trip: Trip?
    @NSManaged public var paidExpenses: NSSet?
    @NSManaged public var paymentShares: NSSet?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Participant> {
        NSFetchRequest<Participant>(entityName: "Participant")
    }

    public var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L.participantUnnamed : trimmed
    }

    public var costShareDecimal: Decimal { Decimal(costSharePercent) }

    /// Kürzel für kompakte Darstellungen (Initialen, max. 2 Zeichen).
    public var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "?" : text
    }

    /// Wird diese Person irgendwo verwendet? Dann darf sie nicht gelöscht werden,
    /// sonst verlöre man die Zuordnung bereits erfasster Ausgaben.
    public var isUsed: Bool {
        if let paid = paidExpenses, paid.count > 0 { return true }
        if let shares = paymentShares as? Set<PaymentShare> {
            // Anteile mit 0 % sind nur Karteileichen und zählen nicht.
            return shares.contains { $0.percent > 0 && $0.expense != nil }
        }
        return false
    }

    /// - Parameter id: Lässt sich vorgeben, damit eine im Editor vorbereitete
    ///   Person nach dem Speichern dieselbe Kennung behält (wichtig für die
    ///   Zuordnung "das bin ich").
    @discardableResult
    public static func create(in context: NSManagedObjectContext,
                              trip: Trip,
                              name: String,
                              costSharePercent: Double = 0,
                              id: UUID = UUID()) -> Participant {
        let participant = Participant(context: context)
        participant.id = id
        participant.name = name
        participant.costSharePercent = costSharePercent
        participant.sortIndex = Int16(trip.participantList.count)
        participant.colorIndex = Int16(trip.participantList.count % Theme.participantPaletteSize)
        participant.createdAt = Date()
        participant.trip = trip
        if let store = trip.objectID.persistentStore {
            context.assign(participant, to: store)
        }
        return participant
    }
}
