import CoreData
import SwiftUI

/// Wurzel-Ansicht: entscheidet zwischen Startbildschirm und Haupt-Navigation.
struct RootView: View {

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
                  animation: .default)
    private var trips: FetchedResults<Trip>

    @State private var showTripEditor = false

    var body: some View {
        Group {
            if let trip = appState.resolveTrip(from: Array(trips)) {
                MainTabView(trip: trip)
            } else {
                NavigationStack {
                    WelcomeView { showTripEditor = true }
                        .navigationTitle(L.appName)
                }
            }
        }
        .sheet(isPresented: $showTripEditor) {
            TripEditorView(trip: nil)
        }
    }
}

/// Startbildschirm, solange noch nichts erfasst ist.
///
/// Statt eines einzelnen grossen Symbols liegt hier ein Wasserzeichen aus
/// vielen kleinen Ausgaben-Symbolen über die ganze Fläche – das zeigt auf einen
/// Blick, worum es in der App geht, ohne aufdringlich zu sein.
struct WelcomeView: View {

    let action: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ExpenseWatermarkBackground().ignoresSafeArea()

            VStack(spacing: 14) {
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
