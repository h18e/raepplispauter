import CoreData
import Foundation

/// Eine Ausgabenkategorie.
///
/// Kategorien gehören zur Reise (nicht zum Gerät) – dadurch wandern sie beim
/// CloudKit-Sharing mit und beide Geräte sehen dieselbe Liste. Beim Anlegen einer
/// Reise wird ein Satz Standardkategorien erzeugt; eigene lassen sich jederzeit
/// ergänzen, umbenennen und – solange keine Ausgabe sie verwendet – löschen.
@objc(ExpenseCategory)
public final class ExpenseCategory: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    /// SF-Symbol-Name.
    @NSManaged public var symbolName: String?
    @NSManaged public var colorIndex: Int16
    @NSManaged public var sortIndex: Int16
    /// true = beim Anlegen der Reise mitgeliefert.
    @NSManaged public var isBuiltIn: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var trip: Trip?
    @NSManaged public var expenses: NSSet?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ExpenseCategory> {
        NSFetchRequest<ExpenseCategory>(entityName: "ExpenseCategory")
    }

    public var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L.categoryUnnamed : trimmed
    }

    public var symbol: String {
        let trimmed = (symbolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "tag.fill" : trimmed
    }

    public var expenseCount: Int { expenses?.count ?? 0 }

    /// Nur unbenutzte Kategorien dürfen gelöscht werden – sonst hätten Ausgaben
    /// plötzlich keine Kategorie mehr.
    public var isUsed: Bool { expenseCount > 0 }

    @discardableResult
    public static func create(in context: NSManagedObjectContext,
                              trip: Trip,
                              name: String,
                              symbolName: String,
                              colorIndex: Int,
                              isBuiltIn: Bool = false) -> ExpenseCategory {
        let category = ExpenseCategory(context: context)
        category.id = UUID()
        category.name = name
        category.symbolName = symbolName
        category.colorIndex = Int16(colorIndex % Theme.categoryPaletteSize)
        category.sortIndex = Int16(trip.categoryList.count)
        category.isBuiltIn = isBuiltIn
        category.createdAt = Date()
        category.trip = trip
        if let store = trip.objectID.persistentStore {
            context.assign(category, to: store)
        }
        return category
    }

    // MARK: - Standardkategorien

    /// Wird beim Anlegen einer Reise angelegt. Frei erweiterbar und löschbar –
    /// das ist nur der Startsatz, damit man sofort erfassen kann.
    public struct Template {
        public let name: String
        public let symbolName: String
    }

    public static var defaultTemplates: [Template] {
        [
            Template(name: L.categoryUnterkunft, symbolName: "bed.double.fill"),
            Template(name: L.categoryRestaurant, symbolName: "fork.knife"),
            Template(name: L.categoryLebensmittel, symbolName: "basket.fill"),
            Template(name: L.categoryOev, symbolName: "tram.fill"),
            Template(name: L.categoryAuto, symbolName: "car.fill"),
            Template(name: L.categorySightseeing, symbolName: "binoculars.fill")
        ]
    }

    /// Auswahl an SF-Symbolen für selbst erfasste Kategorien.
    public static let availableSymbols: [String] = [
        "tag.fill", "bed.double.fill", "fork.knife", "basket.fill", "tram.fill",
        "car.fill", "binoculars.fill", "airplane", "ferry.fill", "bicycle",
        "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill", "gift.fill",
        "bag.fill", "cart.fill", "ticket.fill", "theatermasks.fill", "music.note",
        "figure.hiking", "figure.pool.swimming", "sportscourt.fill", "mountain.2.fill",
        "beach.umbrella.fill", "camera.fill", "book.fill", "cross.case.fill",
        "pills.fill", "fuelpump.fill", "parkingsign", "phone.fill", "wifi",
        "creditcard.fill", "banknote.fill", "house.fill", "building.2.fill",
        "sun.max.fill", "snowflake", "pawprint.fill", "leaf.fill"
    ]
}
