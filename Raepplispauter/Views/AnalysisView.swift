import CoreData
import SwiftUI

/// Auswertung: Ausgaben aufgeschlüsselt nach Kategorie und Zahler –
/// immer in Reisewährung **und** CHF.
struct AnalysisView: View {

    @ObservedObject var trip: Trip

    @FetchRequest private var expenses: FetchedResults<Expense>

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

    private var showsCHF: Bool { trip.currency.uppercased() != Currencies.home }

    var body: some View {
        Group {
            if expenses.isEmpty {
                EmptyStateView(symbol: "chart.pie", title: L.analysisEmpty)
            } else {
                ScrollView {
                    let report = self.report
                    VStack(spacing: 16) {
                        totalCard(report)
                        categorySection(report)
                        payerSection(report)
                    }
                    .padding(16)
                }
            }
        }
        .screenBackground()
        .navigationTitle(L.analysisTitle)
    }

    // MARK: - Bausteine

    @ViewBuilder
    private func totalCard(_ report: TripReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L.balanceTotalExpenses)
            DualAmountView(tripAmount: report.tripBalance.total,
                           tripCurrency: trip.currency,
                           chfAmount: report.chfBalance.total,
                           alignment: .leading,
                           primaryFont: .title.weight(.bold))
            Text(L.logbookCount(report.expenseCount))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    @ViewBuilder
    private func categorySection(_ report: TripReport) -> some View {
        let maximum = report.categories.map(\.totalTrip).max() ?? 1

        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: L.analysisByCategory)
            ForEach(report.categories) { row in
                VStack(spacing: 4) {
                    BarRow(title: row.name,
                           symbolName: row.symbolName,
                           color: Theme.categoryColor(row.colorIndex),
                           fraction: fraction(row.totalTrip, of: maximum),
                           primaryText: Money.format(row.totalTrip, currencyCode: trip.currency),
                           secondaryText: showsCHF
                               ? Money.format(row.totalCHF, currencyCode: Currencies.home)
                               : nil)

                    HStack {
                        Text(L.logbookCount(row.count))
                        Spacer()
                        Text(percentText(row.totalTrip, of: report.tripBalance.total))
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func payerSection(_ report: TripReport) -> some View {
        let maximum = report.payers.map(\.totalTrip).max() ?? 1

        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: L.analysisByPayer,
                          subtitle: L.analysisByPayerHint)
            ForEach(report.payers) { row in
                BarRow(title: row.participant.name,
                       symbolName: "person.fill",
                       color: Theme.participantColor(row.participant.colorIndex),
                       fraction: fraction(row.totalTrip, of: maximum),
                       primaryText: Money.format(row.totalTrip, currencyCode: trip.currency),
                       secondaryText: showsCHF
                           ? Money.format(row.totalCHF, currencyCode: Currencies.home)
                           : nil)
            }
        }
        .card()
    }

    private func fraction(_ value: Decimal, of maximum: Decimal) -> Double {
        guard maximum > 0 else { return 0 }
        return NSDecimalNumber(decimal: value / maximum).doubleValue
    }

    private func percentText(_ value: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return "0 %" }
        let percent = NSDecimalNumber(decimal: value / total * 100).doubleValue
        return String(format: "%.0f %%", percent)
    }
}
