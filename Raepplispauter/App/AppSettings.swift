import Foundation
import UIKit

/// Geräteweite Einstellungen (bewusst **nicht** synchronisiert – sie sind lokal).
public enum AppSettings {

    private enum Key {
        static let rateMarkup = "rateMarkupPercent"
        static let lastRateRefresh = "lastRateRefresh"
        static let selectedTripID = "selectedTripID"
        static let deviceOwner = "deviceOwnerRole"
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

    /// Wer sitzt an diesem Gerät? Steuert nur Vorbelegungen (z. B. Zahler-Vorschlag)
    /// und die Beschriftung "du" – nicht die Berechnung.
    public static var deviceOwner: Person {
        get { Person(rawValue: defaults.string(forKey: Key.deviceOwner) ?? "") ?? .a }
        set { defaults.set(newValue.rawValue, forKey: Key.deviceOwner) }
    }

    /// Autor-Kennung für Core-Data-Transaktionen und das Konflikt-Protokoll.
    public static var transactionAuthor: String {
        UIDevice.current.name
    }
}
