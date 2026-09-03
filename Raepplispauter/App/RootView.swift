import CoreData
import SwiftUI

/// Wurzel-Ansicht: entscheidet zwischen "no kei Reis" und der Haupt-Navigation.
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
                    EmptyStateView(symbol: "suitcase.rolling",
                                   title: L.balanceNoTrip,
                                   message: L.balanceNoTripHint,
                                   actionTitle: L.balanceCreateTrip) {
                        showTripEditor = true
                    }
                    .screenBackground()
                    .navigationTitle(L.appName)
                }
            }
        }
        .sheet(isPresented: $showTripEditor) {
            TripEditorView(trip: nil)
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
