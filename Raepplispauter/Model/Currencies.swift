import Foundation

/// Auswahl der unterstützten Währungen.
///
/// Bewusst begrenzt auf jene Währungen, für die die **EZB** täglich einen
/// Referenzkurs publiziert (Feed `eurofxref-daily.xml`), plus EUR selbst.
/// Nur so ist eine Umrechnung in CHF überhaupt möglich; andere Währungen
/// müssten manuell erfasst werden und würden stillschweigend falsche
/// CHF-Werte erzeugen.
public enum Currencies {

    /// ISO-4217-Codes aller von der EZB publizierten Währungen (Stand Referenzkurs-Feed).
    public static let supported: [String] = [
        "CHF", "EUR", "USD", "GBP",
        "AUD", "BGN", "BRL", "CAD", "CNY", "CZK", "DKK", "HKD", "HUF",
        "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "ZAR"
    ]

    /// Referenzwährung der App – alle Bilanzen laufen zusätzlich immer in CHF.
    public static let home = "CHF"

    /// Basiswährung des EZB-Feeds.
    public static let ecbBase = "EUR"

    /// Häufig gebrauchte Ferienwährungen zuoberst, Rest alphabetisch.
    public static var pickerOrder: [String] {
        let favourites = ["EUR", "CHF", "USD", "GBP", "SEK", "NOK", "DKK", "CZK", "PLN", "HUF"]
        let rest = supported.filter { !favourites.contains($0) }.sorted()
        return favourites.filter { supported.contains($0) } + rest
    }

    /// Lokalisierter Klartextname, z. B. "EUR – Euro".
    public static func displayName(_ code: String) -> String {
        let locale = Locale(identifier: "de_CH")
        if let name = locale.localizedString(forCurrencyCode: code) {
            return "\(code) – \(name)"
        }
        return code
    }

    public static func isSupported(_ code: String) -> Bool {
        supported.contains(code.uppercased())
    }
}
