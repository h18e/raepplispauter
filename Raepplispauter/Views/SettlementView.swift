import CoreData
import SwiftUI
import UIKit

/// Schlussabrechnung am Reiseende: wer schuldet wem wie viel, Detailzahlen und
/// CSV-Export über die iOS-Freigabefunktion.
struct SettlementView: View {

    @ObservedObject var trip: Trip

    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var exportFile: ExportFile?
    @State private var errorMessage: String?

    init(trip: Trip) {
        _trip = ObservedObject(wrappedValue: trip)
        _expenses = FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
                                 predicate: NSPredicate(format: "trip == %@", trip),
                                 animation: .default)
    }

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
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
                if trip.isClosed {
                    Label(L.settlementClosedNotice, systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .card(padding: 12)
                }

                settlementCard(report)
                detailsCard(report)
                actionsCard
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(L.settlementTitle)
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .alert(L.errorTitle, isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
            Button(L.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Bausteine

    @ViewBuilder
    private func settlementCard(_ report: TripReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L.settlementFinal)

            if report.settlementTrip.isBalanced {
                HStack(spacing: 10) {
                    Image(systemName: "equal.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text(L.settlementBalanced)
                        .font(.headline)
                }
            } else {
                let settlement = report.settlementTrip
                let debtorName = trip.name(for: settlement.debtor ?? .b)
                let creditorName = trip.name(for: settlement.creditor ?? .a)

                Text(L.balanceOwesShort(debtorName, creditorName))
                    .font(.headline)
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

            if report.provisionalCount > 0 {
                Text(L.balanceMissingRates(report.provisionalCount))
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
        .card()
    }

    @ViewBuilder
    private func detailsCard(_ report: TripReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L.settlementDetails)

            detailRow(L.balanceTotalExpenses,
                      tripValue: report.tripBalance.total,
                      chfValue: report.chfBalance.total,
                      emphasised: true)
            Divider().overlay(Theme.separator)

            detailRow(L.csvRowPaid(trip.nameA),
                      tripValue: report.tripBalance.a.paid,
                      chfValue: report.chfBalance.a.paid)
            detailRow(L.csvRowPaid(trip.nameB),
                      tripValue: report.tripBalance.b.paid,
                      chfValue: report.chfBalance.b.paid)
            Divider().overlay(Theme.separator)

            detailRow(L.csvRowShare(trip.nameA),
                      tripValue: report.tripBalance.a.share,
                      chfValue: report.chfBalance.a.share)
            detailRow(L.csvRowShare(trip.nameB),
                      tripValue: report.tripBalance.b.share,
                      chfValue: report.chfBalance.b.share)
            Divider().overlay(Theme.separator)

            detailRow(L.csvRowNet(trip.nameA),
                      tripValue: report.tripBalance.a.net,
                      chfValue: report.chfBalance.a.net,
                      colorise: true)
            detailRow(L.csvRowNet(trip.nameB),
                      tripValue: report.tripBalance.b.net,
                      chfValue: report.chfBalance.b.net,
                      colorise: true)
        }
        .card()
    }

    @ViewBuilder
    private func detailRow(_ label: String,
                           tripValue: Decimal,
                           chfValue: Decimal,
                           emphasised: Bool = false,
                           colorise: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(emphasised ? Theme.textPrimary : Theme.textSecondary)
            Spacer(minLength: 12)
            DualAmountView(tripAmount: tripValue,
                           tripCurrency: trip.currency,
                           chfAmount: chfValue,
                           colorise: colorise)
        }
    }

    @ViewBuilder
    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                exportCSV()
            } label: {
                Label(L.settlementExport, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(expenses.isEmpty)

            Button {
                trip.isClosed.toggle()
                PersistenceController.shared.save()
            } label: {
                Label(trip.isClosed ? L.settlementReopenTrip : L.settlementCloseTrip,
                      systemImage: trip.isClosed ? "lock.open" : "lock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .card()
    }

    // MARK: - Export

    private func exportCSV() {
        let result = CSVExporter.makeCSV(tripName: trip.displayName,
                                         tripCurrency: trip.currency,
                                         startDate: trip.startDate,
                                         endDate: trip.endDate,
                                         nameA: trip.nameA,
                                         nameB: trip.nameB,
                                         snapshots: snapshots,
                                         report: report)
        do {
            let url = try CSVExporter.writeTemporaryFile(result)
            exportFile = ExportFile(url: url)
        } catch {
            errorMessage = L.settlementExportFailed
        }
    }
}

/// Hülle um `UIActivityViewController` – das ist die iOS-Freigabefunktion
/// (Mail, Nachrichten, Dateien, AirDrop …) für den CSV-Export.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let controller = PersistenceController.preview
    let trip = (try? controller.viewContext.fetch(Trip.fetchRequest()))?.first
    return NavigationStack {
        if let trip {
            SettlementView(trip: trip)
        }
    }
    .environment(\.managedObjectContext, controller.viewContext)
    .preferredColorScheme(.dark)
}
