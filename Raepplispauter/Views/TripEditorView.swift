import CloudKit
import CoreData
import SwiftUI

/// Reise anlegen bzw. bearbeiten – inklusive der iCloud-Freigabe an den Partner.
struct TripEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    /// `nil` = neue Reise anlegen.
    let trip: Trip?

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var currencyCode: String
    @State private var personAName: String
    @State private var personBName: String
    @State private var costSharePercentA: Double
    @State private var isClosed: Bool

    @State private var shareTarget: ShareTarget?
    @State private var isPreparingShare = false
    @State private var errorMessage: String?

    init(trip: Trip?) {
        self.trip = trip
        _name = State(initialValue: trip?.name ?? "")
        _startDate = State(initialValue: trip?.startDate ?? Date())
        _endDate = State(initialValue: trip?.endDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _currencyCode = State(initialValue: trip?.currencyCode ?? "EUR")
        _personAName = State(initialValue: trip?.nameA ?? Person.defaultNameA)
        _personBName = State(initialValue: trip?.nameB ?? Person.defaultNameB)
        _costSharePercentA = State(initialValue: trip?.costSharePercentA ?? 50)
        _isClosed = State(initialValue: trip?.isClosed ?? false)
    }

    private struct ShareTarget: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let title: String
    }

    private var isNew: Bool { trip == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(L.tripName) {
                    TextField(L.tripNamePlaceholder, text: $name)
                }

                Section(L.tripPeriod) {
                    DatePicker(L.tripStart, selection: $startDate, displayedComponents: .date)
                    DatePicker(L.tripEnd, selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section(L.tripCurrency) {
                    Picker(L.tripCurrency, selection: $currencyCode) {
                        ForEach(Currencies.pickerOrder, id: \.self) { code in
                            Text(Currencies.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(L.tripPeople) {
                    LabeledContent(L.tripPersonA) {
                        TextField(Person.defaultNameA, text: $personAName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L.tripPersonB) {
                        TextField(Person.defaultNameB, text: $personBName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                costShareSection

                if !isNew {
                    sharingSection

                    Section {
                        Toggle(L.tripStatusClosed, isOn: $isClosed)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? L.tripNew : L.tripEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $shareTarget) { target in
                CloudSharingSheet(share: target.share,
                                  container: target.container,
                                  title: target.title,
                                  onSaved: {
                                      if let trip { SharingController.shared.markShared(trip, isShared: true) }
                                  },
                                  onStopped: {
                                      if let trip { SharingController.shared.markShared(trip, isShared: false) }
                                  },
                                  onFailed: { error in
                                      errorMessage = error.localizedDescription
                                  })
            }
            .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                      set: { if !$0 { errorMessage = nil } })) {
                Button(L.ok, role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Kostenschlüssel

    private var costShareSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(displayNameA) \(Int(costSharePercentA)) %")
                        .foregroundStyle(Theme.personColor(.a))
                    Spacer()
                    Text("\(displayNameB) \(Int(100 - costSharePercentA)) %")
                        .foregroundStyle(Theme.personColor(.b))
                }
                .font(.caption.weight(.semibold))
                .monospacedDigit()

                Slider(value: $costSharePercentA, in: 0...100, step: 5)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.tripCostShare)
        } footer: {
            Text(L.tripCostShareHint)
        }
    }

    private var displayNameA: String {
        personAName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Person.defaultNameA : personAName
    }

    private var displayNameB: String {
        personBName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Person.defaultNameB : personBName
    }

    // MARK: - Teile (CloudKit)

    @ViewBuilder
    private var sharingSection: some View {
        if let trip {
            if SharingController.shared.isLocalOnly {
                localModeSection
            } else {
                cloudSharingSection(for: trip)
            }
        }
    }

    /// Lokalmodus: Teilen ist konstruktiv nicht möglich. Statt eines toten
    /// Knopfes gibt es eine ehrliche Erklärung, wie man umschaltet.
    private var localModeSection: some View {
        Section {
            Label(L.syncModeLocal, systemImage: "iphone.slash")
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text(L.sharingSection)
        } footer: {
            Text(L.syncModeLocalHint)
        }
    }

    @ViewBuilder
    private func cloudSharingSection(for trip: Trip) -> some View {
        let controller = SharingController.shared
        let isShared = controller.isShared(trip)
        let isOwner = controller.isOwner(of: trip)

        Section {
            if isShared {
                let participants = controller.participantNames(for: trip)
                if !participants.isEmpty {
                    LabeledContent(L.sharingSharedWith) {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(participants, id: \.self) { participant in
                                Text(participant)
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    LabeledContent(L.sharingSection) { Text(L.sharingShared) }
                }
            } else {
                LabeledContent(L.sharingSection) { Text(L.sharingNotShared) }
            }

            if isOwner {
                Button {
                    Task { await prepareShare(for: trip) }
                } label: {
                    HStack {
                        Label(isShared ? L.sharingManage : L.sharingInvite,
                              systemImage: isShared ? "person.2.badge.gearshape" : "person.crop.circle.badge.plus")
                        if isPreparingShare {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparingShare)

                if isShared {
                    Button(role: .destructive) {
                        Task { await SharingController.shared.stopSharing(trip) }
                    } label: {
                        Label(L.sharingStop, systemImage: "person.2.slash")
                    }
                }
            } else {
                Label(L.sharingParticipant, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text(L.sharingSection)
        } footer: {
            Text(isOwner ? L.sharingHint : L.sharingOnlyOwner)
        }
    }

    /// Erzeugt (oder lädt) den `CKShare` und öffnet die iCloud-Freigabeoberfläche.
    private func prepareShare(for trip: Trip) async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let result = try await SharingController.shared.makeShare(for: trip)
            shareTarget = ShareTarget(share: result.share,
                                      container: result.container,
                                      title: trip.displayName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Speichern

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = L.tripNoName
            return
        }

        let target: Trip
        if let trip {
            target = trip
        } else {
            target = Trip.create(in: context,
                                 name: trimmedName,
                                 startDate: startDate,
                                 endDate: endDate,
                                 currencyCode: currencyCode,
                                 assignTo: PersistenceController.shared.privateStore)
        }

        target.name = trimmedName
        target.startDate = startDate
        target.endDate = endDate
        target.currencyCode = currencyCode
        target.personAName = displayNameA
        target.personBName = displayNameB
        target.costSharePercentA = costSharePercentA
        target.isClosed = isClosed

        PersistenceController.shared.save()

        if isNew {
            appState.select(target)
        }
        dismiss()
    }
}

#Preview {
    TripEditorView(trip: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
