import Foundation

/// Schnittstelle zwischen der App und dem Sperrbildschirm-Widget.
///
/// Diese Datei gehört **beiden** Targets an (App *und* Widget-Erweiterung) –
/// deshalb liegt sie in `Shared/` und nicht in einem der beiden Ordner.
///
/// **Warum eine Momentaufnahme statt Core Data im Widget?**
///
/// Naheliegend wäre, das Widget direkt in den Datenspeicher schauen zu lassen.
/// Das hiesse aber: die Speicherdateien in einen App-Group-Container umziehen
/// (samt Migration der schon erfassten Kassä), das Datenmodell im Widget
/// nochmals vorhalten und CloudKit aus einer Erweiterung heraus betreiben –
/// ein tiefer Eingriff in den Sync für drei Zahlen auf dem Sperrbildschirm.
///
/// Stattdessen legt die App nach jeder Änderung eine winzige Momentaufnahme in
/// den geteilten `UserDefaults` ab; das Widget liest nur noch diese. Der
/// Datenspeicher bleibt unangetastet, und ein Fehler im Widget kann den
/// Kassä-Daten nichts anhaben.
public enum WidgetSharing {

    /// App-Group, über die App und Widget dieselben `UserDefaults` sehen.
    /// Muss in **beiden** Entitlements-Dateien eingetragen sein.
    public static let appGroupID = "group.ch.hebera.raepplispauter"

    /// Kennung des Widgets – verbindet `StaticConfiguration(kind:)` mit
    /// `WidgetCenter.reloadTimelines(ofKind:)`.
    public static let widgetKind = "RaepplispauterKassaWidget"

    private static let snapshotKey = "widget.kassaSnapshot"

    /// `nil`, wenn die App-Group (noch) nicht eingerichtet ist. Alle Zugriffe
    /// unten gehen damit ins Leere, statt abzustürzen – das Widget zeigt dann
    /// seinen leeren Zustand.
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static func load() -> KassaWidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(KassaWidgetSnapshot.self, from: data)
    }

    /// `nil` löscht die Momentaufnahme – etwa wenn die letzte Kassä weg ist.
    public static func save(_ snapshot: KassaWidgetSnapshot?) {
        guard let defaults else { return }
        guard let snapshot else {
            defaults.removeObject(forKey: snapshotKey)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}

/// Was das Widget über die aktuelle Kassä wissen muss – mehr nicht.
///
/// Die Beträge stehen bewusst **fertig formatiert** drin. Das Formatieren
/// (Währung, 5-Rappen-Rundung) steckt in `Money` im App-Target; würde das
/// Widget selbst rechnen, könnten Sperrbildschirm und App verschiedene Zahlen
/// zeigen. So gibt es nur eine Quelle.
public struct KassaWidgetSnapshot: Codable, Equatable, Sendable {

    /// Wie steht die Person an diesem Gerät da?
    public enum Standing: String, Codable, Sendable {
        /// Bekommt Geld zurück.
        case getsBack
        /// Schuldet noch etwas.
        case owes
        /// Saldo null.
        case balanced
        /// "Das bin ich" ist nicht gesetzt – ein persönlicher Saldo wäre geraten.
        case unknownPerson
    }

    public var tripName: String
    public var standing: Standing
    /// Saldo in der Kassä-Währung, z. B. "+42.50 €". `nil` bei `unknownPerson`.
    public var netText: String?
    /// Derselbe Saldo in CHF. `nil`, wenn kein Kurs vorlag.
    public var netCHFText: String?
    /// Sehr kurze Fassung für das runde Widget, z. B. "+43".
    public var netCompactText: String?
    /// Summe aller Ausgaben, fertig formatiert – der Ersatzwert, solange nicht
    /// klar ist, wer am Gerät sitzt.
    public var totalText: String
    public var expenseCount: Int
    public var isClosed: Bool
    public var updatedAt: Date

    public init(tripName: String,
                standing: Standing,
                netText: String? = nil,
                netCHFText: String? = nil,
                netCompactText: String? = nil,
                totalText: String,
                expenseCount: Int,
                isClosed: Bool,
                updatedAt: Date = Date()) {
        self.tripName = tripName
        self.standing = standing
        self.netText = netText
        self.netCHFText = netCHFText
        self.netCompactText = netCompactText
        self.totalText = totalText
        self.expenseCount = expenseCount
        self.isClosed = isClosed
        self.updatedAt = updatedAt
    }

    /// Beispielwerte für die Widget-Galerie und die Vorschau in Xcode.
    public static let placeholder = KassaWidgetSnapshot(
        tripName: "Wucheändi Tessin",
        standing: .getsBack,
        netText: "+42.50 €",
        netCHFText: "+39.85 CHF",
        netCompactText: "+43",
        totalText: "312.00 €",
        expenseCount: 14,
        isClosed: false
    )
}

/// Texte des Widgets (Bärndütsch).
///
/// Die übrigen UI-Texte stehen in `Raepplispauter/Resources/Strings.swift`.
/// Jene Datei gehört nur dem App-Target; das Widget käme nicht an sie heran.
/// Das hier ist deshalb keine Kopie, sondern der eigene Satz Texte der
/// Erweiterung – gleich aufgebaut wie `L`.
public enum WidgetText {

    private static func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value)
    }

    public static let displayName = t("widget.displayName", "Kassä-Saldo")
    public static let description = t("widget.description",
                                      "Zeigt dr Saldo vo dyner aktuelle Kassä uf em Sperrbildschirm.")

    public static let noKassa = t("widget.noKassa", "No kei Kassä")
    public static let noKassaShort = t("widget.noKassaShort", "–")
    public static let getsBack = t("widget.getsBack", "Du überchunnsch")
    public static let owes = t("widget.owes", "Du muesch zahle")
    public static let balanced = t("widget.balanced", "Alles usglyche")
    public static let unknownPerson = t("widget.unknownPerson", "Wär bisch du?")
    public static let closedSuffix = t("widget.closed", "abgschlosse")
}
