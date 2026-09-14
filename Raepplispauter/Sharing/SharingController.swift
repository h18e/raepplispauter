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

    /// Letzter Fehler aus einem Vorgang, der **im Hintergrund** passiert ist –
    /// vor allem das Annehmen einer Einladung. Solche Fehler haben keine
    /// Oberfläche, in der sie erscheinen könnten; `RootView` zeigt sie deshalb
    /// als Hinweis an. Ohne das scheitert das Annehmen stumm.
    @Published public private(set) var lastError: String?

    public init() {}

    public func clearError() {
        lastError = nil
    }

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

    /// Wer darf über den Link beitreten? `.none` = nur namentlich Eingeladene.
    public func linkIsOpen(for trip: Trip) -> Bool {
        existingShare(for: trip)?.publicPermission == .readWrite
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

    /// Erzeugt einen Einladungs-Link, den **jede Person mit dem Link** nutzen kann.
    ///
    /// ## Warum das nötig ist
    ///
    /// Ein frisch erstellter `CKShare` steht auf `publicPermission = .none`.
    /// Das bedeutet: Herein kommt nur, wer vorher namentlich als Teilnehmer
    /// eingetragen wurde. Ein solcher Link ist technisch gültig, aber für
    /// niemanden freigeschaltet – beim Empfänger endet er mit
    ///
    ///   „Objekt nicht verfügbar. Die Person, der die Datei gehört, teilt diese
    ///    nicht mehr oder dein Account ist nicht berechtigt, sie zu öffnen."
    ///
    /// Für einen verschickbaren Link muss die Reichweite deshalb ausdrücklich
    /// auf `.readWrite` gesetzt **und** nach iCloud gespeichert werden. Das
    /// Setzen allein genügt nicht: Es verändert nur die lokale Kopie des
    /// Share-Datensatzes. `persistUpdatedShare(_:in:)` schreibt ihn zum Server
    /// und zieht die lokalen Metadaten nach.
    ///
    /// Nebenbei wird dabei auch der in `makeShare(for:)` gesetzte Titel
    /// gespeichert, der sonst nie beim Server ankäme.
    public func makeLinkShare(for trip: Trip) async throws -> URL {
        guard !isLocalOnly else { throw SharingError.localModeActive }
        guard isOwner(of: trip) else { throw SharingError.notOwner }
        guard let privateStore = persistence.privateStore else {
            throw SharingError.shareUnavailable
        }

        let (share, _) = try await makeShare(for: trip)
        share.publicPermission = .readWrite

        let updated: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.persistUpdatedShare(share, in: privateStore) { updatedShare, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let updatedShare {
                    continuation.resume(returning: updatedShare)
                } else {
                    continuation.resume(throwing: SharingError.shareUnavailable)
                }
            }
        }

        guard let url = updated.url else { throw SharingError.linkUnavailable }
        return url
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
        // Gleich zu Beginn protokollieren. Nur so lässt sich später
        // unterscheiden, ob die Einladung gar nie ankam oder ob sie ankam und
        // das Annehmen scheiterte – zwei Fehler mit demselben Symptom
        // ("die Kassä erscheint nicht"), aber ganz verschiedenen Ursachen.
        ConflictAuditor.shared.log(.init(date: Date(),
                                         author: AppSettings.transactionAuthor,
                                         kind: .info,
                                         detail: L.sharingAcceptReceived))

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
    /// Nur wer die Kassä angelegt hat, kann die Reichweite des Links ändern.
    case notOwner
    /// iCloud hat noch keinen Link geliefert (z. B. kein Netz beim Speichern).
    case linkUnavailable

    public var errorDescription: String? {
        switch self {
        case .shareUnavailable: return L.sharingCreateFailed
        case .localModeActive: return L.sharingLocalMode
        case .notOwner: return L.sharingOnlyOwner
        case .linkUnavailable: return L.sharingLinkFailed
        }
    }
}
