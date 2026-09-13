import Foundation

/// Rechenregeln für prozentuale Aufteilungen über beliebig viele Personen.
///
/// Zwei Verwendungen:
/// * **Auslage einer Ausgabe** – wer hat wie viel davon bezahlt. Das ist die
///   einzige Aufteilung, die sich noch von Hand einstellen lässt
///   (`SplitEditorView`), weil sie im Alltag tatsächlich wechselt.
/// * **Kostenanteil der Personen** – wer trägt wie viel an den gemeinsamen
///   Ausgaben. Hier wird nur noch `equalShares(count:)` gebraucht: Geteilt wird
///   immer gleichmässig durch die Anzahl Personen.
///
/// Zentrale Zusage an die Bedienung: **Die Summe ist immer genau 100 %.**
/// Wird ein Schieber bewegt, verteilt `adjust(_:to:at:)` den Rest proportional
/// auf die übrigen Personen; 100 % können damit nie überschritten werden.
public enum SplitCalculator {

    /// Auf ganze Zehntelprozent runden – das entspricht der Schrittweite der
    /// Schieber und verhindert Nachkommastellen-Rauschen.
    static let scale = 1

    /// Gleichmässige Verteilung auf `count` Personen (Rest auf die ersten).
    ///
    /// Beispiel für 3 Personen: 33.4 / 33.3 / 33.3 – Summe exakt 100.
    public static func equalShares(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let base = (100.0 / Double(count) * 10).rounded(.down) / 10
        var result = Array(repeating: base, count: count)
        let remainder = ((100.0 - base * Double(count)) * 10).rounded() / 10
        if remainder > 0 {
            result[0] = ((base + remainder) * 10).rounded() / 10
        }
        return result
    }

    /// Setzt den Wert an Position `index` und verteilt den Rest proportional
    /// auf die übrigen Positionen, sodass die Summe genau 100 ergibt.
    ///
    /// - Bei nur einer Person ist das Ergebnis immer `[100]`.
    /// - Sind alle übrigen Werte 0, wird der Rest gleichmässig verteilt.
    public static func adjust(_ values: [Double], to newValue: Double, at index: Int) -> [Double] {
        guard values.indices.contains(index) else { return values }
        guard values.count > 1 else { return [100] }

        let target = min(max(newValue, 0), 100)
        let remaining = 100 - target

        var others = values
        others.remove(at: index)
        let othersSum = others.reduce(0, +)

        var scaled: [Double]
        if othersSum > 0 {
            scaled = others.map { $0 / othersSum * remaining }
        } else {
            let each = remaining / Double(others.count)
            scaled = Array(repeating: each, count: others.count)
        }

        var result = scaled
        result.insert(target, at: index)
        return normalise(result, keeping: index)
    }

    /// Rundet auf eine Nachkommastelle und schiebt die Rundungsdifferenz auf eine
    /// andere Position, damit die Summe exakt 100 bleibt.
    ///
    /// - Parameter keeping: Diese Position bleibt unangetastet (der eben bewegte
    ///   Schieber soll nicht unter der Hand springen).
    public static func normalise(_ values: [Double], keeping index: Int? = nil) -> [Double] {
        guard !values.isEmpty else { return [] }
        guard values.count > 1 else { return [100] }

        var result = values.map { max(0, ($0 * 10).rounded() / 10) }
        let sum = result.reduce(0, +)
        let difference = ((100 - sum) * 10).rounded() / 10

        if difference != 0 {
            // Die Differenz landet dort, wo sie am wenigsten auffällt: auf der
            // grössten Position, die nicht der eben bewegte Schieber ist.
            let candidates = result.indices.filter { $0 != index }
            if let target = candidates.max(by: { result[$0] < result[$1] }) {
                result[target] = max(0, ((result[target] + difference) * 10).rounded() / 10)
            }
        }
        return result
    }

    /// Summe einer Aufteilung (für Prüfungen und Anzeigen).
    public static func sum(_ values: [Double]) -> Double {
        (values.reduce(0, +) * 10).rounded() / 10
    }

    /// Ist die Aufteilung gültig? (Summe 100, keine negativen Werte)
    public static func isValid(_ values: [Double]) -> Bool {
        !values.contains { $0 < 0 } && abs(sum(values) - 100) < 0.05
    }
}
