import SwiftUI

/// Prozentuale Aufteilung über beliebig viele Personen – mit einem Schieber je Person.
///
/// Wird zweimal verwendet:
/// * **Kostenschlüssel der Reise** – wer trägt welchen Anteil
/// * **Auslage einer Ausgabe** – wer hat wie viel bezahlt
///
/// Die Summe bleibt **immer genau 100 %**: Wird ein Schieber bewegt, verteilt
/// `SplitCalculator` den Rest proportional auf die übrigen Personen. Über 100 %
/// zu kommen ist damit gar nicht möglich – es braucht keine Fehlermeldung.
struct SplitEditorView: View {

    let participants: [ParticipantSnapshot]
    @Binding var percentages: [Double]

    /// Optionale Betragsvorschau je Person (z. B. "EUR 24.00").
    var amountText: ((Int) -> String?)?
    var isEnabled = true

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(L.splitTotal)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Money.formatPlain(Decimal(SplitCalculator.sum(percentages)), fractionDigits: 1)) %")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)

                if isEnabled && participants.count > 1 {
                    Button(L.splitEqualise) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            percentages = SplitCalculator.equalShares(count: participants.count)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .padding(.leading, 4)
                }
            }

            ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.participantColor(participant.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(participant.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let amountText, let text = amountText(index) {
                            Text(text)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text("\(Money.formatPlain(Decimal(value(at: index)), fractionDigits: 1)) %")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 58, alignment: .trailing)
                    }

                    // Bewusst OHNE `step`: Der Schieber würde sonst auf ganze
                    // Prozent einrasten, während `SplitCalculator` Zehntel
                    // zurückgibt (33.3 % bei drei Personen). Schieber und Wert
                    // würden sich dann gegenseitig immer wieder korrigieren –
                    // eine Endlosschleife, die die Oberfläche einfriert.
                    Slider(value: binding(for: index), in: 0...100)
                        .tint(Theme.participantColor(participant.colorIndex))
                        .disabled(!isEnabled || participants.count < 2)
                }
            }
        }
    }

    // MARK: - Werte

    private func value(at index: Int) -> Double {
        percentages.indices.contains(index) ? percentages[index] : 0
    }

    /// Beim Verschieben wird der Rest proportional auf die übrigen Personen
    /// verteilt – dadurch bleibt die Summe exakt 100 %.
    private func binding(for index: Int) -> Binding<Double> {
        Binding(
            get: { value(at: index) },
            set: { newValue in
                // Schreibsperre bei unveränderten Werten: Ohne sie löst jedes
                // Neuzeichnen ein weiteres Neuzeichnen aus, und die Ansicht
                // kommt nie zur Ruhe.
                guard abs(newValue - value(at: index)) > 0.05 else { return }
                percentages = SplitCalculator.adjust(percentages, to: newValue, at: index)
            }
        )
    }
}

#Preview {
    struct Wrapper: View {
        @State private var values: [Double] = [40, 35, 25]
        private let people = [
            ParticipantSnapshot(id: UUID(), name: "Anna", costSharePercent: 40, colorIndex: 0),
            ParticipantSnapshot(id: UUID(), name: "Beat", costSharePercent: 35, colorIndex: 1),
            ParticipantSnapshot(id: UUID(), name: "Cem", costSharePercent: 25, colorIndex: 2)
        ]

        var body: some View {
            SplitEditorView(participants: people, percentages: $values)
                .padding()
                .screenBackground()
        }
    }
    return Wrapper().preferredColorScheme(.dark)
}
