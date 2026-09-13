import CloudKit
import Combine
import CoreData
import SwiftUI

/// Gerätezustand über alle Ansichten hinweg: welche Kassä ist gewählt, wie steht
/// es um iCloud und die Wechselkurse.
@MainActor
public final class AppState: ObservableObject {

    /// Aktuell angezeigte Kassä (UUID). Wird in `AppSettings` gemerkt, damit die
    /// App beim Start sofort die richtige Bilanz zeigt.
    @Published public var selectedTripID: UUID? {
        didSet { AppSettings.selectedTripID = selectedTripID?.uuidString }
    }

    @Published public var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @Published public var isRefreshingRates = false
    @Published public var rateErrorMessage: String?
    @Published public var lastRateRefresh: Date? = AppSettings.lastRateRefresh

    public init() {
        if let stored = AppSettings.selectedTripID {
            selectedTripID = UUID(uuidString: stored)
        }
    }

    /// Wählt die anzuzeigende Kassä: die gemerkte, sonst die erste aktive, sonst irgendeine.
    public func resolveTrip(from trips: [Trip]) -> Trip? {
        if let selectedTripID, let match = trips.first(where: { $0.id == selectedTripID }) {
            return match
        }
        let fallback = trips.first(where: { !$0.isClosed }) ?? trips.first
        if let fallback, fallback.id != selectedTripID {
            // Auswahl nachziehen, ohne die View-Aktualisierung zu stören.
            DispatchQueue.main.async { self.selectedTripID = fallback.id }
        }
        return fallback
    }

    public func select(_ trip: Trip) {
        selectedTripID = trip.id
    }

    // MARK: - Start-Aufgaben

    /// Beim App-Start: iCloud-Status prüfen, Kurse aktualisieren, provisorische
    /// Ausgaben nachrechnen. Fehler sind unkritisch – die App bleibt offline nutzbar.
    public func performStartupTasks(context: NSManagedObjectContext) async {
        if !isLocalOnly {
            iCloudStatus = await SharingController.shared.accountStatus()
        }
        await refreshRates(context: context)
    }

    // MARK: - "Das bin ich"

    /// Wird bei jeder Änderung der Zuordnung erhöht, damit abhängige Ansichten
    /// neu zeichnen. Die Werte selbst liegen in `AppSettings` (gerätelokal).
    @Published public private(set) var identityRevision = 0

    /// Welche Person der Kassä sitzt an diesem Gerät? `nil` = noch nicht gewählt.
    public func myParticipantID(in trip: Trip) -> UUID? {
        guard let tripID = trip.id else { return nil }
        guard let stored = AppSettings.myParticipantID(forTrip: tripID) else { return nil }
        // Die Person könnte inzwischen gelöscht worden sein.
        return trip.participantList.contains { $0.id == stored } ? stored : nil
    }

    public func myParticipant(in trip: Trip) -> Participant? {
        guard let id = myParticipantID(in: trip) else { return nil }
        return trip.participant(with: id)
    }

    public func setMyParticipantID(_ participantID: UUID?, in trip: Trip) {
        guard let tripID = trip.id else { return }
        AppSettings.setMyParticipantID(participantID, forTrip: tripID)
        identityRevision += 1
    }

    /// Muss die Kassä noch fragen, wer hier sitzt?
    /// Bei nur einer Person erübrigt sich die Frage.
    public func needsIdentityChoice(in trip: Trip) -> Bool {
        trip.participantList.count > 1 && myParticipantID(in: trip) == nil
    }

    /// Läuft die App ohne iCloud? (Schalter in `AppConfiguration` oder Fallback.)
    public var isLocalOnly: Bool { PersistenceController.shared.isLocalOnly }

    /// true, wenn CloudKit gewünscht war, aber nicht verfügbar ist.
    public var didFallBackToLocal: Bool { PersistenceController.shared.didFallBackToLocal }

    public func refreshRates(context: NSManagedObjectContext) async {
        guard !isRefreshingRates else { return }
        isRefreshingRates = true
        defer { isRefreshingRates = false }

        do {
            _ = try await ExchangeRateService.shared.refreshRates()
            rateErrorMessage = nil
            lastRateRefresh = AppSettings.lastRateRefresh
        } catch {
            rateErrorMessage = error.localizedDescription
        }

        // Auch bei Kursfehler versuchen – vielleicht reicht der Cache.
        _ = await RateBackfillService.backfill(in: context)
    }

    public var iCloudStatusText: String {
        if isLocalOnly { return L.syncModeLocal }
        switch iCloudStatus {
        case .available: return L.settingsICloudOk
        case .noAccount: return L.settingsICloudMissing
        case .restricted: return L.settingsICloudRestricted
        default: return L.settingsICloudUnknown
        }
    }
}
