import Foundation

/// Ergebnis einer Währungsumrechnung – wird 1:1 auf einer `Expense` eingefroren.
public struct CurrencyConversion: Equatable, Sendable {
    public let originalAmount: Decimal
    public let originalCurrency: String
    public let tripCurrency: String
    /// Betrag in der Reisewährung (2 Nachkommastellen).
    public let amountInTripCurrency: Decimal
    /// Betrag in CHF, auf 5 Rappen gerundet.
    public let amountInCHF: Decimal
    /// Verwendeter Kurs Ausgabewährung → CHF (inkl. allfälligem Aufschlag).
    public let rateToCHF: Decimal
    /// Verwendeter Kurs Reisewährung → CHF (inkl. allfälligem Aufschlag).
    public let rateTripToCHF: Decimal
    public let rateDate: Date
    public let source: RateSource
    /// true = es lag kein Kurs vor; der CHF-Betrag ist nicht belastbar und wird
    /// weder in der Bilanz noch in der Abrechnung mitgezählt.
    public let isProvisional: Bool
}

/// Anbindung an die Wechselkursdaten der Europäischen Zentralbank.
///
/// ## Datenquelle
/// Die EZB stellt ihre Referenzkurse als offenen XML-Feed bereit (kein API-Key):
///
/// | Feed | URL | Inhalt |
/// |------|-----|--------|
/// | Tageskurse | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` | letzter Bankarbeitstag |
/// | 90 Tage | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml` | letzte 90 Tage |
///
/// Alle Kurse sind **gegen EUR** notiert; Fremdwährung → CHF wird als Kreuzkurs
/// über EUR gerechnet (siehe `DailyRates.crossRate`).
///
/// ## Kursbegriff (wichtig)
/// Die EZB publiziert **Referenz-/Mittelkurse**, keine Bank-Verkaufskurse. Um den
/// in der Spezifikation gewünschten "Verkaufskurs" abzubilden, wird ein
/// konfigurierbarer Aufschlag `AppSettings.rateMarkupPercent` (Standard 0 %)
/// auf den Mittelkurs gerechnet. Der effektiv verwendete Kurs, das Kursdatum und
/// die Quelle werden pro Ausgabe gespeichert und sind im CSV-Export sichtbar.
///
/// ## Offline-Verhalten (PLATZHALTER-Regelung)
/// 1. Kurs des Erfassungstages im Cache → wird verwendet (`.ecbLive`/`.ecbCached`)
/// 2. Sonst jüngster Kurs ≤ Erfassungstag (Wochenende/Feiertag) → `.ecbCached`
/// 3. Gar kein Kurs (Erstinstallation ohne Netz) → **Platzhalter**: die Ausgabe wird
///    mit `isProvisional = true` gespeichert, in der UI markiert ("Kurs fählt no")
///    und aus der CHF-Bilanz herausgehalten. Sobald wieder Kurse verfügbar sind,
///    füllt `RateBackfillService` diese Ausgaben automatisch nach.
///    Es wird **nie** stillschweigend ein erfundener Kurs verwendet.
public final class ExchangeRateService {

    public static let shared = ExchangeRateService()

    public static let dailyFeedURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    public static let historyFeedURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!

    private let store: RateStore
    private let session: URLSession
    private let markupProvider: () -> Decimal

    public init(store: RateStore = .shared,
                session: URLSession = .shared,
                markupProvider: @escaping () -> Decimal = { AppSettings.rateMarkupPercent }) {
        self.store = store
        self.session = session
        self.markupProvider = markupProvider
    }

    // MARK: - Kurse laden

    /// Lädt Kurse von der EZB und legt sie im Cache ab.
    ///
    /// Ist der Cache leer, wird der 90-Tage-Feed geholt (damit auch rückwirkend
    /// erfasste Ausgaben einen korrekten Tageskurs bekommen), sonst der Tagesfeed.
    @discardableResult
    public func refreshRates(forceHistory: Bool = false) async throws -> Int {
        let url = (forceHistory || store.isEmpty) ? Self.historyFeedURL : Self.dailyFeedURL
        let data: Data
        do {
            let (payload, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ExchangeRateError.network("HTTP \(http.statusCode)")
            }
            data = payload
        } catch let error as ExchangeRateError {
            throw error
        } catch {
            throw ExchangeRateError.network(error.localizedDescription)
        }

        let days = try ECBRatesParser().parse(data: data)
        store.store(days)
        AppSettings.lastRateRefresh = Date()
        return days.count
    }

    // MARK: - Umrechnen

    /// Rechnet einen Betrag in Reisewährung **und** CHF um.
    ///
    /// Fehlt der Kurs des gewünschten Tages im Cache, wird einmalig ein
    /// Netzabruf versucht (`allowNetwork`). Schlägt auch das fehl, greift die
    /// oben beschriebene Offline-Regelung.
    public func convert(amount: Decimal,
                        from currency: String,
                        tripCurrency: String,
                        on date: Date,
                        allowNetwork: Bool = true) async -> CurrencyConversion {
        let day = Self.dayKey(for: date)

        var lookup = resolveRates(for: day)
        if lookup == nil && allowNetwork {
            _ = try? await refreshRates()
            lookup = resolveRates(for: day)
        }

        guard let lookup else {
            return placeholderConversion(amount: amount,
                                         currency: currency,
                                         tripCurrency: tripCurrency,
                                         date: date)
        }
        let rates = lookup.rates
        let source = lookup.source

        let markup = markupProvider()
        guard let midToCHF = rates.crossRate(from: currency, to: Currencies.home),
              let midTripToCHF = rates.crossRate(from: tripCurrency, to: Currencies.home),
              let midToTrip = rates.crossRate(from: currency, to: tripCurrency) else {
            return placeholderConversion(amount: amount,
                                         currency: currency,
                                         tripCurrency: tripCurrency,
                                         date: date)
        }

        // Aufschlag nur auf den CHF-Kursen: er bildet die Differenz zwischen
        // EZB-Mittelkurs und Bank-Verkaufskurs beim CHF-Bezug ab.
        let rateToCHF = applyMarkup(midToCHF, markup: markup, identical: currency.uppercased() == Currencies.home)
        let rateTripToCHF = applyMarkup(midTripToCHF, markup: markup, identical: tripCurrency.uppercased() == Currencies.home)

        let amountTrip = Money.round(amount * midToTrip, scale: 2)
        let amountCHF = Money.roundToFiveRappen(amount * rateToCHF)

        let effectiveSource: RateSource
        if currency.uppercased() == Currencies.home && tripCurrency.uppercased() == Currencies.home {
            effectiveSource = .identity
        } else {
            effectiveSource = source
        }

        return CurrencyConversion(originalAmount: amount,
                                  originalCurrency: currency.uppercased(),
                                  tripCurrency: tripCurrency.uppercased(),
                                  amountInTripCurrency: amountTrip,
                                  amountInCHF: amountCHF,
                                  rateToCHF: rateToCHF,
                                  rateTripToCHF: rateTripToCHF,
                                  rateDate: Self.date(fromDay: rates.day) ?? date,
                                  source: effectiveSource,
                                  isProvisional: false)
    }

    /// Synchrone Variante rein aus dem Cache – für Vorschauen während der Eingabe.
    public func convertFromCache(amount: Decimal,
                                 from currency: String,
                                 tripCurrency: String,
                                 on date: Date) -> CurrencyConversion? {
        let day = Self.dayKey(for: date)
        guard let lookup = resolveRates(for: day) else { return nil }
        let rates = lookup.rates
        let source = lookup.source

        guard let midToCHF = rates.crossRate(from: currency, to: Currencies.home),
              let midTripToCHF = rates.crossRate(from: tripCurrency, to: Currencies.home),
              let midToTrip = rates.crossRate(from: currency, to: tripCurrency) else { return nil }

        let markup = markupProvider()
        let rateToCHF = applyMarkup(midToCHF, markup: markup, identical: currency.uppercased() == Currencies.home)
        let rateTripToCHF = applyMarkup(midTripToCHF, markup: markup, identical: tripCurrency.uppercased() == Currencies.home)

        return CurrencyConversion(originalAmount: amount,
                                  originalCurrency: currency.uppercased(),
                                  tripCurrency: tripCurrency.uppercased(),
                                  amountInTripCurrency: Money.round(amount * midToTrip, scale: 2),
                                  amountInCHF: Money.roundToFiveRappen(amount * rateToCHF),
                                  rateToCHF: rateToCHF,
                                  rateTripToCHF: rateTripToCHF,
                                  rateDate: Self.date(fromDay: rates.day) ?? date,
                                  source: source,
                                  isProvisional: false)
    }

    // MARK: - Intern

    /// Gefundene Kurse samt Herkunft.
    private struct RateLookup {
        let rates: DailyRates
        let source: RateSource
    }

    /// Kurse für einen Tag: exakter Treffer → `.ecbLive`, sonst jüngerer Tag davor → `.ecbCached`.
    private func resolveRates(for day: String) -> RateLookup? {
        if let exact = store.rates(for: day) {
            return RateLookup(rates: exact, source: .ecbLive)
        }
        if let earlier = store.latestRates(onOrBefore: day) {
            return RateLookup(rates: earlier, source: .ecbCached)
        }
        // Ausgabe liegt vor dem ältesten bekannten Kurs (z. B. Reise nachträglich
        // erfasst): dann der jüngste bekannte Kurs, klar als Cache markiert.
        if let newest = store.newestRates() {
            return RateLookup(rates: newest, source: .ecbCached)
        }
        return nil
    }

    private func applyMarkup(_ rate: Decimal, markup: Decimal, identical: Bool) -> Decimal {
        guard !identical, markup != 0 else { return rate }
        return rate * (1 + markup / 100)
    }

    /// Platzhalter, wenn überhaupt kein Kurs verfügbar ist.
    private func placeholderConversion(amount: Decimal,
                                       currency: String,
                                       tripCurrency: String,
                                       date: Date) -> CurrencyConversion {
        let isCHF = currency.uppercased() == Currencies.home

        // Ohne Kurs bleibt der Betrag unverändert stehen (bei gleicher Währung ist
        // das korrekt, sonst provisorisch und entsprechend markiert).
        return CurrencyConversion(originalAmount: amount,
                                  originalCurrency: currency.uppercased(),
                                  tripCurrency: tripCurrency.uppercased(),
                                  amountInTripCurrency: Money.round(amount, scale: 2),
                                  amountInCHF: isCHF ? Money.roundToFiveRappen(amount) : 0,
                                  rateToCHF: isCHF ? 1 : 0,
                                  rateTripToCHF: tripCurrency.uppercased() == Currencies.home ? 1 : 0,
                                  rateDate: date,
                                  source: isCHF ? .identity : .unavailable,
                                  // Nur wenn der CHF-Betrag wirklich unbekannt ist,
                                  // gilt die Ausgabe als provisorisch.
                                  isProvisional: !isCHF)
    }

    // MARK: - Datumsschlüssel

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Tagesschlüssel im lokalen Kalender – passend zu den Kalendertagen des EZB-Feeds.
    public static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func date(fromDay day: String) -> Date? {
        dayFormatter.date(from: day)
    }
}
