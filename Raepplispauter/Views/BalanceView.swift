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

    private var report: TripReport {
        SettlementCalculator.report(snapshots: expenses.map(ExpenseSnapshot.init(expense:)),
                                    participants: trip.participantSnapshots,
                                    tripCurrency: trip.currency)
    }

    var body: some View {
        ScrollView {
            let report = self.report
            VStack(spacing: 16) {
                if trip.isClosed {
                    Label(L.settlementClosedNotice, systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .card(padding: 12)
                }

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
            if trip.isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExpenseEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(L.expenseNewTitle)
                }
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

            if trip.participantSnapshots.isEmpty {
                Text(L.balanceNoParticipants)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else if report.expenseCount == 0 {
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
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(report.settlementTrip.transfers.enumerated()), id: \.element.id) { index, transfer in
                        TransferRow(transfer: transfer,
                                    chfAmount: matchingCHFAmount(for: transfer, in: report),
                                    showCHF: trip.currency.uppercased() != Currencies.home,
                                    emphasised: index == 0)
                        if transfer.id != report.settlementTrip.transfers.last?.id {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
            }
        }
        .card()
    }

    /// Sucht zur Zahlung in Reisewährung den passenden CHF-Betrag.
    private func matchingCHFAmount(for transfer: Transfer, in report: TripReport) -> Decimal? {
        report.settlementCHF.transfers
            .first { $0.from.id == transfer.from.id && $0.to.id == transfer.to.id }?
            .amount
    }

    @ViewBuilder
    private func personCards(_ report: TripReport) -> some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(report.tripBalance.balances) { balance in
                personCard(balance, report: report)
            }
        }
    }

    @ViewBuilder
    private func personCard(_ balance: PersonBalance, report: TripReport) -> some View {
        // Wenn zu *allen* Ausgaben der Kurs fehlt, wird gar kein CHF-Wert gezeigt.
        let hasCHF = report.expenseCount == 0 || report.chfBalance.skippedCount < report.expenseCount
        let chf = report.chfBalance.balance(for: balance.id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.participantColor(balance.participant.colorIndex))
                    .frame(width: 8, height: 8)
                Text(balance.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L.balanceNet)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                DualAmountView(tripAmount: balance.net,
                               tripCurrency: trip.currency,
                               chfAmount: hasCHF ? chf?.net : nil,
                               alignment: .leading,
                               primaryFont: .title3.weight(.bold),
                               colorise: true)
            }

            Divider().overlay(Theme.separator)

            VStack(alignment: .leading, spacing: 4) {
                LabeledValueRow(label: L.balancePaid) {
                    Text(Money.format(balance.paid, currencyCode: trip.currency))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                LabeledValueRow(label: L.balanceShare) {
                    Text(Money.format(balance.share, currencyCode: trip.currency))
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
            let recent = Array(expenses.prefix(5))
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L.balanceRecent)
                ForEach(recent, id: \.objectID) { expense in
                    ExpenseRow(snapshot: ExpenseSnapshot(expense: expense),
                               tripCurrency: trip.currency,
                               participants: trip.participantSnapshots)
                    if expense.objectID != recent.last?.objectID {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .card()
        }
    }
}

/// Eine Zeile "X zahlt Y" der Schlussabrechnung.
struct TransferRow: View {
    let transfer: Transfer
    let chfAmount: Decimal?
    let showCHF: Bool
    var emphasised = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.participantColor(transfer.from.colorIndex))
                    .frame(width: 7, height: 7)
                Text(transfer.from.name)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                Circle()
                    .fill(Theme.participantColor(transfer.to.colorIndex))
                    .frame(width: 7, height: 7)
                Text(transfer.to.name)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)

            Text(Money.format(transfer.amount, currencyCode: transfer.currencyCode))
                .font(emphasised
                      ? .system(size: 30, weight: .bold, design: .rounded)
                      : .title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .monospacedDigit()

            if showCHF, let chfAmount {
                Text(Money.format(chfAmount, currencyCode: Currencies.home))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}
