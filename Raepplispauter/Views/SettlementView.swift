import CoreData
import SwiftUI
import UIKit

/// Schlussabrechnung am Reiseende: wer zahlt wem wie viel, Detailzahlen je Person
/// und CSV-Export über die iOS-Freigabefunktion.
struct SettlementView: View {

    @ObservedObject var trip: Trip

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var appState: AppState

    @FetchRequest private var expenses: FetchedResults<Expense>

    @State private var exportFile: ExportFile?
    @State private var errorMessage: String?
    @State private var showCloseConfirmation = false

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
                                    participants: trip.participantSnapshots,
                                    tripCurrency: trip.currency)
    }

    private var showsCHF: Bool { trip.currency.uppercased() != Currencies.home }

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
        .confirmationDialog(L.settlementCloseConfirm,
                            isPresented: $showCloseConfirmation,
                            titleVisibility: .visible) {
            Button(L.settlementCloseTrip) { setClosed(true) }
            Button(L.cancel, role: .cancel) {}
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
                ForEach(Array(report.settlementTrip.transfers.enumerated()), id: \.element.id) { index, transfer in
                    TransferRow(transfer: transfer,
                                chfAmount: matchingCHFAmount(for: transfer, in: report),
                                showCHF: showsCHF,
                                emphasised: index == 0,
                                myParticipantID: appState.myParticipantID(in: trip))
                    if transfer.id != report.settlementTrip.transfers.last?.id {
                        Divider().overlay(Theme.separator)
                    }
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

    private func matchingCHFAmount(for transfer: Transfer, in report: TripReport) -> Decimal? {
        report.settlementCHF.transfers
            .first { $0.from.id == transfer.from.id && $0.to.id == transfer.to.id }?
            .amount
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

            ForEach(report.tripBalance.balances) { balance in
                let chf = report.chfBalance.balance(for: balance.id)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.participantColor(balance.participant.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(balance.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Money.formatPlain(balance.participant.costSharePercent, fractionDigits: 1)) %")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }

                    detailRow(L.balancePaid,
                              tripValue: balance.paid,
                              chfValue: chf?.paid ?? 0)
                    detailRow(L.balanceShare,
                              tripValue: balance.share,
                              chfValue: chf?.share ?? 0)
                    detailRow(L.balanceNet,
                              tripValue: balance.net,
                              chfValue: chf?.net ?? 0,
                              colorise: true)
                }
                .padding(.vertical, 4)

                if balance.id != report.tripBalance.balances.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
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
                if trip.isClosed {
                    setClosed(false)
                } else {
                    showCloseConfirmation = true
                }
            } label: {
                Label(trip.isClosed ? L.settlementReopenTrip : L.settlementCloseTrip,
                      systemImage: trip.isClosed ? "lock.open" : "lock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .card()
    }

    // MARK: - Aktionen

    private func setClosed(_ closed: Bool) {
        trip.isClosed = closed
        PersistenceController.shared.save()
    }

    private func exportCSV() {
        let result = CSVExporter.makeCSV(tripName: trip.displayName,
                                         tripCurrency: trip.currency,
                                         startDate: trip.startDate,
                                         endDate: trip.endDate,
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
