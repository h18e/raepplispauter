import CoreData
import SwiftUI

/// Kategorien einer Reise verwalten: anlegen, umbenennen, Symbol und Farbe
/// wählen, löschen.
///
/// Kategorien gehören zur Reise und wandern damit beim Teilen mit – beide
/// Geräte sehen dieselbe Liste.
struct CategoryEditorView: View {

    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var categories: FetchedResults<ExpenseCategory>

    @State private var editTarget: EditTarget?
    @State private var showNewCategory = false
    @State private var errorMessage: String?

    init(trip: Trip) {
        _trip = ObservedObject(wrappedValue: trip)
        _categories = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)],
                                   predicate: NSPredicate(format: "trip == %@", trip),
                                   animation: .default)
    }

    private struct EditTarget: Identifiable {
        let id: NSManagedObjectID
        let category: ExpenseCategory
    }

    var body: some View {
        List {
            Section {
                ForEach(categories, id: \.objectID) { category in
                    Button {
                        guard trip.isEditable else { return }
                        editTarget = EditTarget(id: category.objectID, category: category)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.categoryColor(Int(category.colorIndex)).opacity(0.18))
                                Image(systemName: category.symbol)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.categoryColor(Int(category.colorIndex)))
                            }
                            .frame(width: 32, height: 32)

                            Text(category.displayName)
                                .foregroundStyle(Theme.textPrimary)

                            Spacer()

                            if category.expenseCount > 0 {
                                Text("\(category.expenseCount)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
                .onDelete { offsets in
                    delete(at: offsets)
                }
            } footer: {
                Text(L.categoriesDeleteHint)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(L.categoriesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewCategory = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(L.categoryNew)
                .disabled(!trip.isEditable)
            }
        }
        .sheet(isPresented: $showNewCategory) {
            CategoryDetailView(trip: trip, category: nil)
        }
        .sheet(item: $editTarget) { target in
            CategoryDetailView(trip: trip, category: target.category)
        }
        .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
            Button(L.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete(at offsets: IndexSet) {
        guard trip.isEditable else {
            errorMessage = L.tripClosedBlocked
            return
        }

        let items = offsets.compactMap { categories.indices.contains($0) ? categories[$0] : nil }

        // Benutzte Kategorien dürfen nicht weg – sonst hätten Ausgaben keine mehr.
        let used = items.filter(\.isUsed)
        guard used.isEmpty else {
            errorMessage = L.categoryDeleteBlocked(used.map(\.displayName).joined(separator: ", "))
            return
        }
        guard categories.count - items.count >= 1 else {
            errorMessage = L.categoryNeedsOne
            return
        }

        for category in items {
            context.delete(category)
        }
        PersistenceController.shared.save()
    }
}

/// Eine Kategorie anlegen oder bearbeiten.
struct CategoryDetailView: View {

    @ObservedObject var trip: Trip
    let category: ExpenseCategory?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var name: String
    @State private var symbolName: String
    @State private var colorIndex: Int

    init(trip: Trip, category: ExpenseCategory?) {
        _trip = ObservedObject(wrappedValue: trip)
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _symbolName = State(initialValue: category?.symbol ?? "tag.fill")
        _colorIndex = State(initialValue: Int(category?.colorIndex ?? Int16(trip.categoryList.count % Theme.categoryPaletteSize)))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L.categoryName) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.categoryColor(colorIndex).opacity(0.18))
                            Image(systemName: symbolName)
                                .foregroundStyle(Theme.categoryColor(colorIndex))
                        }
                        .frame(width: 36, height: 36)

                        TextField(L.categoryNamePlaceholder, text: $name)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section(L.categoryColor) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(0..<Theme.categoryPaletteSize, id: \.self) { index in
                            Button {
                                colorIndex = index
                            } label: {
                                Circle()
                                    .fill(Theme.categoryColor(index))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.textPrimary, lineWidth: colorIndex == index ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(L.categorySymbol) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                        ForEach(ExpenseCategory.availableSymbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(symbolName == symbol
                                                  ? Theme.categoryColor(colorIndex).opacity(0.24)
                                                  : Color.white.opacity(0.05))
                                    )
                                    .foregroundStyle(symbolName == symbol
                                                     ? Theme.categoryColor(colorIndex)
                                                     : Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(category == nil ? L.categoryNew : L.categoryEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }

        if let category {
            category.name = trimmedName
            category.symbolName = symbolName
            category.colorIndex = Int16(colorIndex)
        } else {
            ExpenseCategory.create(in: context,
                                   trip: trip,
                                   name: trimmedName,
                                   symbolName: symbolName,
                                   colorIndex: colorIndex)
        }
        PersistenceController.shared.save()
        dismiss()
    }
}
