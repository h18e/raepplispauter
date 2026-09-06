import Combine
import CoreData
import Foundation

/// Ein Eintrag im Sync-/Konflikt-Protokoll.
public struct SyncLogEntry: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable {
        case created
        case updated
        case deleted
        case info
        case error
    }

    public let id: UUID
    public let date: Date
    public let author: String
    public let kind: Kind
    public let detail: String

    public init(id: UUID = UUID(), date: Date, author: String, kind: Kind, detail: String) {
        self.id = id
        self.date = date
        self.author = author
        self.kind = kind
        self.detail = detail
    }

    public var symbolName: String {
        switch kind {
        case .created: return "plus.circle.fill"
        case .updated: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

/// Macht eingehende Fremdänderungen sichtbar.
///
/// **Warum es das gibt:** Die Merge-Policy `mergeByPropertyObjectTrump` löst
/// Konflikte automatisch – das ist praktisch, wäre aber "stilles Überschreiben".
/// Der Auditor liest deshalb die **Persistent History** aus und protokolliert
/// jede Änderung, die *nicht* von diesem Gerät stammt: Was wurde angelegt,
/// geändert (inkl. betroffener Felder) oder gelöscht, von wem und wann.
///
/// Das Protokoll ist bewusst **gerätelokal** (JSON-Datei) und wird nicht via
/// CloudKit synchronisiert – sonst würde jeder Protokolleintrag selbst wieder
/// eine Änderung auslösen (Endlosschleife).
public final class ConflictAuditor: ObservableObject {

    public static let shared = ConflictAuditor()

    @Published public private(set) var entries: [SyncLogEntry] = []

    private let maxEntries = 400
    private let fileURL: URL
    private let tokenKey = "conflictAuditorHistoryToken"
    private var observer: NSObjectProtocol?
    private weak var container: NSPersistentCloudKitContainer?
    private let queue = DispatchQueue(label: "ch.hebera.raepplispauter.auditor")

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true))
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("sync-log.json")
        }
        entries = loadEntries()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Beobachtung

    public func start(container: NSPersistentCloudKitContainer, syncMode: SyncMode) {
        self.container = container
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.processHistory()
        }
        log(.init(date: Date(),
                  author: AppSettings.transactionAuthor,
                  kind: .info,
                  detail: syncMode == .cloudKit ? L.syncLogStarted : L.syncLogStartedLocal))
    }

    /// Liest alle Transaktionen seit dem letzten Durchgang und protokolliert
    /// jene, die von einem anderen Gerät/Account stammen.
    public func processHistory() {
        guard let container else { return }
        let context = container.newBackgroundContext()
        context.name = "historyAudit"

        context.perform { [weak self] in
            guard let self else { return }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.currentToken())
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }

            var newEntries: [SyncLogEntry] = []
            let ownAuthor = AppSettings.transactionAuthor

            for transaction in transactions {
                let author = transaction.author ?? L.syncLogAuthorCloud
                // Eigene Änderungen dieses Geräts interessieren nicht.
                if author == ownAuthor { continue }

                for change in transaction.changes ?? [] {
                    guard let entry = self.makeEntry(for: change,
                                                     author: author,
                                                     timestamp: transaction.timestamp,
                                                     context: context) else { continue }
                    newEntries.append(entry)
                }
            }

            if let token = transactions.last?.token {
                self.storeToken(token)
            }

            guard !newEntries.isEmpty else { return }
            DispatchQueue.main.async {
                self.append(newEntries)
            }
        }
    }

    private func makeEntry(for change: NSPersistentHistoryChange,
                           author: String,
                           timestamp: Date,
                           context: NSManagedObjectContext) -> SyncLogEntry? {
        let entityName = change.changedObjectID.entity.name ?? ""
        guard entityName == "Expense" || entityName == "Trip" else { return nil }

        let subject = describe(objectID: change.changedObjectID, entityName: entityName, context: context)

        switch change.changeType {
        case .insert:
            return SyncLogEntry(date: timestamp, author: author, kind: .created,
                                detail: L.syncLogInserted(subject))
        case .update:
            let fields = (change.updatedProperties ?? [])
                .compactMap { Self.fieldLabel($0.name) }
                .sorted()
            return SyncLogEntry(date: timestamp, author: author, kind: .updated,
                                detail: fields.isEmpty
                                    ? L.syncLogUpdated(subject)
                                    : L.syncLogUpdatedFields(subject, fields.joined(separator: ", ")))
        case .delete:
            return SyncLogEntry(date: timestamp, author: author, kind: .deleted,
                                detail: L.syncLogDeleted(subject))
        @unknown default:
            return nil
        }
    }

    private func describe(objectID: NSManagedObjectID, entityName: String, context: NSManagedObjectContext) -> String {
        if let expense = try? context.existingObject(with: objectID) as? Expense {
            let amount = Money.format(expense.amountDecimal, currencyCode: expense.currency)
            return "\(expense.displayNote) (\(amount))"
        }
        if let trip = try? context.existingObject(with: objectID) as? Trip {
            return trip.displayName
        }
        return entityName == "Trip" ? L.tripUnnamed : L.expenseFallbackName
    }

    /// Übersetzt Core-Data-Feldnamen in verständliche Bezeichnungen.
    static func fieldLabel(_ name: String) -> String? {
        switch name {
        case "amount", "amountTrip", "amountCHF": return L.fieldAmount
        case "currencyCode": return L.fieldCurrency
        case "categoryRaw": return L.fieldCategory
        case "note": return L.fieldNote
        case "payerRaw": return L.fieldPayer
        case "splitPercentA": return L.fieldSplit
        case "date": return L.fieldDate
        case "rateToCHF", "rateTripToCHF", "rateDate", "rateSourceRaw", "isRateProvisional": return nil
        case "name": return L.fieldName
        case "startDate", "endDate": return L.fieldPeriod
        case "isClosed": return L.fieldStatus
        case "costSharePercentA": return L.fieldCostShare
        case "updatedAt", "lastEditedBy", "createdAt", "id", "isShared": return nil
        default: return nil
        }
    }

    // MARK: - Protokoll führen

    public func log(_ entry: SyncLogEntry) {
        DispatchQueue.main.async {
            self.append([entry])
        }
    }

    private func append(_ newEntries: [SyncLogEntry]) {
        entries.insert(contentsOf: newEntries.sorted { $0.date > $1.date }, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist(entries)
    }

    public func clear() {
        entries = []
        persist(entries)
    }

    private func loadEntries() -> [SyncLogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SyncLogEntry].self, from: data) else { return [] }
        return decoded
    }

    private func persist(_ entries: [SyncLogEntry]) {
        let snapshot = entries
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }

    // MARK: - History-Token

    private func currentToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    private func storeToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: tokenKey)
    }
}
