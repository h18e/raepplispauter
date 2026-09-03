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
                                    tripCurrency: trip.currency,
                                    costSharePercentA: trip.costSharePercentADecimal)
    }

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
                BarRow(title: row.category.displayName,
                       symbolName: row.category.symbolName,
                       color: Theme.categoryColor(row.category),
                       fraction: fraction(row.totalTrip, of: maximum),
                       primaryText: Money.format(row.totalTrip, currencyCode: trip.currency),
                       secondaryText: trip.currency.uppercased() == Currencies.home
                           ? nil
                           : Money.format(row.totalCHF, currencyCode: Currencies.home))

                HStack(spacing: 10) {
                    personChip(.a, amount: row.paidATrip)
                    personChip(.b, amount: row.paidBTrip)
                    Spacer()
                    Text(percentText(row.totalTrip, of: report.tripBalance.total))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func payerSection(_ report: TripReport) -> some View {
        let maximum = report.payers.map(\.totalTrip).max() ?? 1

        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: L.analysisByPayer)
            ForEach(report.payers) { row in
                BarRow(title: payerName(row.payer),
                       symbolName: row.payer == .shared ? "person.2.fill" : "person.fill",
                       color: payerColor(row.payer),
                       fraction: fraction(row.totalTrip, of: maximum),
                       primaryText: Money.format(row.totalTrip, currencyCode: trip.currency),
                       secondaryText: trip.currency.uppercased() == Currencies.home
                           ? nil
                           : Money.format(row.totalCHF, currencyCode: Currencies.home))
            }
        }
        .card()
    }

    @ViewBuilder
    private func personChip(_ person: Person, amount: Decimal) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.personColor(person))
                .frame(width: 6, height: 6)
            Text("\(trip.name(for: person)) \(Money.formatPlain(amount))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func payerName(_ payer: Payer) -> String {
        switch payer {
        case .a: return trip.nameA
        case .b: return trip.nameB
        case .shared: return L.payerShared
        }
    }

    private func payerColor(_ payer: Payer) -> Color {
        switch payer {
        case .a: return Theme.personColor(.a)
        case .b: return Theme.personColor(.b)
        case .shared: return Theme.accent
        }
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

#Preview {
    let controller = PersistenceController.preview
    let trip = (try? controller.viewContext.fetch(Trip.fetchRequest()))?.first
    return NavigationStack {
        if let trip {
            AnalysisView(trip: trip)
        }
    }
    .environment(\.managedObjectContext, controller.viewContext)
    .preferredColorScheme(.dark)
}
