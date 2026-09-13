import Foundation

/// Betriebsart der Datenhaltung.
public enum SyncMode: String {
    /// Volle Funktion: Core Data + CloudKit, Kassä lassen sich mit den
    /// Beteiligten teilen. Braucht ein **kostenpflichtiges Apple Developer
    /// Program**, weil nur damit iCloud-Entitlements signiert werden können.
    case cloudKit

    /// Alles läuft rein lokal auf dem Gerät – kein iCloud, kein Teilen.
    /// Funktioniert mit einer **gratis Apple-ID**.
    case localOnly
}

/// Zentrale Bau-Einstellungen der App.
public enum AppConfiguration {

    // ═════════════════════════════════════════════════════════════════════
    //  ►►►  BETRIEBSART  ◄◄◄
    //
    //  .cloudKit   – Bezahltes Apple Developer Program. Voller Sync und
    //                Teilen zwischen getrennten iCloud-Accounts.  ← aktiv
    //
    //  .localOnly  – Gratis Apple-ID. App läuft nur auf diesem Gerät,
    //                kein iCloud-Sync, kein Teilen.
    //
    //  WICHTIG: Beim Umschalten muss auch die Entitlements-Datei mitziehen!
    //  Xcode → Projekt „Raepplispauter“ → TARGETS → Raepplispauter →
    //  Build Settings → nach „Code Signing Entitlements“ suchen → Wert setzen:
    //
    //      .cloudKit   →  Config/Raepplispauter.entitlements
    //      .localOnly  →  Config/Raepplispauter-Local.entitlements
    //
    //  Ausführlich beschrieben im README, Abschnitt „Betriebsart“.
    // ═════════════════════════════════════════════════════════════════════
    public static let syncMode: SyncMode = .cloudKit

    /// Sicherheitsnetz: Auch wenn oben `.cloudKit` steht, die Entitlements aber
    /// fehlen (typisch bei einer gratis Apple-ID), startet die App nicht ab –
    /// `PersistenceController` fällt dann automatisch auf `.localOnly` zurück
    /// und vermerkt das im Sync-Protokoll.
    public static let allowsAutomaticLocalFallback = true

    // ═════════════════════════════════════════════════════════════════════
    //  ►►►  VOR DER ERSTEN APP-STORE-VERÖFFENTLICHUNG AUF `false` SETZEN  ◄◄◄
    //
    //  Solange die App noch nicht veröffentlicht ist, darf ein geändertes
    //  Datenmodell den lokalen Speicher einfach neu aufbauen – es sind reine
    //  Testdaten. Sobald echte Nutzerdaten im Spiel sind, wäre das
    //  Datenverlust: dann braucht es stattdessen eine Modellversion mit
    //  Lightweight Migration (Editor → Add Model Version in Xcode).
    // ═════════════════════════════════════════════════════════════════════
    public static let resetStoreOnIncompatibleModel = true
}
