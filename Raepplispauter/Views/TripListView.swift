import CoreData
import SwiftUI

/// Übersicht über alle Kassä – aktive und abgeschlossene – inklusive Auswahl,
/// Anlegen, Bearbeiten und Löschen.
struct TripListView: View {

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
                  animation: .default)
    private var trips: FetchedResults<Trip>

    @State private var editTarget: EditTarget?
    @State private var showNewTrip = false
    @State private var deleteCandidate: EditTarget?

    private struct EditTarget: Identifiable {
        let id: NSManagedObjectID
        let trip: Trip
    }

    private var activeTrips: [Trip] { trips.filter { !$0.isClosed } }
    private var closedTrips: [Trip] { trips.filter { $0.isClosed } }

    var body: some View {
        Group {
            if trips.isEmpty {
                EmptyStateView(symbol: "suitcase.rolling",
                               title: L.tripsEmpty,
                               message: L.balanceNoTripHint,
                               actionTitle: L.tripNew) { showNewTrip = true }
            } else {
                List {
                    if !activeTrips.isEmpty {
                        Section(L.tripsActive) {
                            ForEach(activeTrips, id: \.objectID) { trip in
                                row(for: trip)
                            }
                        }
                    }
                    if !closedTrips.isEmpty {
                        Section(L.tripsClosed) {
                            ForEach(closedTrips, id: \.objectID) { trip in
                                row(for: trip)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .screenBackground()
        .navigationTitle(L.tripsTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(L.settingsTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewTrip = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(L.tripNew)
            }
        }
        .sheet(isPresented: $showNewTrip) {
            TripEditorView(trip: nil)
        }
        .sheet(item: $editTarget) { target in
            TripEditorView(trip: target.trip)
        }
        .confirmationDialog(L.tripDeleteConfirm,
                            isPresented: Binding(get: { deleteCandidate != nil },
                                                 set: { if !$0 { deleteCandidate = nil } }),
                            titleVisibility: .visible) {
            Button(L.delete, role: .destructive) {
                if let trip = deleteCandidate?.trip {
                    delete(trip)
                }
                deleteCandidate = nil
            }
            Button(L.cancel, role: .cancel) { deleteCandidate = nil }
        }
    }

    @ViewBuilder
    private func row(for trip: Trip) -> some View {
        let isSelected = appState.selectedTripID == trip.id

        Button {
            appState.select(trip)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(CSVExporter.formatDateRange(trip.startDate, trip.endDate))
                        Text("·")
                        Text(trip.currency)
                        Text("·")
                        Text(L.tripParticipantCount(trip.participantList.count))
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if trip.isShared || SharingController.shared.isShared(trip) {
                        BadgeView(text: L.sharingShared, color: Theme.accent, systemImage: "person.2.fill")
                    }
                    if trip.isClosed {
                        BadgeView(text: L.tripStatusClosed, color: Theme.textSecondary, systemImage: "lock.fill")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteCandidate = EditTarget(id: trip.objectID, trip: trip)
            } label: {
                Label(L.delete, systemImage: "trash")
            }
            Button {
                editTarget = EditTarget(id: trip.objectID, trip: trip)
            } label: {
                Label(L.edit, systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
    }

    private func delete(_ trip: Trip) {
        if appState.selectedTripID == trip.id {
            appState.selectedTripID = nil
        }
        context.delete(trip)
        PersistenceController.shared.save()
    }
}

#Preview {
    NavigationStack {
        TripListView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
