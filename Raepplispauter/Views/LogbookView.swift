import CoreData
import SwiftUI

/// Logbuch: chronologische, filter- und sortierbare Liste aller Ausgaben
/// mit Bearbeiten und Löschen.
struct LogbookView: View {

    @ObservedObject var trip: Trip

    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var categoryFilter: ExpenseCategory?
    @State private var payerFilter: Payer?
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var editTarget: EditTarget?
    @State private var showNewExpense = false

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
        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }
        if let payerFilter {
            result = result.filter { $0.payer == payerFilter }
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

    private var isFiltering: Bool { categoryFilter != nil || payerFilter != nil }

    var body: some View {
        Group {
            if expenses.isEmpty {
                EmptyStateView(symbol: "list.bullet.rectangle",
                               title: L.logbookEmpty,
                               actionTitle: L.expenseNewTitle) { showNewExpense = true }
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
                                           nameA: trip.nameA,
                                           nameB: trip.nameB)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete(perform: delete)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewExpense = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(L.expenseNewTitle)
            }
        }
        .sheet(item: $editTarget) { target in
            ExpenseEditorView(trip: trip, expense: target.expense)
        }
        .sheet(isPresented: $showNewExpense) {
            ExpenseEditorView(trip: trip, expense: nil)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker(L.logbookSort, selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }

            Picker(L.expenseCategory, selection: $categoryFilter) {
                Text(L.logbookAllCategories).tag(ExpenseCategory?.none)
                ForEach(ExpenseCategory.ordered) { category in
                    Label(category.displayName, systemImage: category.symbolName)
                        .tag(ExpenseCategory?.some(category))
                }
            }

            Picker(L.fieldPayer, selection: $payerFilter) {
                Text(L.logbookAllPayers).tag(Payer?.none)
                Text(trip.nameA).tag(Payer?.some(.a))
                Text(trip.nameB).tag(Payer?.some(.b))
                Text(L.payerShared).tag(Payer?.some(.shared))
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
        categoryFilter = nil
        payerFilter = nil
    }

    private func delete(at offsets: IndexSet) {
        let items = filtered
        for index in offsets {
            guard items.indices.contains(index) else { continue }
            context.delete(items[index])
        }
        PersistenceController.shared.save()
    }
}

#Preview {
    let controller = PersistenceController.preview
    let trip = (try? controller.viewContext.fetch(Trip.fetchRequest()))?.first
    return NavigationStack {
        if let trip {
            LogbookView(trip: trip)
        }
    }
    .environment(\.managedObjectContext, controller.viewContext)
    .preferredColorScheme(.dark)
}
