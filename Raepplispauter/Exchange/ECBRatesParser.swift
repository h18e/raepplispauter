import Foundation

/// Tageskurse der EZB, immer **gegen EUR** (Basiswährung des Feeds).
///
/// `ratesPerEUR["CHF"] = 0.9412` bedeutet: 1 EUR = 0.9412 CHF.
public struct DailyRates: Equatable, Sendable {
    public let day: String          // "yyyy-MM-dd" (UTC)
    public let ratesPerEUR: [String: Decimal]

    public init(day: String, ratesPerEUR: [String: Decimal]) {
        self.day = day
        var rates = ratesPerEUR
        rates[Currencies.ecbBase] = 1     // EUR gegen sich selbst
        self.ratesPerEUR = rates
    }

    /// Kreuzkurs `from` → `to`, gerechnet über EUR.
    ///
    /// Beispiel USD → CHF:  `CHF_pro_EUR / USD_pro_EUR`
    public func crossRate(from: String, to: String) -> Decimal? {
        let source = from.uppercased()
        let target = to.uppercased()
        if source == target { return 1 }
        guard let sourcePerEUR = ratesPerEUR[source],
              let targetPerEUR = ratesPerEUR[target],
              sourcePerEUR != 0 else { return nil }
        return targetPerEUR / sourcePerEUR
    }
}

/// Parser für die XML-Referenzkurse der Europäischen Zentralbank.
///
/// **Datenquelle** (offen, kein API-Key, keine Registrierung nötig):
/// * Tageskurse:  https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml
/// * 90 Tage:     https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml
///
/// Struktur:
/// ```xml
/// <Cube>
///   <Cube time='2026-09-02'>
///     <Cube currency='USD' rate='1.0812'/>
///     <Cube currency='CHF' rate='0.9412'/>
///   </Cube>
/// </Cube>
/// ```
///
/// **Hinweis zum Kursbegriff:** Die EZB publiziert *Referenzkurse* (Mittelkurse,
/// täglich um ca. 16:00 MEZ), keine Verkaufskurse einer Bank. Ein Verkaufskurs
/// wird in `ExchangeRateService` über einen konfigurierbaren Aufschlag
/// (`AppSettings.rateMarkupPercent`, Standard 0 %) nachgebildet.
public final class ECBRatesParser: NSObject, XMLParserDelegate {

    private var days: [DailyRates] = []
    private var currentDay: String?
    private var currentRates: [String: Decimal] = [:]

    /// Parst einen EZB-Feed. Liefert alle enthaltenen Tage (Daily-Feed: genau einen).
    public func parse(data: Data) throws -> [DailyRates] {
        days = []
        currentDay = nil
        currentRates = [:]

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw ExchangeRateError.malformedFeed(parser.parserError?.localizedDescription ?? "XML")
        }
        flushCurrentDay()
        guard !days.isEmpty else { throw ExchangeRateError.malformedFeed("keine Kurse gefunden") }
        return days
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Cube" || qName == "Cube" else { return }

        if let time = attributeDict["time"] {
            flushCurrentDay()
            currentDay = time
            currentRates = [:]
        } else if let currency = attributeDict["currency"],
                  let rateString = attributeDict["rate"],
                  let rate = Decimal(string: rateString, locale: Locale(identifier: "en_US_POSIX")) {
            currentRates[currency.uppercased()] = rate
        }
    }

    private func flushCurrentDay() {
        if let day = currentDay, !currentRates.isEmpty {
            days.append(DailyRates(day: day, ratesPerEUR: currentRates))
        }
        currentDay = nil
        currentRates = [:]
    }
}

public enum ExchangeRateError: LocalizedError {
    case malformedFeed(String)
    case unsupportedCurrency(String)
    case noRateAvailable(currency: String, day: String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .malformedFeed(let detail):
            return L.errorFeedMalformed(detail)
        case .unsupportedCurrency(let code):
            return L.errorUnsupportedCurrency(code)
        case .noRateAvailable(let currency, let day):
            return L.errorNoRate(currency, day)
        case .network(let detail):
            return L.errorNetwork(detail)
        }
    }
}
