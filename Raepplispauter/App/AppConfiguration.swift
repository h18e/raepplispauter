import Foundation

/// Betriebsart der Datenhaltung.
public enum SyncMode: String {
    /// Volle Funktion: Core Data + CloudKit, Reisen lassen sich mit dem
    /// Partner-Account teilen. Braucht ein **kostenpflichtiges Apple Developer
    /// Program**, weil nur damit iCloud-Entitlements signiert werden können.
    case cloudKit

    /// Alles läuft rein lokal auf dem Gerät – kein iCloud, kein Teilen.
    /// Funktioniert mit einer **gratis Apple-ID**.
    case localOnly
}

/// Zentrale Bau-Einstellungen der App.
public enum AppConfiguration {

    // ═════════════════════════════════════════════════════════════════════
    //  ►►►  HIER UMSCHALTEN  ◄◄◄
    //
    //  .localOnly  – Gratis Apple-ID. App läuft nur auf diesem Gerät,
    //                kein iCloud-Sync, kein Teilen mit Gini.
    //
    //  .cloudKit   – Bezahltes Apple Developer Program. Voller Sync und
    //                Teilen zwischen zwei getrennten iCloud-Accounts.
    //
    //  WICHTIG: Beim Umschalten muss auch die Entitlements-Datei mitziehen!
    //  Xcode → Projekt „Raepplispauter“ → TARGETS → Raepplispauter →
    //  Build Settings → nach „Code Signing Entitlements“ suchen → Wert setzen:
    //
    //      .localOnly  →  Config/Raepplispauter-Local.entitlements
    //      .cloudKit   →  Config/Raepplispauter.entitlements
    //
    //  Ausführlich beschrieben im README, Abschnitt „Lokalmodus“.
    // ═════════════════════════════════════════════════════════════════════
    public static let syncMode: SyncMode = .localOnly

    /// Sicherheitsnetz: Auch wenn oben `.cloudKit` steht, die Entitlements aber
    /// fehlen (typisch bei einer gratis Apple-ID), startet die App nicht ab –
    /// `PersistenceController` fällt dann automatisch auf `.localOnly` zurück
    /// und vermerkt das im Sync-Protokoll.
    public static let allowsAutomaticLocalFallback = true
}
