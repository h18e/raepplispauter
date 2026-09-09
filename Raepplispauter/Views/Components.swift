import SwiftUI

/// Überschrift eines Abschnitts im App-Stil.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .kerning(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Betrag in **Reisewährung und CHF** – die Doppelanzeige ist in der ganzen App Pflicht.
struct DualAmountView: View {
    let tripAmount: Decimal
    let tripCurrency: String
    let chfAmount: Decimal?
    var alignment: HorizontalAlignment = .trailing
    var primaryFont: Font = .body.weight(.semibold)
    var colorise = false

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(Money.format(tripAmount, currencyCode: tripCurrency))
                .font(primaryFont)
                .foregroundStyle(colorise ? Theme.amountColor(tripAmount) : Theme.textPrimary)
                .monospacedDigit()

            if tripCurrency.uppercased() != Currencies.home {
                if let chfAmount {
                    Text(Money.format(chfAmount, currencyCode: Currencies.home))
                        .font(.caption)
                        .foregroundStyle(colorise ? Theme.amountColor(chfAmount).opacity(0.8) : Theme.textSecondary)
                        .monospacedDigit()
                } else {
                    Text(L.expenseProvisionalBadge)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }
}

/// Kleine farbige Markierung, z. B. "Teilt" oder "Kurs fählt".
struct BadgeView: View {
    let text: String
    var color: Color = Theme.accent
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Personen-Marke mit Farbpunkt.
struct ParticipantChip: View {
    let participant: ParticipantSnapshot
    var trailingText: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.participantColor(participant.colorIndex))
                .frame(width: 7, height: 7)
            Text(participant.name)
                .lineLimit(1)
            if let trailingText {
                Text(trailingText)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Zeile mit Beschriftung links und Wert rechts.
struct LabeledValueRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            value
        }
    }
}

/// Leerer Zustand mit Symbol, Text und optionaler Aktion.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

/// Waagrechter Balken für die Auswertung (bewusst ohne Chart-Framework,
/// damit die Darstellung im Dark Mode exakt kontrollierbar bleibt).
struct BarRow: View {
    let title: String
    let symbolName: String?
    let color: Color
    let fraction: Double
    let primaryText: String
    let secondaryText: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.footnote)
                        .foregroundStyle(color)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(primaryText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if let secondaryText {
                        Text(secondaryText)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

/// Kompakte Zeile für eine Ausgabe (Logbuch und Bilanz-Vorschau).
struct ExpenseRow: View {
    let snapshot: ExpenseSnapshot
    let tripCurrency: String
    let participants: [ParticipantSnapshot]

    private var payerText: String {
        if let singleID = snapshot.singlePayerID {
            return participants.first { $0.id == singleID }?.name ?? L.participantUnnamed
        }
        let names = participants
            .filter { (snapshot.paymentPercentages[$0.id] ?? 0) > 0 }
            .map(\.name)
        return names.isEmpty ? L.payerShared : names.joined(separator: " + ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.categoryColor(snapshot.categoryColorIndex).opacity(0.18))
                Image(systemName: snapshot.categorySymbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.categoryColor(snapshot.categoryColorIndex))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.note.isEmpty ? snapshot.categoryName : snapshot.note)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Formatters.dateOnly.string(from: snapshot.date))
                    Text("·")
                    Text(payerText)
                        .lineLimit(1)
                    if snapshot.isRateProvisional {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                DualAmountView(tripAmount: snapshot.amountTrip,
                               tripCurrency: tripCurrency,
                               chfAmount: snapshot.amountCHF)
                if snapshot.currencyCode.uppercased() != tripCurrency.uppercased() {
                    Text(Money.format(snapshot.amountOriginal, currencyCode: snapshot.currencyCode))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
