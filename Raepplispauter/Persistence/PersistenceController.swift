import CoreData
import CloudKit
import Foundation

/// Persistenz- und Sync-Schicht.
///
/// ## Warum zwei Stores?
/// Beim CloudKit-*Sharing* liegen die Daten in zwei verschiedenen Datenbanken:
///
/// * **Private Database** – alles, was *dieses* Gerät selber angelegt hat
///   (bei uns: Reisen, die man selber erstellt und dann einlädt)
/// * **Shared Database** – alles, was ein *anderer* iCloud-Account mit einem geteilt hat
///   (bei uns: die Reise, die der Partner erstellt und eingeladen hat)
///
/// `NSPersistentCloudKitContainer` bildet das mit **zwei SQLite-Stores** ab, die
/// dasselbe Modell verwenden. Genau deshalb funktioniert das Szenario "zwei
/// getrennte Apple-Accounts, ein gemeinsamer Datensatz" – ein gemeinsamer
/// Family-Container wäre nicht nötig und ist auch nicht vorgesehen.
///
/// ## Offline-First
/// Core Data ist die Wahrheit auf dem Gerät. Jede Eingabe landet sofort lokal und
/// ist ohne Netz vollständig nutzbar. `NSPersistentCloudKitContainer` schiebt die
/// Änderungen im Hintergrund hoch, sobald wieder eine Verbindung besteht.
///
/// ## Lokalmodus
/// Steht `AppConfiguration.syncMode` auf `.localOnly` (oder ist CloudKit mangels
/// Entitlement gar nicht verfügbar), wird **nur der private Store ohne
/// CloudKit-Optionen** geladen. Die App ist dann voll benutzbar – Erfassen,
/// Bilanz, Logbuch, Auswertung, Abrechnung, CSV-Export – nur Sync und Teilen
/// fallen weg. Der Dateipfad bleibt derselbe, ein späterer Wechsel auf CloudKit
/// übernimmt die bereits erfassten Daten.
///
/// ## Konflikte
/// * `mergeByPropertyObjectTrump` löst Konflikte **feldweise** – zwei Personen, die
///   offline verschiedene Ausgaben erfassen, kommen beide durch; nur bei
///   *derselben Ausgabe im selben Feld* gewinnt die zuletzt eingetroffene Änderung.
/// * Damit nichts *still* überschrieben wird, protokolliert `ConflictAuditor`
///   alle eingehenden Fremdänderungen (Persistent History) und zeigt sie im
///   Sync-Protokoll an. Zusätzlich trägt jede Ausgabe `updatedAt` und
///   `lastEditedBy`.
public final class PersistenceController {

    public static let shared = PersistenceController()

    /// CloudKit-Container-ID – muss mit dem Eintrag in `Raepplispauter.entitlements`
    /// und dem Container im Apple-Developer-Portal übereinstimmen.
    public static let cloudKitContainerID = "iCloud.ch.hebera.raepplispauter"

    public let container: NSPersistentCloudKitContainer

    /// Tatsächlich verwendete Betriebsart. Kann von `AppConfiguration.syncMode`
    /// abweichen, wenn CloudKit nicht verfügbar war (siehe Fallback unten).
    public let syncMode: SyncMode

    /// true, wenn `.cloudKit` gewünscht war, aber auf `.localOnly` zurückgefallen wurde.
    public let didFallBackToLocal: Bool

    /// Store für selbst angelegte Reisen (private CloudKit-Datenbank).
    public private(set) var privateStore: NSPersistentStore?
    /// Store für Reisen, die der Partner-Account geteilt hat (shared CloudKit-Datenbank).
    /// Im Lokalmodus immer `nil`.
    public private(set) var sharedStore: NSPersistentStore?

    public private(set) var loadError: Error?

    public var viewContext: NSManagedObjectContext { container.viewContext }

    /// Kurzform für die vielen Stellen, die nur wissen müssen "läuft ohne iCloud?".
    public var isLocalOnly: Bool { syncMode == .localOnly }

    private let conflictAuditor = ConflictAuditor.shared

    // MARK: - Aufbau

    public init(inMemory: Bool = false, syncMode requestedMode: SyncMode = AppConfiguration.syncMode) {
        // Tests und Previews laufen grundsätzlich lokal.
        let wanted: SyncMode = inMemory ? .localOnly : requestedMode

        var result = Self.loadContainer(mode: wanted, inMemory: inMemory)
        var fellBack = false

        // Sicherheitsnetz: CloudKit gewünscht, aber nicht verfügbar (fehlendes
        // Entitlement bei gratis Apple-ID, kein iCloud-Account, kein Container).
        // Statt die App scheitern zu lassen, wird lokal weitergemacht.
        if result.error != nil, wanted == .cloudKit, AppConfiguration.allowsAutomaticLocalFallback {
            result = Self.loadContainer(mode: .localOnly, inMemory: inMemory)
            fellBack = true
        }

        container = result.container
        syncMode = result.mode
        didFallBackToLocal = fellBack
        loadError = result.error

        // Stores zuordnen. Im Lokalmodus gibt es nur den privaten Store.
        let coordinator = container.persistentStoreCoordinator
        if inMemory {
            privateStore = coordinator.persistentStores.first
        } else if let storesURL = container.persistentStoreDescriptions.first?.url?.deletingLastPathComponent() {
            privateStore = coordinator.persistentStore(for: storesURL.appendingPathComponent(Self.privateStoreName))
            if result.mode == .cloudKit {
                sharedStore = coordinator.persistentStore(for: storesURL.appendingPathComponent(Self.sharedStoreName))
            }
        }

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = AppSettings.transactionAuthor
        context.name = "viewContext"
        try? context.setQueryGenerationFrom(.current)

        if !inMemory {
            conflictAuditor.start(container: container, syncMode: syncMode)
            if fellBack {
                conflictAuditor.log(.init(date: Date(),
                                          author: AppSettings.transactionAuthor,
                                          kind: .error,
                                          detail: L.syncLogCloudUnavailable))
            }
        }
    }

    // MARK: - Container bauen

    static let privateStoreName = "private.sqlite"
    static let sharedStoreName = "shared.sqlite"

    private struct LoadResult {
        let container: NSPersistentCloudKitContainer
        let mode: SyncMode
        let error: Error?
    }

    /// Baut einen Container für die gewünschte Betriebsart und lädt seine Stores.
    ///
    /// Der Datei-Pfad ist in beiden Modi derselbe (`private.sqlite`) – wer später
    /// vom Lokalmodus auf CloudKit umstellt, behält damit seine erfassten Daten.
    private static func loadContainer(mode: SyncMode, inMemory: Bool) -> LoadResult {
        let container = NSPersistentCloudKitContainer(name: "Raepplispauter")

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("Keine Store-Beschreibung vorhanden – Modell nicht gefunden.")
        }

        if inMemory {
            // Für Tests und SwiftUI-Previews: kein CloudKit, keine Datei.
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDescription]
        } else {
            let storesURL = privateDescription.url!.deletingLastPathComponent()
            privateDescription.url = storesURL.appendingPathComponent(privateStoreName)

            // Persistent History: für CloudKit Pflicht, lokal die Grundlage des
            // Änderungsprotokolls. Wird in beiden Modi eingeschaltet, damit ein
            // späterer Wechsel keine Store-Migration braucht.
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            switch mode {
            case .localOnly:
                // Ohne CloudKit-Optionen verhält sich der Container wie ein
                // gewöhnlicher NSPersistentContainer – rein lokal.
                privateDescription.cloudKitContainerOptions = nil
                container.persistentStoreDescriptions = [privateDescription]

            case .cloudKit:
                let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
                privateOptions.databaseScope = .private
                privateDescription.cloudKitContainerOptions = privateOptions

                // Zweiter Store für geteilte Daten – identisches Modell, andere Datenbank.
                guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription else {
                    fatalError("Store-Beschreibung konnte nicht kopiert werden.")
                }
                sharedDescription.url = storesURL.appendingPathComponent(sharedStoreName)
                let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
                sharedOptions.databaseScope = .shared
                sharedDescription.cloudKitContainerOptions = sharedOptions

                container.persistentStoreDescriptions = [privateDescription, sharedDescription]
            }
        }

        var failure: Error?
        container.loadPersistentStores { _, error in
            if let error, failure == nil { failure = error }
        }

        // Bei einem Fehlschlag alle bereits geöffneten Stores wieder schliessen,
        // damit der Fallback-Container dieselbe Datei sauber öffnen kann.
        if failure != nil {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }

        return LoadResult(container: container, mode: mode, error: failure)
    }

    /// Vorschau-/Testcontainer mit Beispieldaten.
    public static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let trip = Trip.create(in: context,
                               name: "Toskana",
                               startDate: Date().addingTimeInterval(-6 * 86_400),
                               endDate: Date().addingTimeInterval(4 * 86_400),
                               currencyCode: "EUR")
        let samples: [(Decimal, ExpenseCategory, Payer, String)] = [
            (120, .unterkunft, .a, "Agriturismo"),
            (48.5, .restaurant, .b, "Znacht Trattoria"),
            (23.9, .lebensmittel, .shared, "Märit"),
            (14, .oev, .a, "Zug Florenz"),
            (62, .auto, .b, "Tanke"),
            (36, .sightseeing, .a, "Uffizien")
        ]
        for (index, sample) in samples.enumerated() {
            let expense = Expense.create(in: context, trip: trip)
            expense.date = Date().addingTimeInterval(Double(-index) * 43_200)
            expense.category = sample.1
            expense.payer = sample.2
            expense.note = sample.3
            expense.applyConversion(CurrencyConversion(originalAmount: sample.0,
                                                       originalCurrency: "EUR",
                                                       tripCurrency: "EUR",
                                                       amountInTripCurrency: sample.0,
                                                       amountInCHF: Money.roundToFiveRappen(sample.0 * Decimal(string: "0.94")!),
                                                       rateToCHF: Decimal(string: "0.94")!,
                                                       rateTripToCHF: Decimal(string: "0.94")!,
                                                       rateDate: expense.date ?? Date(),
                                                       source: .ecbCached,
                                                       isProvisional: false))
        }
        try? context.save()
        return controller
    }()

    // MARK: - Speichern

    /// Speichert und setzt dabei die Nachvollziehbarkeits-Felder.
    public func save(author: String = AppSettings.transactionAuthor) {
        let context = viewContext
        guard context.hasChanges else { return }
        for object in context.insertedObjects.union(context.updatedObjects) {
            if let expense = object as? Expense {
                expense.updatedAt = Date()
                expense.lastEditedBy = author
            } else if let trip = object as? Trip {
                trip.updatedAt = Date()
            }
        }
        do {
            try context.save()
        } catch {
            // Bewusst kein fatalError: ein fehlgeschlagener Speichervorgang darf die
            // App nicht beenden. Der Fehler wird protokolliert und im Sync-Log sichtbar.
            ConflictAuditor.shared.log(.init(date: Date(),
                                             author: author,
                                             kind: .error,
                                             detail: L.syncLogSaveFailed(error.localizedDescription)))
            context.rollback()
        }
    }

    /// In welchem Store liegt dieses Objekt? (privat = selber erstellt, shared = eingeladen)
    public func isInSharedStore(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore === sharedStore
    }
}
