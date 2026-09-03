import CoreData
import Foundation

/// Eine Reise (Ferienabschnitt), die als Wurzel-Objekt via CloudKit geteilt wird.
///
/// Wichtig für CloudKit-Sharing: Der `CKShare` wird immer auf dem *Trip* erstellt.
/// Alle `Expense`-Objekte hängen über die Beziehung `expenses` daran und wandern
/// dadurch automatisch mit in die geteilte CloudKit-Zone.
@objc(Trip)
public final class Trip: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    /// Landeswährung der Reise (ISO-4217, z. B. "EUR").
    @NSManaged public var currencyCode: String?
    /// Status: abgeschlossen ja/nein (aktiv = false).
    @NSManaged public var isClosed: Bool
    /// Zwischengespeicherter Sharing-Status. Die Wahrheit liefert `SharingController.isShared(_:)`,
    /// dieses Flag dient nur der schnellen Anzeige in Listen (auch offline).
    @NSManaged public var isShared: Bool
    /// Anzeigename Person A – Standard "Raphi".
    @NSManaged public var personAName: String?
    /// Anzeigename Person B – Standard "Gini".
    @NSManaged public var personBName: String?
    /// Kostenträger-Schlüssel der Reise: Anteil von Person A an *allen* Ausgaben (Standard 50 %).
    /// Siehe `BalanceCalculator` für die genaue Bedeutung.
    @NSManaged public var costSharePercentA: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
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

    public var nameA: String {
        let trimmed = (personAName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Person.defaultNameA : trimmed
    }

    public var nameB: String {
        let trimmed = (personBName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Person.defaultNameB : trimmed
    }

    public func name(for role: Person) -> String {
        role == .a ? nameA : nameB
    }

    /// Alle Ausgaben, chronologisch absteigend (neuste zuoberst).
    public var sortedExpenses: [Expense] {
        let all = (expenses as? Set<Expense>) ?? []
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Momentaufnahmen für die reine Berechnungslogik (Core-Data-frei, damit testbar).
    public var snapshots: [ExpenseSnapshot] {
        sortedExpenses.map(ExpenseSnapshot.init(expense:))
    }

    public var costSharePercentADecimal: Decimal {
        Decimal(costSharePercentA)
    }

    // MARK: - Factory

    /// Legt eine neue Reise an und weist sie explizit dem **privaten** Store zu.
    ///
    /// Die Zuweisung ist zwingend, weil der Container zwei Stores führt (privat + geteilt);
    /// ohne `assign` wäre nicht definiert, in welchem Store das Objekt landet.
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
        trip.personAName = Person.defaultNameA
        trip.personBName = Person.defaultNameB
        trip.costSharePercentA = 50
        trip.createdAt = Date()
        trip.updatedAt = Date()
        if let store {
            context.assign(trip, to: store)
        }
        return trip
    }
}
