import CoreData
import Foundation

/// Füllt Ausgaben nach, die offline ohne Wechselkurs erfasst wurden.
///
/// Ablauf: Sobald wieder Kurse verfügbar sind (App-Start, Pull-to-Refresh oder
/// manuelles "Kürs aktualisiere"), werden alle Ausgaben mit
/// `isRateProvisional == true` erneut umgerechnet und die eingefrorenen
/// Kursfelder gesetzt. Der Erfassungstag bleibt massgebend – es wird also der
/// historische Kurs nachgetragen, nicht der heutige.
public enum RateBackfillService {

    @discardableResult
    public static func backfill(in context: NSManagedObjectContext,
                                using service: ExchangeRateService = .shared) async -> Int {
        // 1. Kurse aktualisieren (Fehler sind unkritisch – dann bleibt alles provisorisch).
        _ = try? await service.refreshRates()

        // 2. Betroffene Ausgaben laden.
        let request = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "isRateProvisional == YES")

        let candidates: [(objectID: NSManagedObjectID, amount: Decimal, currency: String, tripCurrency: String, date: Date)] =
            await context.perform {
                let expenses = (try? context.fetch(request)) ?? []
                return expenses.map {
                    ($0.objectID,
                     $0.amountDecimal,
                     $0.currency,
                     $0.trip?.currency ?? $0.currency,
                     $0.date ?? Date())
                }
            }

        guard !candidates.isEmpty else { return 0 }

        // 3. Umrechnen (ausserhalb des Kontexts, danach zurückschreiben).
        var conversions: [(NSManagedObjectID, CurrencyConversion)] = []
        for candidate in candidates {
            let conversion = await service.convert(amount: candidate.amount,
                                                   from: candidate.currency,
                                                   tripCurrency: candidate.tripCurrency,
                                                   on: candidate.date,
                                                   allowNetwork: false)
            if !conversion.isProvisional {
                conversions.append((candidate.objectID, conversion))
            }
        }

        guard !conversions.isEmpty else { return 0 }

        return await context.perform {
            var updated = 0
            for (objectID, conversion) in conversions {
                guard let expense = try? context.existingObject(with: objectID) as? Expense else { continue }
                expense.applyConversion(conversion)
                // updatedAt bewusst NICHT anfassen: das Nachtragen eines Kurses ist
                // keine inhaltliche Änderung durch eine Person und soll im
                // Konflikt-Protokoll nicht als Bearbeitung erscheinen.
                updated += 1
            }
            if context.hasChanges {
                try? context.save()
            }
            return updated
        }
    }
}
