import CloudKit
import CoreData
import SwiftUI

/// Reise anlegen bzw. bearbeiten – inklusive Personen, Kostenschlüssel und der
/// iCloud-Freigabe an die Mitreisenden.
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
    @State private var isClosed: Bool
    @State private var drafts: [ParticipantDraft]

    @State private var shareTarget: ShareTarget?
    @State private var shareLink: ShareLinkTarget?
    @State private var isPreparingShare = false
    @State private var errorMessage: String?
    /// Welche Person sitzt an diesem Gerät? (Draft-Kennung, siehe `identitySection`)
    @State private var myDraftID: UUID?

    init(trip: Trip?) {
        self.trip = trip
        _name = State(initialValue: trip?.name ?? "")
        _startDate = State(initialValue: trip?.startDate ?? Date())
        _endDate = State(initialValue: trip?.endDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _currencyCode = State(initialValue: trip?.currencyCode ?? "EUR")
        _isClosed = State(initialValue: trip?.isClosed ?? false)

        if let trip, !trip.participantList.isEmpty {
            _drafts = State(initialValue: trip.participantList.map(ParticipantDraft.init(participant:)))
            // Draft-Kennung entspricht bei bestehenden Personen der Participant-UUID.
            _myDraftID = State(initialValue: trip.id.flatMap { AppSettings.myParticipantID(forTrip: $0) })
        } else {
            // Neue Reise: eine leere Zeile als Startpunkt, weitere per "+".
            _drafts = State(initialValue: [ParticipantDraft(name: "", costSharePercent: 100)])
            _myDraftID = State(initialValue: nil)
        }
    }

    private struct ShareLinkTarget: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Bearbeitbare Person – funktioniert auch, solange die Reise noch gar nicht
    /// gespeichert ist.
    private struct ParticipantDraft: Identifiable {
        let id: UUID
        var name: String
        var costSharePercent: Double
        var colorIndex: Int
        /// Vorhandener Datensatz, falls die Person schon gespeichert ist.
        var existing: Participant?

        init(name: String, costSharePercent: Double, colorIndex: Int = 0) {
            self.id = UUID()
            self.name = name
            self.costSharePercent = costSharePercent
            self.colorIndex = colorIndex
            self.existing = nil
        }

        init(participant: Participant) {
            self.id = participant.id ?? UUID()
            self.name = participant.displayName
            self.costSharePercent = participant.costSharePercent
            self.colorIndex = Int(participant.colorIndex)
            self.existing = participant
        }
    }

    private struct ShareTarget: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let title: String
    }

    private var isNew: Bool { trip == nil }

    /// Bei abgeschlossener Reise bleiben die Inhalte gesperrt, damit die
    /// Abrechnung stabil bleibt. Nur der Status selbst ist umschaltbar.
    private var contentEditable: Bool { !isClosed }

    private var snapshots: [ParticipantSnapshot] {
        drafts.enumerated().map { index, draft in
            ParticipantSnapshot(id: draft.id,
                                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? L.participantPlaceholderNumbered(index + 1)
                                    : draft.name,
                                costSharePercent: Decimal(draft.costSharePercent),
                                colorIndex: draft.colorIndex,
                                sortIndex: index)
        }
    }

    private var percentages: Binding<[Double]> {
        Binding(
            get: { drafts.map(\.costSharePercent) },
            set: { values in
                for (index, value) in values.enumerated() where drafts.indices.contains(index) {
                    drafts[index].costSharePercent = value
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if isClosed {
                    Section {
                        Label(L.settlementClosedNotice, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }

                Section(L.tripName) {
                    TextField(L.tripNamePlaceholder, text: $name)
                        .disabled(!contentEditable)
                }

                Section(L.tripPeriod) {
                    DatePicker(L.tripStart, selection: $startDate, displayedComponents: .date)
                    DatePicker(L.tripEnd, selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                .disabled(!contentEditable)

                Section(L.tripCurrency) {
                    Picker(L.tripCurrency, selection: $currencyCode) {
                        ForEach(Currencies.pickerOrder, id: \.self) { code in
                            Text(Currencies.displayName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                .disabled(!contentEditable)

                participantsSection
                identitySection
                costShareSection

                if let trip, !isNew {
                    Section {
                        NavigationLink {
                            CategoryEditorView(trip: trip)
                        } label: {
                            LabeledContent {
                                Text("\(trip.categoryList.count)")
                                    .foregroundStyle(Theme.textSecondary)
                            } label: {
                                Label(L.categoriesTitle, systemImage: "tag")
                            }
                        }
                    } footer: {
                        Text(L.categoriesHint)
                    }
                }

                if !isNew {
                    sharingSection

                    Section {
                        Toggle(L.tripStatusClosed, isOn: $isClosed)
                    } footer: {
                        Text(L.tripClosedHint)
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
                        .disabled(!canSave)
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
            .sheet(item: $shareLink) { target in
                ActivityView(items: [target.url])
            }
            .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                      set: { if !$0 { errorMessage = nil } })) {
                Button(L.ok, role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && drafts.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Personen

    private var participantsSection: some View {
        Section {
            ForEach($drafts) { $draft in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.participantColor(draft.colorIndex))
                        .frame(width: 10, height: 10)
                    TextField(L.participantNamePlaceholder, text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .disabled(!contentEditable)
                }
            }
            .onDelete { offsets in
                guard contentEditable else { return }
                deleteParticipants(at: offsets)
            }

            if contentEditable {
                Button {
                    addParticipant()
                } label: {
                    Label(L.participantAdd, systemImage: "person.badge.plus")
                }
            }
        } header: {
            Text(L.tripPeople)
        } footer: {
            Text(L.tripPeopleHint)
        }
    }

    private func addParticipant() {
        withAnimation {
            var draft = ParticipantDraft(name: "", costSharePercent: 0)
            draft.colorIndex = drafts.count % Theme.participantPaletteSize
            drafts.append(draft)

            // Neue Person bekommt ihren gleichmässigen Anteil, die übrigen werden
            // proportional gestaucht – die Summe bleibt 100 %.
            let values = SplitCalculator.distributeAfterInsert(drafts.map(\.costSharePercent))
            for (index, value) in values.enumerated() where drafts.indices.contains(index) {
                drafts[index].costSharePercent = value
            }
        }
    }

    private func deleteParticipants(at offsets: IndexSet) {
        // Personen mit bereits erfassten Ausgaben dürfen nicht verschwinden,
        // sonst verlöre man die Zuordnung dieser Ausgaben.
        let blocked = offsets.compactMap { drafts.indices.contains($0) ? drafts[$0] : nil }
            .filter { $0.existing?.isUsed == true }

        guard blocked.isEmpty else {
            errorMessage = L.participantDeleteBlocked(blocked.map(\.name).joined(separator: ", "))
            return
        }

        guard drafts.count - offsets.count >= 1 else {
            errorMessage = L.participantNeedsOne
            return
        }

        withAnimation {
            drafts.remove(atOffsets: offsets)
            let values = SplitCalculator.normalise(drafts.map(\.costSharePercent))
            for (index, value) in values.enumerated() where drafts.indices.contains(index) {
                drafts[index].costSharePercent = value
            }
        }
    }

    // MARK: - "Das bin ich"

    /// Zuordnung, welche Person an diesem Gerät sitzt. Nur auf dem Gerät
    /// gespeichert – auf dem Gerät der Partnerin steht hier jemand anderes.
    @ViewBuilder
    private var identitySection: some View {
        if drafts.count > 1 {
            Section {
                Picker(L.identityQuestion, selection: $myDraftID) {
                    Text(L.identityNotSet).tag(UUID?.none)
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? L.participantPlaceholderNumbered(index + 1)
                             : draft.name)
                            .tag(UUID?.some(draft.id))
                    }
                }
            } header: {
                Text(L.identityTitle)
            } footer: {
                Text(L.identityHint)
            }
        }
    }

    // MARK: - Kostenschlüssel

    private var costShareSection: some View {
        Section {
            if drafts.count < 2 {
                Text(L.tripCostShareSingle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                SplitEditorView(participants: snapshots,
                                percentages: percentages,
                                isEnabled: contentEditable)
                    .padding(.vertical, 4)
            }
        } header: {
            Text(L.tripCostShare)
        } footer: {
            Text(L.tripCostShareHint)
        }
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

                // Einladungs-Link direkt weiterschicken (Nachrichten, WhatsApp,
                // Mail …). Steht erst zur Verfügung, sobald die Freigabe einmal
                // gespeichert wurde.
                if let url = controller.shareURL(for: trip) {
                    Button {
                        shareLink = ShareLinkTarget(url: url)
                    } label: {
                        Label(L.sharingSendLink, systemImage: "link")
                    }
                }

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

        // Leere Namenszeilen fallen lautlos weg – sie sind nur unfertige Eingaben.
        var effective = drafts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !effective.isEmpty else {
            errorMessage = L.participantNeedsOne
            return
        }

        // Kostenschlüssel nach dem Wegfallen leerer Zeilen erneut auf 100 % bringen.
        let normalised = SplitCalculator.normalise(effective.map(\.costSharePercent))
        for (index, value) in normalised.enumerated() where effective.indices.contains(index) {
            effective[index].costSharePercent = value
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
        target.isClosed = isClosed

        // Entfernte Personen löschen (nur unbenutzte kommen hier überhaupt an).
        let keptIDs = Set(effective.compactMap { $0.existing?.objectID })
        for participant in target.participantList where !keptIDs.contains(participant.objectID) {
            context.delete(participant)
        }

        // Bestehende aktualisieren, neue anlegen. Neue Personen übernehmen die
        // Kennung ihres Entwurfs – dadurch bleibt die Zuordnung "das bin ich"
        // auch bei einer frisch angelegten Reise gültig.
        for (index, draft) in effective.enumerated() {
            let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = draft.existing {
                existing.name = cleanName
                existing.costSharePercent = draft.costSharePercent
                existing.sortIndex = Int16(index)
                existing.colorIndex = Int16(draft.colorIndex % Theme.participantPaletteSize)
            } else {
                let created = Participant.create(in: context,
                                                 trip: target,
                                                 name: cleanName,
                                                 costSharePercent: draft.costSharePercent,
                                                 id: draft.id)
                created.sortIndex = Int16(index)
                created.colorIndex = Int16(draft.colorIndex % Theme.participantPaletteSize)
            }
        }

        PersistenceController.shared.save()

        // Zuordnung erst nach dem Speichern setzen – vorher hat eine neue Reise
        // noch keine Kennung. Eine gelöschte oder leer gebliebene Person wird
        // dabei automatisch verworfen.
        let chosenID = myDraftID.flatMap { id in effective.contains { $0.id == id } ? id : nil }
        appState.setMyParticipantID(chosenID, in: target)

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
