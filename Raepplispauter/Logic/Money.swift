import Foundation

/// Rundungs- und Formatierungsregeln für Geldbeträge.
///
/// Grundsatz: gerechnet wird immer mit `Decimal` (keine Fliesskomma-Fehler),
/// gerundet wird erst beim Festschreiben eines Betrags.
public enum Money {

    /// Kleinste Schweizer Münzeinheit: 5 Rappen = 0.05 CHF.
    public static let chfCashIncrement = Decimal(string: "0.05")!

    // MARK: - Rundung

    /// Rundet auf 5 Rappen (kaufmännisch, halbe Schritte aufwärts).
    ///
    /// Vorgehen: Betrag × 20 → auf ganze Zahl runden → ÷ 20.
    /// Beispiel: 12.34 → 246.8 → 247 → 12.35
    public static func roundToFiveRappen(_ value: Decimal) -> Decimal {
        var scaled = value * 20
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded / 20
    }

    /// Kaufmännische Rundung auf eine feste Anzahl Nachkommastellen.
    public static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return rounded
    }

    /// Rundung passend zur Währung: CHF auf 5 Rappen, alles andere auf 2 Stellen.
    public static func roundForCurrency(_ value: Decimal, currencyCode: String) -> Decimal {
        currencyCode.uppercased() == Currencies.home
            ? roundToFiveRappen(value)
            : round(value, scale: 2)
    }

    // MARK: - Formatierung

    /// Schweizer Formatierung, z. B. "EUR 1'234.55".
    public static func format(_ value: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "de_CH")
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positiveFormat = "¤ #,##0.00"
        formatter.negativeFormat = "-¤ #,##0.00"
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(currencyCode) \(value)"
    }

    /// Reine Zahl ohne Währungscode, z. B. "1'234.55".
    public static func formatPlain(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_CH")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Wechselkurse werden mit 6 Stellen dargestellt (EZB-Feed liefert 4–5).
    public static func formatRate(_ value: Decimal) -> String {
        formatPlain(value, fractionDigits: 6)
    }

    /// Für CSV: Punkt als Dezimaltrennzeichen, keine Gruppierung.
    public static func csvNumber(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Parst eine Benutzereingabe ("12.50", "12,50") in ein `Decimal`.
    public static func parse(_ text: String) -> Decimal? {
        let normalised = text
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalised.isEmpty else { return nil }
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func isZero(_ value: Decimal) -> Bool {
        abs(value) < Decimal(string: "0.005")!
    }
}
