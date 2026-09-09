import CoreData
import SwiftUI

/// Logbuch: chronologische, filter- und sortierbare Liste aller Ausgaben
/// mit Bearbeiten und Löschen.
///
/// Ist die Reise abgeschlossen, sind Erfassen, Ändern und Löschen gesperrt.
struct LogbookView: View {

    @ObservedObject var trip: Trip

    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var categoryFilterID: UUID?
    @State private var payerFilterID: UUID?
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var editTarget: EditTarget?
    @State private var showNewExpense = false
    @State private var errorMessage: String?

    init(trip: Trip) {
        _trip = ObservedObject(wrappedValue: trip)
        _expenses = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
                                 predicate: NSPredicate(format: "trip == %@", trip),
                                 animation: .default)
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDescending, dateAscending, amountDescending, amountAscending

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateDescending: return L.logbookSortDateDesc
            case .dateAscending: return L.logbookSortDateAsc
            case .amountDescending: return L.logbookSortAmountDesc
            case .amountAscending: return L.logbookSortAmountAsc
            }
        }
    }

    private struct EditTarget: Identifiable {
        let id: NSManagedObjectID
        let expense: Expense
    }

    private var filtered: [Expense] {
        var result = Array(expenses)
        if let categoryFilterID {
            result = result.filter { $0.category?.id == categoryFilterID }
        }
        if let payerFilterID {
            // Zählt auch als Treffer, wenn die Person nur anteilig bezahlt hat.
            result = result.filter { ($0.paymentPercentages[payerFilterID] ?? 0) > 0 }
        }
        switch sortOrder {
        case .dateDescending:
            result.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .dateAscending:
            result.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .amountDescending:
            result.sort { $0.amountTripDecimal > $1.amountTripDecimal }
        case .amountAscending:
            result.sort { $0.amountTripDecimal < $1.amountTripDecimal }
        }
        return result
    }

    private var isFiltering: Bool { categoryFilterID != nil || payerFilterID != nil }

    var body: some View {
        Group {
            if expenses.isEmpty {
                EmptyStateView(symbol: "list.bullet.rectangle",
                               title: L.logbookEmpty,
                               actionTitle: trip.isEditable ? L.expenseNewTitle : nil) {
                    showNewExpense = true
                }
            } else if filtered.isEmpty {
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle",
                               title: L.logbookEmptyFiltered,
                               actionTitle: L.logbookResetFilter) { resetFilters() }
            } else {
                List {
                    Section {
                        ForEach(filtered, id: \.objectID) { expense in
                            Button {
                                editTarget = EditTarget(id: expense.objectID, expense: expense)
                            } label: {
                                ExpenseRow(snapshot: ExpenseSnapshot(expense: expense),
                                           tripCurrency: trip.currency,
                                           participants: trip.participantSnapshots)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete { offsets in
                            delete(at: offsets)
                        }
                    } header: {
                        Text(L.logbookCount(filtered.count))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .screenBackground()
        .navigationTitle(L.logbookTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            if trip.isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewExpense = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(L.expenseNewTitle)
                }
            }
        }
        .sheet(item: $editTarget) { target in
            ExpenseEditorView(trip: trip, expense: target.expense)
        }
        .sheet(isPresented: $showNewExpense) {
            ExpenseEditorView(trip: trip, expense: nil)
        }
        .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
            Button(L.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker(L.logbookSort, selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }

            Picker(L.expenseCategory, selection: $categoryFilterID) {
                Text(L.logbookAllCategories).tag(UUID?.none)
                ForEach(trip.categoryList, id: \.objectID) { category in
                    Label(category.displayName, systemImage: category.symbol)
                        .tag(category.id)
                }
            }

            Picker(L.fieldPayer, selection: $payerFilterID) {
                Text(L.logbookAllPayers).tag(UUID?.none)
                ForEach(trip.participantList, id: \.objectID) { participant in
                    Text(participant.displayName).tag(participant.id)
                }
            }

            if isFiltering {
                Divider()
                Button(L.logbookResetFilter, systemImage: "arrow.counterclockwise") {
                    resetFilters()
                }
            }
        } label: {
            Image(systemName: isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private func resetFilters() {
        categoryFilterID = nil
        payerFilterID = nil
    }

    private func delete(at offsets: IndexSet) {
        guard trip.isEditable else {
            errorMessage = L.tripClosedBlocked
            return
        }
        let items = filtered
        for index in offsets {
            guard items.indices.contains(index) else { continue }
            context.delete(items[index])
        }
        PersistenceController.shared.save()
    }
}
