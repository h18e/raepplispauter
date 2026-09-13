import CoreData
import Foundation
import WidgetKit

/// Schreibt die Momentaufnahme für das Sperrbildschirm-Widget.
///
/// Gehört zum App-Target: Hier liegen Core Data, `SettlementCalculator` und
/// `Money`. Das Widget selbst rechnet nichts – es zeigt nur, was hier abgelegt
/// wurde (siehe `Shared/WidgetSharing.swift`).
enum WidgetSnapshotWriter {

    /// Rechnet die aktuelle Kassä durch und legt das Ergebnis für das Widget ab.
    ///
    /// - Parameters:
    ///   - trip: Die angezeigte Kassä. `nil` löscht die Momentaufnahme.
    ///   - myParticipantID: Wer sitzt an diesem Gerät? Ohne diese Zuordnung
    ///     gibt es keinen persönlichen Saldo – das Widget zeigt dann die
    ///     Gesamtsumme und fragt nach der Zuordnung.
    @MainActor
    static func refresh(for trip: Trip?,
                        myParticipantID: UUID?,
                        in context: NSManagedObjectContext) {
        WidgetSharing.save(trip.map { snapshot(for: $0, myParticipantID: myParticipantID, in: context) })

        // Nur das eigene Widget neu laden, nicht alle auf dem Gerät.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharing.widgetKind)
    }

    @MainActor
    private static func snapshot(for trip: Trip,
                                 myParticipantID: UUID?,
                                 in context: NSManagedObjectContext) -> KassaWidgetSnapshot {
        let request = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "trip == %@", trip)
        let expenses = (try? context.fetch(request)) ?? []

        let report = SettlementCalculator.report(snapshots: expenses.map(ExpenseSnapshot.init(expense:)),
                                                 participants: trip.participantSnapshots,
                                                 tripCurrency: trip.currency)

        let totalText = Money.format(report.tripBalance.total, currencyCode: trip.currency)

        // Ohne Zuordnung "das bin ich" liesse sich kein persönlicher Saldo
        // bilden – irgendeine Person zu wählen wäre geraten und damit falsch.
        guard let myParticipantID,
              let myBalance = report.tripBalance.balance(for: myParticipantID) else {
            return KassaWidgetSnapshot(tripName: trip.displayName,
                                       standing: .unknownPerson,
                                       totalText: totalText,
                                       expenseCount: report.expenseCount,
                                       isClosed: trip.isClosed)
        }

        let net = myBalance.net
        let standing: KassaWidgetSnapshot.Standing
        if Money.isZero(net) {
            standing = .balanced
        } else {
            standing = net > 0 ? .getsBack : .owes
        }

        // Das Vorzeichen steckt im Zustand (`standing`) und damit im Text des
        // Widgets. Der Betrag wird deshalb ohne Vorzeichen gezeigt – "Du muesch
        // zahle: −20" liest sich wie eine doppelte Verneinung.
        let absolute = abs(net)

        // CHF nur, wenn für diese Person überhaupt ein Kurs vorlag.
        let chfText: String? = {
            guard report.chfBalance.skippedCount < report.expenseCount || report.expenseCount == 0,
                  let chf = report.chfBalance.balance(for: myParticipantID) else { return nil }
            return Money.format(abs(chf.net), currencyCode: "CHF")
        }()

        return KassaWidgetSnapshot(
            tripName: trip.displayName,
            standing: standing,
            netText: Money.format(absolute, currencyCode: trip.currency),
            netCHFText: chfText,
            // Das runde Widget ist winzig – dort passt nur die gerundete Zahl.
            netCompactText: Money.formatPlain(absolute, fractionDigits: 0),
            totalText: totalText,
            expenseCount: report.expenseCount,
            isClosed: trip.isClosed
        )
    }
}
