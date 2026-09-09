import CoreData
import Foundation

/// Eine Reise – Wurzelobjekt für Personen, Kategorien und Ausgaben.
///
/// Wichtig für CloudKit-Sharing: Der `CKShare` wird immer auf dem *Trip* erstellt.
/// Personen, Kategorien, Ausgaben und Zahlungsanteile hängen über Beziehungen
/// daran und wandern dadurch automatisch mit in die geteilte CloudKit-Zone.
@objc(Trip)
public final class Trip: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    /// Landeswährung der Reise (ISO-4217, z. B. "EUR").
    @NSManaged public var currencyCode: String?
    /// Status: abgeschlossen ja/nein (aktiv = false).
    /// Ist eine Reise abgeschlossen, lassen sich keine Ausgaben mehr erfassen,
    /// ändern oder löschen – die Abrechnung bleibt damit stabil.
    @NSManaged public var isClosed: Bool
    /// Zwischengespeicherter Sharing-Status für schnelle Anzeige (auch offline).
    @NSManaged public var isShared: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var participants: NSSet?
    @NSManaged public var categories: NSSet?
    @NSManaged public var expenses: NSSet?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trip> {
        NSFetchRequest<Trip>(entityName: "Trip")
    }

    // MARK: - Bequeme Zugriffe

    public var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L.tripUnnamed : trimmed
    }

    public var currency: String { currencyCode ?? "EUR" }

    /// Personen in stabiler Reihenfolge.
    public var participantList: [Participant] {
        let all = (participants as? Set<Participant>) ?? []
        return all.sorted {
            $0.sortIndex != $1.sortIndex
                ? $0.sortIndex < $1.sortIndex
                : ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    /// Kategorien in stabiler Reihenfolge.
    public var categoryList: [ExpenseCategory] {
        let all = (categories as? Set<ExpenseCategory>) ?? []
        return all.sorted {
            $0.sortIndex != $1.sortIndex
                ? $0.sortIndex < $1.sortIndex
                : ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    /// Alle Ausgaben, chronologisch absteigend (neuste zuoberst).
    public var sortedExpenses: [Expense] {
        let all = (expenses as? Set<Expense>) ?? []
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Momentaufnahmen für die reine Berechnungslogik (Core-Data-frei, testbar).
    public var snapshots: [ExpenseSnapshot] {
        sortedExpenses.map(ExpenseSnapshot.init(expense:))
    }

    public var participantSnapshots: [ParticipantSnapshot] {
        participantList.map(ParticipantSnapshot.init(participant:))
    }

    public func participant(with id: UUID) -> Participant? {
        participantList.first { $0.id == id }
    }

    /// Darf an dieser Reise überhaupt noch etwas geändert werden?
    public var isEditable: Bool { !isClosed }

    // MARK: - Factory

    /// Legt eine neue Reise an und weist sie explizit dem **privaten** Store zu.
    ///
    /// Die Zuweisung ist zwingend, weil der Container zwei Stores führt (privat +
    /// geteilt); ohne `assign` wäre nicht definiert, in welchem Store das Objekt landet.
    @discardableResult
    public static func create(in context: NSManagedObjectContext,
                              name: String,
                              startDate: Date,
                              endDate: Date,
                              currencyCode: String,
                              assignTo store: NSPersistentStore? = nil) -> Trip {
        let trip = Trip(context: context)
        trip.id = UUID()
        trip.name = name
        trip.startDate = startDate
        trip.endDate = endDate
        trip.currencyCode = currencyCode
        trip.isClosed = false
        trip.isShared = false
        trip.createdAt = Date()
        trip.updatedAt = Date()
        if let store {
            context.assign(trip, to: store)
        }
        trip.addDefaultCategories(in: context)
        return trip
    }

    /// Erzeugt den Startsatz an Kategorien. Frei erweiterbar und löschbar.
    public func addDefaultCategories(in context: NSManagedObjectContext) {
        guard categoryList.isEmpty else { return }
        for (index, template) in ExpenseCategory.defaultTemplates.enumerated() {
            ExpenseCategory.create(in: context,
                                   trip: self,
                                   name: template.name,
                                   symbolName: template.symbolName,
                                   colorIndex: index,
                                   isBuiltIn: true)
        }
    }
}
