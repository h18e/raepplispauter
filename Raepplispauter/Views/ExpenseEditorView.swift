import CoreData
import SwiftUI

/// Ausgabe erfassen und bearbeiten.
///
/// Funktioniert vollständig **offline**: gespeichert wird immer sofort lokal.
/// Der Wechselkurs kommt – wenn möglich – aus dem lokalen Kurs-Cache; fehlt er,
/// wird die Ausgabe als provisorisch markiert und später automatisch nachgerechnet.
struct ExpenseEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    let trip: Trip
    let expense: Expense?

    @State private var amountText: String
    @State private var currencyCode: String
    @State private var category: ExpenseCategory
    @State private var payer: Payer
    @State private var splitPercentA: Double
    @State private var note: String
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    @FocusState private var amountFocused: Bool

    init(trip: Trip, expense: Expense?) {
        self.trip = trip
        self.expense = expense

        _amountText = State(initialValue: expense.map {
            $0.amountDecimal > 0 ? Money.formatPlain($0.amountDecimal) : ""
        } ?? "")
        _currencyCode = State(initialValue: expense?.currency ?? trip.currency)
        _category = State(initialValue: expense?.category ?? .restaurant)
        _payer = State(initialValue: expense?.payer ?? .a)
        _splitPercentA = State(initialValue: expense?.splitPercentA ?? 50)
        _note = State(initialValue: expense?.note ?? "")
        _date = State(initialValue: expense?.date ?? Date())
    }

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

    private var canEdit: Bool {
        expense == nil || SharingController.shared.canEdit(trip)
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                categorySection
                payerSection
                detailsSection
                conversionSection

                if expense != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(L.delete, systemImage: "trash")
                        }
                    }
                }
            }
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
            .onAppear { amountFocused = expense == nil }
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
        Section(L.expenseCategory) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ExpenseCategory.ordered) { item in
                    Button {
                        category = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbolName)
                                .font(.caption)
                            Text(item.displayName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(category == item
                                      ? Theme.categoryColor(item).opacity(0.24)
                                      : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(category == item ? Theme.categoryColor(item) : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(category == item ? Theme.categoryColor(item) : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var payerSection: some View {
        Section {
            Picker(L.payerQuestion, selection: $payer) {
                Text(trip.nameA).tag(Payer.a)
                Text(trip.nameB).tag(Payer.b)
                Text(L.payerShared).tag(Payer.shared)
            }
            .pickerStyle(.segmented)

            if payer == .shared {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(trip.nameA) \(Int(splitPercentA)) %")
                            .foregroundStyle(Theme.personColor(.a))
                        Spacer()
                        Text("\(trip.nameB) \(Int(100 - splitPercentA)) %")
                            .foregroundStyle(Theme.personColor(.b))
                    }
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()

                    Slider(value: $splitPercentA, in: 0...100, step: 5)

                    if let amount = parsedAmount {
                        let shareA = amount * Decimal(splitPercentA) / 100
                        HStack {
                            Text(Money.format(shareA, currencyCode: currencyCode))
                            Spacer()
                            Text(Money.format(amount - shareA, currencyCode: currencyCode))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(L.payerQuestion)
        } footer: {
            if payer == .shared {
                Text(L.expenseSplitHint)
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

            if !canEdit {
                Label(L.expenseReadOnly, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    // MARK: - Aktionen

    private func save() async {
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
        target.category = category
        target.payer = payer
        target.splitPercentA = payer == .shared ? splitPercentA : 50
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.date = date
        target.applyConversion(conversion)

        PersistenceController.shared.save()
        dismiss()
    }

    private func deleteExpense() {
        guard let expense else { return }
        context.delete(expense)
        PersistenceController.shared.save()
        dismiss()
    }
}

#Preview {
    let controller = PersistenceController.preview
    let trip = (try? controller.viewContext.fetch(Trip.fetchRequest()))?.first
    return Group {
        if let trip {
            ExpenseEditorView(trip: trip, expense: nil)
        }
    }
    .environment(\.managedObjectContext, controller.viewContext)
    .preferredColorScheme(.dark)
}
