import CloudKit
import Combine
import CoreData
import SwiftUI

/// Gerätezustand über alle Ansichten hinweg: welche Reise ist gewählt, wie steht
/// es um iCloud und die Wechselkurse.
@MainActor
public final class AppState: ObservableObject {

    /// Aktuell angezeigte Reise (UUID). Wird in `AppSettings` gemerkt, damit die
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

    /// Wählt die anzuzeigende Reise: die gemerkte, sonst die erste aktive, sonst irgendeine.
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
