import Foundation

/// Geräteweite Einstellungen (bewusst **nicht** synchronisiert – sie sind lokal).
///
/// Datenschutz: Hier landen ausschliesslich Bedienvorlieben, keine Personendaten
/// und keine Kennungen, die an Dritte gingen. Alles bleibt in `UserDefaults` auf
/// dem Gerät (siehe `PrivacyInfo.xcprivacy`).
public enum AppSettings {

    private enum Key {
        static let rateMarkup = "rateMarkupPercent"
        static let lastRateRefresh = "lastRateRefresh"
        static let selectedTripID = "selectedTripID"
        static let deviceLabel = "deviceLabel"
        /// Präfix für "wär bin ich" – je Reise ein eigener Eintrag.
        static let myParticipantPrefix = "myParticipant."
    }

    private static var defaults: UserDefaults { .standard }

    /// Aufschlag auf den EZB-Mittelkurs in Prozent, um einen Verkaufskurs
    /// nachzubilden (Standard 0 % = reiner Referenzkurs).
    public static var rateMarkupPercent: Decimal {
        get {
            guard let value = defaults.object(forKey: Key.rateMarkup) as? Double else { return 0 }
            return Decimal(value)
        }
        set {
            defaults.set(NSDecimalNumber(decimal: newValue).doubleValue, forKey: Key.rateMarkup)
        }
    }

    public static var lastRateRefresh: Date? {
        get { defaults.object(forKey: Key.lastRateRefresh) as? Date }
        set { defaults.set(newValue, forKey: Key.lastRateRefresh) }
    }

    /// Zuletzt gewählte Reise (UUID-String), damit die App sofort die richtige Bilanz zeigt.
    public static var selectedTripID: String? {
        get { defaults.string(forKey: Key.selectedTripID) }
        set { defaults.set(newValue, forKey: Key.selectedTripID) }
    }

    /// Frei wählbare Bezeichnung dieses Geräts. Sie erscheint im Sync-Protokoll,
    /// damit man Änderungen zuordnen kann ("Ändere vo Raphis iPhone").
    ///
    /// Bewusst **selbst gesetzt** statt aus `UIDevice.current.name` gelesen:
    /// Letzterer liefert seit iOS 16 ohnehin nur noch den Modellnamen, und ein
    /// frei gewählter Text ist datenschutzfreundlicher.
    public static var deviceLabel: String {
        get {
            let stored = (defaults.string(forKey: Key.deviceLabel) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored.isEmpty ? L.settingsDeviceLabelDefault : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.deviceLabel)
        }
    }

    /// Autor-Kennung für Core-Data-Transaktionen und das Sync-Protokoll.
    public static var transactionAuthor: String { deviceLabel }

    // MARK: - "Das bin ich"

    /// Welche Person der Reise sitzt an diesem Gerät?
    ///
    /// Bewusst **gerätelokal** und nicht im Datenmodell:
    /// * Die Antwort ist auf jedem Gerät eine andere – im geteilten Datensatz
    ///   hätte sie gar keinen eindeutigen Wert.
    /// * Es braucht dafür keine CloudKit-Schemaänderung; die Zuordnung lässt
    ///   sich also auch nach der Veröffentlichung noch weiterentwickeln.
    /// * Es wird keine iCloud-Kennung gespeichert, nur eine App-interne UUID.
    public static func myParticipantID(forTrip tripID: UUID) -> UUID? {
        guard let raw = defaults.string(forKey: Key.myParticipantPrefix + tripID.uuidString) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func setMyParticipantID(_ participantID: UUID?, forTrip tripID: UUID) {
        let key = Key.myParticipantPrefix + tripID.uuidString
        if let participantID {
            defaults.set(participantID.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
