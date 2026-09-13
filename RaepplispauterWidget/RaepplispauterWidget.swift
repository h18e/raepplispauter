import SwiftUI
import WidgetKit

/// Einstiegspunkt der Widget-Erweiterung.
@main
struct RaepplispauterWidgetBundle: WidgetBundle {
    var body: some Widget {
        KassaWidget()
    }
}

// MARK: - Zeitachse

struct KassaEntry: TimelineEntry {
    let date: Date
    let snapshot: KassaWidgetSnapshot?
}

/// Liefert den aktuellen Stand aus der geteilten Momentaufnahme.
///
/// Es gibt bewusst **keine** Vorausberechnung künftiger Einträge: Der Saldo
/// ändert sich nicht mit der Zeit, sondern nur, wenn jemand etwas erfasst. Die
/// App stösst dann selbst ein Neuladen an (`WidgetSnapshotWriter`).
struct KassaProvider: TimelineProvider {

    func placeholder(in context: Context) -> KassaEntry {
        KassaEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (KassaEntry) -> Void) {
        // In der Widget-Galerie zeigt iOS eine Vorschau – dort sind
        // Beispielwerte aussagekräftiger als ein leeres Widget.
        let snapshot = context.isPreview ? KassaWidgetSnapshot.placeholder : WidgetSharing.load()
        completion(KassaEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KassaEntry>) -> Void) {
        let entry = KassaEntry(date: Date(), snapshot: WidgetSharing.load())

        // Sicherheitsnetz: Sollte das Neuladen durch die App einmal ausbleiben
        // (App vom System beendet, Widget-Budget aufgebraucht), holt sich das
        // Widget den Stand spätestens in einer Stunde selbst.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Konfiguration

struct KassaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharing.widgetKind, provider: KassaProvider()) { entry in
            KassaWidgetView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(WidgetText.displayName)
        .description(WidgetText.description)
        // Nur die Sperrbildschirm-Grössen. Für den Home-Bildschirm gibt es das
        // App-Symbol – ein zusätzliches Widget dort brächte nichts Neues.
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Darstellung

struct KassaWidgetView: View {

    @Environment(\.widgetFamily) private var family
    let snapshot: KassaWidgetSnapshot?

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        default:
            rectangularView
        }
    }

    // Eine Zeile über der Uhr. Platz für sehr wenig – deshalb nur Zustand und
    // Betrag, ohne Name der Kassä.
    @ViewBuilder
    private var inlineView: some View {
        if let snapshot, let amount = snapshot.netText {
            // Erst zu einem String fügen: `Text("\(a) \(b)")` wäre ein
            // LocalizedStringKey, den SwiftUI als Schlüssel nachschlüge. Die
            // Bestandteile sind bereits fertige Texte.
            Text(statusWord(snapshot) + " " + amount)
        } else {
            Text(snapshot?.tripName ?? WidgetText.noKassa)
        }
    }

    // Rund und winzig: Symbol plus gerundete Zahl, mehr ist nicht lesbar.
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(snapshot?.netCompactText ?? WidgetText.noKassaShort)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }

    // Die grösste Sperrbildschirm-Grösse: drei Zeilen.
    @ViewBuilder
    private var rectangularView: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: symbolName)
                        .font(.caption2)
                    Text(snapshot.tripName)
                        .font(.headline)
                        .lineLimit(1)
                }

                Text(snapshot.isClosed
                     ? "\(statusWord(snapshot)) · \(WidgetText.closedSuffix)"
                     : statusWord(snapshot))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Zweite Zeile mit dem Betrag: in Kassä-Währung, dahinter CHF,
                // sofern ein Kurs vorlag. Beides zu zeigen ist der Kern der App.
                if let amount = snapshot.netText {
                    Text(chfSuffix(snapshot).isEmpty ? amount : "\(amount) · \(chfSuffix(snapshot))")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(snapshot.totalText)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(WidgetText.noKassa, systemImage: "francsign.circle")
                .font(.headline)
        }
    }

    // MARK: - Ableitungen

    private func statusWord(_ snapshot: KassaWidgetSnapshot) -> String {
        switch snapshot.standing {
        case .getsBack: return WidgetText.getsBack
        case .owes: return WidgetText.owes
        case .balanced: return WidgetText.balanced
        case .unknownPerson: return WidgetText.unknownPerson
        }
    }

    private func chfSuffix(_ snapshot: KassaWidgetSnapshot) -> String {
        snapshot.netCHFText ?? ""
    }

    /// Auf dem Sperrbildschirm werden Widgets einfarbig getönt – Farbe trägt
    /// dort keine Bedeutung. Die Richtung muss deshalb aus Symbol und Wort
    /// hervorgehen.
    private var symbolName: String {
        guard let standing = snapshot?.standing else { return "francsign.circle" }
        switch standing {
        case .getsBack: return "arrow.down.left"
        case .owes: return "arrow.up.right"
        case .balanced: return "checkmark"
        case .unknownPerson: return "person.fill.questionmark"
        }
    }
}

#Preview(as: .accessoryRectangular) {
    KassaWidget()
} timeline: {
    KassaEntry(date: .now, snapshot: .placeholder)
    KassaEntry(date: .now, snapshot: nil)
}
