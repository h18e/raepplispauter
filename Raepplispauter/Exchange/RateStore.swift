import Foundation

/// Lokaler, persistenter Kurs-Cache.
///
/// Damit die App **offline vollständig nutzbar** bleibt, werden alle je geladenen
/// Tageskurse als JSON im Application-Support-Ordner abgelegt. Beim Erfassen einer
/// Ausgabe ohne Netz wird der jüngste bekannte Kurs ≤ Erfassungsdatum verwendet
/// (die EZB publiziert ohnehin nur an Bankarbeitstagen).
///
/// Der Cache wird bewusst **nicht** über CloudKit synchronisiert: Kurse sind
/// öffentlich reproduzierbar, der pro Ausgabe verwendete Kurs ist am Datensatz
/// selbst eingefroren.
public final class RateStore {

    public static let shared = RateStore()

    private let queue = DispatchQueue(label: "ch.hebera.raepplispauter.ratestore")
    private var cache: [String: [String: Decimal]] = [:]   // day -> (currency -> rate per EUR)
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true))
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base.appendingPathComponent("ecb-rates-cache.json")
        }
        load()
    }

    // MARK: - Lesen

    /// Kurse für genau diesen Tag, falls vorhanden.
    public func rates(for day: String) -> DailyRates? {
        queue.sync {
            guard let entry = cache[day] else { return nil }
            return DailyRates(day: day, ratesPerEUR: entry)
        }
    }

    /// Jüngste vorhandene Kurse mit Tag ≤ `day` (Wochenenden/Feiertage überbrücken).
    public func latestRates(onOrBefore day: String) -> DailyRates? {
        queue.sync {
            guard let bestDay = cache.keys.filter({ $0 <= day }).max() else { return nil }
            return DailyRates(day: bestDay, ratesPerEUR: cache[bestDay] ?? [:])
        }
    }

    /// Allerjüngste bekannte Kurse, unabhängig vom Datum.
    public func newestRates() -> DailyRates? {
        queue.sync {
            guard let bestDay = cache.keys.max() else { return nil }
            return DailyRates(day: bestDay, ratesPerEUR: cache[bestDay] ?? [:])
        }
    }

    public var isEmpty: Bool { queue.sync { cache.isEmpty } }

    public var cachedDayCount: Int { queue.sync { cache.count } }

    public var newestDay: String? { queue.sync { cache.keys.max() } }

    // MARK: - Schreiben

    public func store(_ days: [DailyRates]) {
        queue.sync {
            for day in days {
                cache[day.day] = day.ratesPerEUR
            }
            persist()
        }
    }

    public func removeAll() {
        queue.sync {
            cache = [:]
            persist()
        }
    }

    // MARK: - Persistenz (Decimal als String, damit exakt)

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return }
        var restored: [String: [String: Decimal]] = [:]
        for (day, rates) in raw {
            var converted: [String: Decimal] = [:]
            for (currency, value) in rates {
                if let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) {
                    converted[currency] = decimal
                }
            }
            restored[day] = converted
        }
        cache = restored
    }

    private func persist() {
        var raw: [String: [String: String]] = [:]
        for (day, rates) in cache {
            raw[day] = rates.mapValues { "\($0)" }
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
