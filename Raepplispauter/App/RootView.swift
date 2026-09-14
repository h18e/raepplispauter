import Combine
import CoreData
import SwiftUI

/// Wurzel-Ansicht: entscheidet zwischen Startbildschirm und Haupt-Navigation.
struct RootView: View {

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sharing: SharingController

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
                  animation: .default)
    private var trips: FetchedResults<Trip>

    @State private var showTripEditor = false

    var body: some View {
        Group {
            if let trip = appState.resolveTrip(from: Array(trips)) {
                MainTabView(trip: trip)
            } else {
                WelcomeView { showTripEditor = true }
            }
        }
        .sheet(isPresented: $showTripEditor) {
            TripEditorView(trip: nil)
        }
        // Fehler beim Annehmen einer Einladung passieren im Hintergrund – sie
        // haben sonst keine Oberfläche, in der sie auftauchen könnten. Ohne
        // diesen Hinweis scheitert das Annehmen stumm und man sucht den Fehler
        // an der falschen Stelle.
        .alert(L.errorTitle,
               isPresented: Binding(get: { sharing.lastError != nil },
                                    set: { if !$0 { sharing.clearError() } })) {
            Button(L.ok, role: .cancel) { sharing.clearError() }
        } message: {
            Text(sharing.lastError ?? "")
        }
        // Das Sperrbildschirm-Widget liest eine Momentaufnahme, die hier
        // nachgeführt wird. Vier Anlässe, bei denen sie veralten könnte:
        .onAppear { refreshWidget() }
        .onChange(of: appState.selectedTripID) { refreshWidget() }
        .onChange(of: appState.identityRevision) { refreshWidget() }
        // Jede gespeicherte Änderung – auch die vom Gerät der anderen Person,
        // die über CloudKit hereinkommt.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            refreshWidget()
        }
    }

    /// Rechnet die Kassä durch und legt das Ergebnis für das Widget ab.
    ///
    /// Der Sprung über `Task { @MainActor in … }` ist nötig, weil diese Methode
    /// auch aus der Speicher-Benachrichtigung heraus aufgerufen wird – die kann
    /// von einer Hintergrund-Queue kommen (CloudKit-Import), während der
    /// View-Kontext und `AppState` an den Haupt-Thread gebunden sind. Dasselbe
    /// Muster verwendet der AppDelegate beim Annehmen einer Freigabe.
    private func refreshWidget() {
        Task { @MainActor in
            let trip = appState.resolveTrip(from: Array(trips))
            WidgetSnapshotWriter.refresh(for: trip,
                                         myParticipantID: trip.flatMap { appState.myParticipantID(in: $0) },
                                         in: context)
        }
    }
}

/// Startbildschirm, solange noch nichts erfasst ist.
///
/// Statt eines einzelnen grossen Symbols liegt hier ein Wasserzeichen aus
/// vielen kleinen Ausgaben-Symbolen über die ganze Fläche – das zeigt auf einen
/// Blick, worum es in der App geht, ohne aufdringlich zu sein.
///
/// App-Name und Untertitel stehen bewusst **im Inhalt** und nicht als
/// `navigationTitle`: Ein Navigationstitel trägt keinen Untertitel, und ein
/// zweites Mal derselbe Name in der Leiste wäre nur Dopplung. Ohne
/// Navigationsleiste steht der Block ausserdem frei in der Mitte.
struct WelcomeView: View {

    let action: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ExpenseWatermarkBackground().ignoresSafeArea()

            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(L.appName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(L.appTagline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

                Text(L.balanceNoTrip)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L.balanceNoTripHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button(L.balanceCreateTrip, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 6)
            }
            .padding(28)
            // Dezenter Verlauf hinter dem Text, damit er sich auch dort klar
            // abhebt, wo zufällig mehrere Symbole zusammenfallen.
            .background(
                RadialGradient(colors: [Theme.background, Theme.background.opacity(0)],
                               center: .center,
                               startRadius: 40,
                               endRadius: 260)
            )
        }
    }
}

/// Haupt-Navigation mit den fünf Bereichen der App.
struct MainTabView: View {

    @ObservedObject var trip: Trip

    var body: some View {
        TabView {
            NavigationStack { BalanceView(trip: trip) }
                .tabItem { Label(L.tabBalance, systemImage: "scalemass") }

            NavigationStack { LogbookView(trip: trip) }
                .tabItem { Label(L.tabLogbook, systemImage: "list.bullet.rectangle") }

            NavigationStack { AnalysisView(trip: trip) }
                .tabItem { Label(L.tabAnalysis, systemImage: "chart.pie") }

            NavigationStack { SettlementView(trip: trip) }
                .tabItem { Label(L.tabSettlement, systemImage: "checkmark.seal") }

            NavigationStack { TripListView() }
                .tabItem { Label(L.tabTrips, systemImage: "suitcase") }
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(AppState())
        .environmentObject(SharingController.shared)
        .environmentObject(ConflictAuditor.shared)
        .preferredColorScheme(.dark)
}
