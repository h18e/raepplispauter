import Foundation

/// Fixe, bewusst **nicht erweiterbare** Kategorienliste gemäss Spezifikation.
///
/// Die Rohwerte werden in Core Data/CloudKit gespeichert und dürfen deshalb
/// nie geändert werden – nur der Anzeigetext ist lokalisiert.
public enum ExpenseCategory: String, CaseIterable, Identifiable, Sendable {
    case unterkunft
    case restaurant
    case lebensmittel
    case oev
    case auto
    case sightseeing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unterkunft: return L.categoryUnterkunft
        case .restaurant: return L.categoryRestaurant
        case .lebensmittel: return L.categoryLebensmittel
        case .oev: return L.categoryOev
        case .auto: return L.categoryAuto
        case .sightseeing: return L.categorySightseeing
        }
    }

    /// SF-Symbol für Listen, Filter und Auswertung.
    public var symbolName: String {
        switch self {
        case .unterkunft: return "bed.double.fill"
        case .restaurant: return "fork.knife"
        case .lebensmittel: return "basket.fill"
        case .oev: return "tram.fill"
        case .auto: return "car.fill"
        case .sightseeing: return "binoculars.fill"
        }
    }

    /// Stabile Reihenfolge für Auswertung und CSV-Export.
    public static var ordered: [ExpenseCategory] { allCases }
}
