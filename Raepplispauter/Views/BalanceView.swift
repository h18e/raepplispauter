import CoreData
import SwiftUI

/// Startbildschirm: zeigt beim App-Start sofort die aktuelle Bilanz der laufenden
/// Reise – wer steht im Plus, wer im Minus, in Reisewährung **und** CHF.
struct BalanceView: View {

    @ObservedObject var trip: Trip

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    @FetchRequest private var expenses: FetchedResults<Expense>
    @State private var showExpenseEditor = false

    init(trip: Trip) {
        _trip = ObservedObject(wrappedValue: trip)
        _expenses = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
                                 predicate: NSPredicate(format: "trip == %@", trip),
                                 animation: .default)
    }

    private var snapshots: [ExpenseSnapshot] {
        expenses.map(ExpenseSnapshot.init(expense:))
    }

    private var report: TripReport {
        SettlementCalculator.report(snapshots: snapshots,
                                    tripCurrency: trip.currency,
                                    costSharePercentA: trip.costSharePercentADecimal)
    }

    var body: some View {
        ScrollView {
            let report = self.report
            VStack(spacing: 16) {
                settlementCard(report)
                personCards(report)
                totalsCard(report)

                if report.provisionalCount > 0 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text(L.balanceMissingRates(report.provisionalCount))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .card()
                }

                recentExpenses
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExpenseEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel(L.expenseNewTitle)
            }
        }
        .sheet(isPresented: $showExpenseEditor) {
            ExpenseEditorView(trip: trip, expense: nil)
        }
        .refreshable {
            await appState.refreshRates(context: context)
        }
    }

    // MARK: - Bausteine

    @ViewBuilder
    private func settlementCard(_ report: TripReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L.balanceTitle)

            if report.expenseCount == 0 {
                Text(L.balanceNoExpenses)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else if report.settlementTrip.isBalanced {
                HStack(spacing: 10) {
                    Image(systemName: "equal.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text(L.balanceEven)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                let settlement = report.settlementTrip
                let debtorName = trip.name(for: settlement.debtor ?? .b)
                let creditorName = trip.name(for: settlement.creditor ?? .a)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.balanceOwesShort(debtorName, creditorName))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text(Money.format(settlement.amount, currencyCode: settlement.currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()

                    if trip.currency.uppercased() != Currencies.home {
                        Text(Money.format(report.settlementCHF.amount, currencyCode: Currencies.home))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func personCards(_ report: TripReport) -> some View {
        HStack(spacing: 12) {
            personCard(.a, report: report)
            personCard(.b, report: report)
        }
    }

    @ViewBuilder
    private func personCard(_ person: Person, report: TripReport) -> some View {
        let tripBalance = report.tripBalance.balance(for: person)
        let chfBalance = report.chfBalance.balance(for: person)
        // Wenn zu *allen* Ausgaben der Kurs fehlt, wird gar kein CHF-Wert gezeigt.
        let hasCHF = report.expenseCount == 0 || report.chfBalance.skippedCount < report.expenseCount

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.personColor(person))
                    .frame(width: 8, height: 8)
                Text(trip.name(for: person))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L.balanceNet)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                DualAmountView(tripAmount: tripBalance.net,
                               tripCurrency: trip.currency,
                               chfAmount: hasCHF ? chfBalance.net : nil,
                               alignment: .leading,
                               primaryFont: .title3.weight(.bold),
                               colorise: true)
            }

            Divider().overlay(Theme.separator)

            VStack(alignment: .leading, spacing: 4) {
                LabeledValueRow(label: L.balancePaid) {
                    Text(Money.format(tripBalance.paid, currencyCode: trip.currency))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                LabeledValueRow(label: L.balanceShare) {
                    Text(Money.format(tripBalance.share, currencyCode: trip.currency))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
            }
            .font(.caption)
        }
        .card(padding: 14)
    }

    @ViewBuilder
    private func totalsCard(_ report: TripReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L.balanceTotalExpenses)
            HStack(alignment: .firstTextBaseline) {
                DualAmountView(tripAmount: report.tripBalance.total,
                               tripCurrency: trip.currency,
                               chfAmount: report.chfBalance.total,
                               alignment: .leading,
                               primaryFont: .title2.weight(.bold))
                Spacer()
                Text(L.logbookCount(report.expenseCount))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private var recentExpenses: some View {
        if !expenses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.balanceRecent)
                ForEach(Array(expenses.prefix(5)), id: \.objectID) { expense in
                    ExpenseRow(snapshot: ExpenseSnapshot(expense: expense),
                               tripCurrency: trip.currency,
                               nameA: trip.nameA,
                               nameB: trip.nameB)
                    if expense.objectID != expenses.prefix(5).last?.objectID {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .card()
        }
    }
}

#Preview {
    let controller = PersistenceController.preview
    let trip = (try? controller.viewContext.fetch(Trip.fetchRequest()))?.first
    return NavigationStack {
        if let trip {
            BalanceView(trip: trip)
        }
    }
    .environment(\.managedObjectContext, controller.viewContext)
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
