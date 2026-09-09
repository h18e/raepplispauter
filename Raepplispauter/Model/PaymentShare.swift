import CoreData
import Foundation

/// Anteil einer Person an der **Auslage** einer einzelnen Ausgabe.
///
/// Nur relevant, wenn mehrere Personen zusammen bezahlt haben
/// (`Expense.payer == nil`). Die Summe aller Anteile einer Ausgabe ergibt 100 %.
@objc(PaymentShare)
public final class PaymentShare: NSManagedObject, Identifiable {

    @NSManaged public var id: UUID?
    /// Anteil in Prozent (0…100).
    @NSManaged public var percent: Double
    @NSManaged public var expense: Expense?
    @NSManaged public var participant: Participant?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PaymentShare> {
        NSFetchRequest<PaymentShare>(entityName: "PaymentShare")
    }

    @discardableResult
    public static func create(in context: NSManagedObjectContext,
                              expense: Expense,
                              participant: Participant,
                              percent: Double) -> PaymentShare {
        let share = PaymentShare(context: context)
        share.id = UUID()
        share.percent = percent
        share.expense = expense
        share.participant = participant
        if let store = expense.objectID.persistentStore {
            context.assign(share, to: store)
        }
        return share
    }
}
