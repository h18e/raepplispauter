import CloudKit
import CoreData
import Foundation

/// Steuert das CloudKit-Sharing einer Kassä zwischen **zwei getrennten iCloud-Accounts**.
///
/// ## Ablauf in drei Schritten
///
/// **1. Einladen (Gerät des Erstellers)**
/// `NSPersistentCloudKitContainer.share(_:to:)` verschiebt den `Trip` (samt aller
/// über `expenses` verknüpften Ausgaben) aus der Default-Zone in eine **eigene,
/// geteilte CloudKit-Zone** und legt dafür einen `CKShare` an. Der Share wird über
/// `UICloudSharingController` als iCloud-Einladung verschickt (Nachricht, Mail,
/// Link). Das passiert einmalig pro Kassä.
///
/// **2. Annehmen (Gerät des Partners)**
/// Tippt der Partner auf den Einladungslink, ruft iOS
/// `application(_:userDidAcceptCloudKitShareWith:)` auf. Dort wird
/// `acceptShareInvitations(from:into:)` mit dem **shared Store** aufgerufen.
/// Danach taucht die Kassä auf dem Partnergerät im shared Store auf – als wäre
/// sie lokal, inklusive Schreibrechten.
///
/// **3. Laufender Betrieb**
/// Beide Geräte schreiben in dieselbe geteilte Zone. Der Ersteller sieht sie im
/// privaten Store (Rolle "Owner"), der Partner im shared Store (Rolle
/// "Participant"). Neue Ausgaben landen automatisch in der Zone des jeweiligen
/// `Trip` – man muss nichts weiter tun.
///
/// ## Berechtigungen
/// Der Share wird mit `.readWrite` erstellt, damit beide erfassen und bearbeiten
/// können. `container.canUpdateRecord(forManagedObjectWith:)` prüft im Zweifel,
/// ob ein Objekt lokal bearbeitet werden darf.
@MainActor
public final class SharingController: ObservableObject {

    public static let shared = SharingController()

    private var persistence: PersistenceController { .shared }
    private var container: NSPersistentCloudKitContainer { persistence.container }

    @Published public private(set) var lastError: String?

    public init() {}

    // MARK: - Status

    /// Im Lokalmodus gibt es kein CloudKit – sämtliche Sharing-Funktionen sind aus.
    public var isLocalOnly: Bool { persistence.isLocalOnly }

    /// Bestehender Share einer Kassä, falls sie bereits geteilt wurde.
    public func existingShare(for trip: Trip) -> CKShare? {
        guard !isLocalOnly else { return nil }
        return try? container.fetchShares(matching: [trip.objectID])[trip.objectID]
    }

    public func isShared(_ trip: Trip) -> Bool {
        guard !isLocalOnly else { return false }
        return existingShare(for: trip) != nil || persistence.isInSharedStore(trip)
    }

    /// Bin ich Eigentümer der Kassä (habe ich sie erstellt) oder Teilnehmer?
    public func isOwner(of trip: Trip) -> Bool {
        !persistence.isInSharedStore(trip)
    }

    /// Darf dieses Gerät die Kassä bearbeiten? (Bei `.readOnly`-Shares nein.)
    public func canEdit(_ trip: Trip) -> Bool {
        guard !isLocalOnly else { return true }
        return container.canUpdateRecord(forManagedObjectWith: trip.objectID)
    }

    /// Einladungs-Link der Kassä.
    ///
    /// Erst verfügbar, **nachdem** der Share tatsächlich in iCloud gespeichert
    /// wurde (also nach dem ersten Durchlauf der Freigabe-Oberfläche). Vorher ist
    /// er `nil` – dann gibt es in der UI auch keinen Knopf zum Verschicken.
    public func shareURL(for trip: Trip) -> URL? {
        existingShare(for: trip)?.url
    }

    /// Anzeigenamen der Teilnehmer – für die Sharing-Karte in den Kassä-Einstellungen.
    public func participantNames(for trip: Trip) -> [String] {
        guard let share = existingShare(for: trip) else { return [] }
        return share.participants.compactMap { participant in
            let identity = participant.userIdentity
            if let components = identity.nameComponents {
                let formatter = PersonNameComponentsFormatter()
                let name = formatter.string(from: components)
                if !name.isEmpty { return name }
            }
            if let email = identity.lookupInfo?.emailAddress { return email }
            if let phone = identity.lookupInfo?.phoneNumber { return phone }
            return L.sharingUnknownParticipant
        }
    }

    /// Ist der iCloud-Account auf diesem Gerät überhaupt bereit?
    /// Im Lokalmodus wird gar nicht erst gefragt.
    public func accountStatus() async -> CKAccountStatus {
        guard !isLocalOnly else { return .couldNotDetermine }
        return (try? await CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus()) ?? .couldNotDetermine
    }

    // MARK: - Einladen

    /// Erstellt (oder holt) den `CKShare` einer Kassä.
    ///
    /// Wichtig: Vor dem Teilen müssen alle Änderungen gespeichert sein, sonst
    /// wandern noch nicht gesicherte Ausgaben nicht in die geteilte Zone.
    public func makeShare(for trip: Trip) async throws -> (share: CKShare, container: CKContainer) {
        guard !isLocalOnly else { throw SharingError.localModeActive }
        persistence.save()

        if let existing = existingShare(for: trip) {
            return (existing, CKContainer(identifier: PersistenceController.cloudKitContainerID))
        }

        // Den Titel vorher auslesen: `Trip` ist ein NSManagedObject und damit
        // nicht `Sendable` – in der Completion-Closure darf es deshalb nicht
        // verwendet werden. Der reine String ist unbedenklich.
        let shareTitle = trip.displayName

        return try await withCheckedThrowingContinuation { continuation in
            container.share([trip], to: nil) { _, share, ckContainer, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let share, let ckContainer else {
                    continuation.resume(throwing: SharingError.shareUnavailable)
                    return
                }
                // Titel der Einladung, wie er in Nachrichten/Mail erscheint.
                share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
                // `publicPermission` wird bewusst nicht erzwungen: In der
                // Freigabe-Oberfläche entscheidet die Person selbst zwischen
                // "nur iiglademi Lüt" und "jede, wo dr Link het". Für eine
                // Ferienabrechnung ist Letzteres oft das Praktischere.
                continuation.resume(returning: (share, ckContainer))
            }
        }
    }

    /// Merkt am Trip, dass er geteilt ist (für schnelle Offline-Anzeige).
    public func markShared(_ trip: Trip, isShared: Bool) {
        guard trip.isShared != isShared else { return }
        trip.isShared = isShared
        persistence.save()
    }

    // MARK: - Annehmen

    /// Nimmt eine eingehende iCloud-Einladung an und legt die Kassä im **shared Store** ab.
    public func accept(_ metadata: CKShare.Metadata) {
        guard !isLocalOnly else {
            lastError = L.sharingLocalMode
            return
        }
        guard let sharedStore = persistence.sharedStore else {
            lastError = L.sharingNoSharedStore
            return
        }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    ConflictAuditor.shared.log(.init(date: Date(),
                                                     author: AppSettings.transactionAuthor,
                                                     kind: .error,
                                                     detail: L.sharingAcceptFailed(error.localizedDescription)))
                } else {
                    ConflictAuditor.shared.log(.init(date: Date(),
                                                     author: AppSettings.transactionAuthor,
                                                     kind: .info,
                                                     detail: L.sharingAccepted))
                }
            }
        }
    }

    // MARK: - Beenden

    /// Hebt die Freigabe auf. Beim Eigentümer wird der Share gelöscht, beim
    /// Teilnehmer entfernt sich dieser selbst aus der Freigabe.
    public func stopSharing(_ trip: Trip) async {
        guard let share = existingShare(for: trip) else { return }
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let database = isOwner(of: trip) ? ckContainer.privateCloudDatabase : ckContainer.sharedCloudDatabase
        do {
            _ = try await database.deleteRecord(withID: share.recordID)
            markShared(trip, isShared: false)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

public enum SharingError: LocalizedError {
    case shareUnavailable
    /// Die App läuft im Lokalmodus – Teilen ist nicht möglich.
    case localModeActive

    public var errorDescription: String? {
        switch self {
        case .shareUnavailable: return L.sharingCreateFailed
        case .localModeActive: return L.sharingLocalMode
        }
    }
}
