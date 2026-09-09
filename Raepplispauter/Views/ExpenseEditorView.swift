import CoreData
import SwiftUI

/// Ausgabe erfassen und bearbeiten.
///
/// Funktioniert vollständig **offline**: gespeichert wird immer sofort lokal.
/// Der Wechselkurs kommt – wenn möglich – aus dem lokalen Kurs-Cache; fehlt er,
/// wird die Ausgabe als provisorisch markiert und später automatisch nachgerechnet.
///
/// Ist die Reise abgeschlossen, lässt sich hier nichts mehr ändern.
struct ExpenseEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @ObservedObject var trip: Trip
    let expense: Expense?

    @State private var amountText: String
    @State private var currencyCode: String
    @State private var categoryID: UUID?
    /// `nil` = mehrere haben bezahlt (dann gilt `paymentPercentages`).
    @State private var payerID: UUID?
    @State private var paymentPercentages: [Double]
    @State private var note: String
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showNewCategory = false
    @State private var knownCategoryIDs: Set<UUID>

    @FocusState private var amountFocused: Bool

    init(trip: Trip, expense: Expense?) {
        _trip = ObservedObject(wrappedValue: trip)
        self.expense = expense

        let participants = trip.participantList

        _amountText = State(initialValue: expense.map {
            $0.amountDecimal > 0 ? Money.formatPlain($0.amountDecimal) : ""
        } ?? "")
        _currencyCode = State(initialValue: expense?.currency ?? trip.currency)
        _categoryID = State(initialValue: expense?.category?.id ?? trip.categoryList.first?.id)
        _note = State(initialValue: expense?.note ?? "")
        _date = State(initialValue: expense?.date ?? Date())
        _knownCategoryIDs = State(initialValue: Set(trip.categoryList.compactMap(\.id)))

        if let expense {
            _payerID = State(initialValue: expense.payer?.id)
            if expense.isSplitPayment {
                let shares = expense.paymentPercentages
                _paymentPercentages = State(initialValue: participants.map {
                    guard let id = $0.id, let percent = shares[id] else { return 0 }
                    return NSDecimalNumber(decimal: percent).doubleValue
                })
            } else {
                _paymentPercentages = State(initialValue: SplitCalculator.equalShares(count: participants.count))
            }
        } else {
            // Neue Ausgabe: erste Person als Zahlerin vorschlagen.
            _payerID = State(initialValue: participants.first?.id)
            _paymentPercentages = State(initialValue: SplitCalculator.equalShares(count: participants.count))
        }
    }

    private var participants: [ParticipantSnapshot] { trip.participantSnapshots }

    private var parsedAmount: Decimal? {
        guard let value = Money.parse(amountText), value > 0 else { return nil }
        return value
    }

    /// Vorschau der Umrechnung – rein aus dem Cache, damit die Eingabe flüssig bleibt.
    private var previewConversion: CurrencyConversion? {
        guard let amount = parsedAmount else { return nil }
        return ExchangeRateService.shared.convertFromCache(amount: amount,
                                                           from: currencyCode,
                                                           tripCurrency: trip.currency,
                                                           on: date)
    }

    /// Reise abgeschlossen oder nur Leserechte am Share → nichts änderbar.
    private var canEdit: Bool {
        trip.isEditable && SharingController.shared.canEdit(trip)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !trip.isEditable {
                    Section {
                        Label(L.tripClosedBlocked, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }

                amountSection
                categorySection
                payerSection
                detailsSection
                conversionSection

                if expense != nil && canEdit {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(L.delete, systemImage: "trash")
                        }
                    }
                }
            }
            .disabled(!canEdit)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(expense == nil ? L.expenseNewTitle : L.expenseEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) {
                        Task { await save() }
                    }
                    .disabled(parsedAmount == nil || isSaving || !canEdit)
                }
            }
            .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                      set: { if !$0 { errorMessage = nil } })) {
                Button(L.ok, role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(L.expenseDeleteConfirm,
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible) {
                Button(L.delete, role: .destructive) { deleteExpense() }
                Button(L.cancel, role: .cancel) {}
            }
            .sheet(isPresented: $showNewCategory, onDismiss: selectNewestCategory) {
                CategoryDetailView(trip: trip, category: nil)
            }
            .onAppear { amountFocused = expense == nil && canEdit }
        }
    }

    // MARK: - Abschnitte

    private var amountSection: some View {
        Section {
            HStack {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .focused($amountFocused)

                Picker("", selection: $currencyCode) {
                    ForEach(Currencies.pickerOrder, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        } header: {
            Text(L.expenseAmount)
        } footer: {
            if currencyCode != trip.currency {
                Text(Currencies.displayName(currencyCode))
            }
        }
    }

    private var categorySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(trip.categoryList, id: \.objectID) { item in
                    categoryButton(item)
                }

                // Neue Kategorie direkt aus der Erfassung heraus anlegen.
                Button {
                    showNewCategory = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text(L.categoryNew)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.expenseCategory)
        }
    }

    @ViewBuilder
    private func categoryButton(_ item: ExpenseCategory) -> some View {
        let isSelected = categoryID == item.id
        let color = Theme.categoryColor(Int(item.colorIndex))

        Button {
            categoryID = item.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.caption)
                Text(item.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? color.opacity(0.24) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? color : .clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var payerSection: some View {
        Section {
            // Bis drei Personen als Segmente, darüber als Auswahlliste – sonst
            // werden die Segmente unlesbar schmal.
            if participants.count <= 3 {
                payerPicker.pickerStyle(.segmented)
            } else {
                payerPicker.pickerStyle(.menu)
            }

            if payerID == nil && participants.count > 1 {
                SplitEditorView(participants: participants,
                                percentages: $paymentPercentages,
                                amountText: { index in
                                    guard let amount = parsedAmount,
                                          paymentPercentages.indices.contains(index) else { return nil }
                                    let share = amount * Decimal(paymentPercentages[index]) / 100
                                    return Money.format(share, currencyCode: currencyCode)
                                })
                .padding(.vertical, 4)
            }
        } header: {
            Text(L.payerQuestion)
        } footer: {
            if payerID == nil {
                Text(L.expenseSplitHint)
            }
        }
    }

    private var payerPicker: some View {
        Picker(L.payerQuestion, selection: $payerID) {
            ForEach(participants) { participant in
                Text(participant.name).tag(UUID?.some(participant.id))
            }
            if participants.count > 1 {
                Text(L.payerShared).tag(UUID?.none)
            }
        }
    }

    private var detailsSection: some View {
        Section(L.expensePurpose) {
            TextField(L.expensePurposePlaceholder, text: $note, axis: .vertical)
                .lineLimit(1...3)

            DatePicker(L.expenseDateTime,
                       selection: $date,
                       displayedComponents: [.date, .hourAndMinute])
        }
    }

    @ViewBuilder
    private var conversionSection: some View {
        Section(L.expenseConversion) {
            if let conversion = previewConversion {
                LabeledValueRow(label: trip.currency) {
                    Text(Money.format(conversion.amountInTripCurrency, currencyCode: trip.currency))
                        .monospacedDigit()
                }
                LabeledValueRow(label: Currencies.home) {
                    Text(Money.format(conversion.amountInCHF, currencyCode: Currencies.home))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                LabeledValueRow(label: L.expenseRate) {
                    Text(Money.formatRate(conversion.rateToCHF))
                        .font(.caption)
                        .monospacedDigit()
                }
                LabeledValueRow(label: L.expenseRateDate) {
                    Text(Formatters.dateOnly.string(from: conversion.rateDate))
                        .font(.caption)
                }
                LabeledValueRow(label: L.expenseRateSourceLabel) {
                    Text(conversion.source.displayName)
                        .font(.caption)
                }
            } else if parsedAmount != nil {
                Label(L.expenseNoRate, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            } else {
                Text(L.expenseAmountInvalid)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Aktionen

    /// Nach dem Anlegen einer Kategorie soll diese gleich ausgewählt sein.
    private func selectNewestCategory() {
        let current = trip.categoryList
        if let created = current.first(where: { candidate in
            guard let candidateID = candidate.id else { return false }
            return !knownCategoryIDs.contains(candidateID)
        }) {
            categoryID = created.id
        }
        knownCategoryIDs = Set(current.compactMap(\.id))
    }

    private func save() async {
        guard canEdit else {
            errorMessage = L.tripClosedBlocked
            return
        }
        guard let amount = parsedAmount else {
            errorMessage = L.expenseAmountInvalid
            return
        }
        isSaving = true
        defer { isSaving = false }

        // Kurs holen (nutzt Cache, versucht bei Bedarf einmalig das Netz).
        let conversion = await ExchangeRateService.shared.convert(amount: amount,
                                                                  from: currencyCode,
                                                                  tripCurrency: trip.currency,
                                                                  on: date)

        let target = expense ?? Expense.create(in: context, trip: trip)
        target.category = categoryID.flatMap { id in trip.categoryList.first { $0.id == id } }
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.date = date
        target.applyConversion(conversion)

        // Zahler setzen: entweder eine Person, oder die Aufteilung über alle.
        let singlePayer = payerID.flatMap { id in trip.participant(with: id) }
        var shares: [UUID: Double] = [:]
        if singlePayer == nil {
            let normalised = SplitCalculator.normalise(paymentPercentages)
            for (index, participant) in trip.participantList.enumerated() {
                guard let id = participant.id, normalised.indices.contains(index) else { continue }
                shares[id] = normalised[index]
            }
        }
        target.setPayment(singlePayer: singlePayer, shares: shares, in: context)

        PersistenceController.shared.save()
        dismiss()
    }

    private func deleteExpense() {
        guard let expense, canEdit else { return }
        context.delete(expense)
        PersistenceController.shared.save()
        dismiss()
    }
}
