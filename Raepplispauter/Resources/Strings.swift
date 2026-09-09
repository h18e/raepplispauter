import Foundation

/// Zentrale Sammlung **aller** UI-Texte (Bärndütsch).
///
/// Aufbau: Jeder Text ist über `String(localized:defaultValue:)` an den String-Katalog
/// `Localizable.xcstrings` angebunden. Der Schlüssel ist stabil, der bärndütsche Text
/// steht als `defaultValue` direkt daneben – so bleibt die App auch dann vollständig
/// beschriftet, wenn der Katalog (noch) keinen Eintrag hat.
///
/// Neue Texte **immer hier** ergänzen, nie direkt in einer View schreiben.
/// Danach `Tools/generate-xcstrings.py` laufen lassen, um den Katalog nachzuführen.
public enum L {

    private static func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value)
    }

    // MARK: - Allgemein

    public static let appName = t("app.name", "Räpplispauter")
    public static let save = t("common.save", "Spichere")
    public static let cancel = t("common.cancel", "Abbräche")
    public static let delete = t("common.delete", "Lösche")
    public static let edit = t("common.edit", "Bearbeite")
    public static let done = t("common.done", "Fertig")
    public static let close = t("common.close", "Zue")
    public static let ok = t("common.ok", "Guet")
    public static let retry = t("common.retry", "Nomal probiere")
    public static let refresh = t("common.refresh", "Aktualisiere")
    public static let total = t("common.total", "Total")
    public static let errorTitle = t("common.errorTitle", "Öppis isch schiefgloffe")

    // MARK: - Tabs

    public static let tabBalance = t("tab.balance", "Bilanz")
    public static let tabLogbook = t("tab.logbook", "Logbuech")
    public static let tabAnalysis = t("tab.analysis", "Uswertig")
    public static let tabSettlement = t("tab.settlement", "Abrächnig")
    public static let tabTrips = t("tab.trips", "Reise")

    // MARK: - Kategorien

    /// Startsatz beim Anlegen einer Reise – frei erweiterbar und löschbar.
    public static let categoryUnterkunft = t("category.unterkunft", "Unterkunft")
    public static let categoryRestaurant = t("category.restaurant", "Restaurant")
    public static let categoryLebensmittel = t("category.lebensmittel", "Läbesmittel")
    public static let categoryOev = t("category.oev", "ÖV")
    public static let categoryAuto = t("category.auto", "Outo")
    public static let categorySightseeing = t("category.sightseeing", "Sightseeing")

    public static let categoriesTitle = t("categories.title", "Kategorie")
    public static let categoriesHint = t("categories.hint",
                                         "D Kategorie ghöre zur Reis und wärde mit em Teile automatisch mitgnoh.")
    public static let categoriesDeleteHint = t("categories.deleteHint",
                                               "Zum Lösche nach links wüsche. Kategorie, wo scho bruucht wärde, chöi nid glöscht wärde.")
    public static let categoryNew = t("category.new", "Nöii Kategorie")
    public static let categoryEdit = t("category.edit", "Kategorie bearbeite")
    public static let categoryName = t("category.name", "Name")
    public static let categoryNamePlaceholder = t("category.namePlaceholder", "z. B. Souvenir")
    public static let categoryColor = t("category.color", "Farb")
    public static let categorySymbol = t("category.symbol", "Symbol")
    public static let categoryUnnamed = t("category.unnamed", "Ohni Kategorie")
    public static let categoryNeedsOne = t("category.needsOne", "S muess mindestens ei Kategorie blybe.")

    public static func categoryDeleteBlocked(_ names: String) -> String {
        String(localized: "category.deleteBlocked",
               defaultValue: "Die Kategorie wärde no bruucht und chöi drum nid glöscht wärde: \(names)")
    }

    // MARK: - Persone

    public static let participantUnnamed = t("participant.unnamed", "Ohni Name")
    public static let participantAdd = t("participant.add", "Person zuefüege")
    public static let participantNamePlaceholder = t("participant.namePlaceholder", "Name")
    public static let participantNeedsOne = t("participant.needsOne", "S bruucht mindestens ei Person mit eme Name.")

    public static func participantPlaceholderNumbered(_ number: Int) -> String {
        String(localized: "participant.placeholderNumbered", defaultValue: "Person \(number)")
    }

    public static func participantDeleteBlocked(_ names: String) -> String {
        String(localized: "participant.deleteBlocked",
               defaultValue: "Die Persone hei scho Uusgabe und chöi drum nid glöscht wärde: \(names)")
    }

    // MARK: - Zahler und Ufteilig

    public static let payerShared = t("payer.shared", "Gmeinsam")
    public static let payerQuestion = t("payer.question", "Wär het zahlt?")
    public static let splitTotal = t("split.total", "Total")
    public static let splitEqualise = t("split.equalise", "Glychmässig")

    // MARK: - Bilanz

    public static let balanceTitle = t("balance.title", "Bilanz")
    public static let balanceNoTrip = t("balance.noTrip", "No kei Reis erfasst")
    public static let balanceNoTripHint = t("balance.noTripHint",
                                            "Legg zerscht e Reis a, de chasch drufabe Uusgabe erfasse.")
    public static let balanceCreateTrip = t("balance.createTrip", "Nöii Reis erstelle")
    public static let balanceEven = t("balance.even", "Alles usglyche – niemer schuldet öppis.")
    public static let balancePaid = t("balance.paid", "Uusgleit")
    public static let balanceShare = t("balance.share", "Aateil")
    public static let balanceNet = t("balance.net", "Saldo")
    public static let balanceTotalExpenses = t("balance.totalExpenses", "Total Uusgabe")
    public static let balanceInTripCurrency = t("balance.inTripCurrency", "I dr Reisewärig")
    public static let balanceInCHF = t("balance.inCHF", "I Franke")
    public static let balanceRecent = t("balance.recent", "Letschti Uusgabe")
    public static let balanceShowAll = t("balance.showAll", "Alli zeige")
    public static let balanceNoExpenses = t("balance.noExpenses", "No kei Uusgabe i dere Reis.")
    public static let balanceNoParticipants = t("balance.noParticipants",
                                                "Für die Reis si no kei Persone erfasst.")


    public static func balanceMissingRates(_ count: Int) -> String {
        String(localized: "balance.missingRates",
               defaultValue: "\(count) Uusgabe ohni Wächselkurs – die si i dr CHF-Bilanz no nid drin.")
    }

    // MARK: - Uusgab erfasse

    public static let expenseNewTitle = t("expense.newTitle", "Nöii Uusgab")
    public static let expenseEditTitle = t("expense.editTitle", "Uusgab bearbeite")
    public static let expenseAmount = t("expense.amount", "Betrag")
    public static let expenseCurrency = t("expense.currency", "Wärig")
    public static let expenseCategory = t("expense.category", "Kategorie")
    public static let expensePurpose = t("expense.purpose", "Verwändigszwäck")
    public static let expensePurposePlaceholder = t("expense.purposePlaceholder", "z. B. Znacht im Städtli")
    public static let expenseSplitHint = t("expense.splitHint",
                                           "Wär het wie viel usgleit? D Summe isch immer 100 % – verschiebsch eine, passe sich di andere a.")
    public static let expenseDateTime = t("expense.dateTime", "Datum & Zyt")
    public static let expenseConversion = t("expense.conversion", "Umrächnig")
    public static let expenseRate = t("expense.rate", "Kurs")
    public static let expenseRateDate = t("expense.rateDate", "Kursdatum")
    public static let expenseRateSourceLabel = t("expense.rateSourceLabel", "Kursquelle")
    public static let expenseNoRate = t("expense.noRate",
                                        "Kei Kurs verfüegbar – d Uusgab wird gspicheret u dr Kurs wird automatisch nachträit, sobald wieder Netz da isch.")
    public static let expenseAmountInvalid = t("expense.amountInvalid", "Bitte gib e gültige Betrag i.")
    public static let expenseDeleteConfirm = t("expense.deleteConfirm", "Die Uusgab würklech lösche?")
    public static let expenseFallbackName = t("expense.fallbackName", "Uusgab")
    public static let expenseProvisionalBadge = t("expense.provisionalBadge", "Kurs fählt")

    // MARK: - Logbuech

    public static let logbookTitle = t("logbook.title", "Logbuech")
    public static let logbookEmpty = t("logbook.empty", "No kei Uusgabe erfasst.")
    public static let logbookEmptyFiltered = t("logbook.emptyFiltered", "Kei Uusgabe zu dene Filter.")
    public static let logbookFilter = t("logbook.filter", "Filter")
    public static let logbookSort = t("logbook.sort", "Sortiere")
    public static let logbookSortDateDesc = t("logbook.sortDateDesc", "Nöischti zerscht")
    public static let logbookSortDateAsc = t("logbook.sortDateAsc", "Elteschti zerscht")
    public static let logbookSortAmountDesc = t("logbook.sortAmountDesc", "Grösste Betrag zerscht")
    public static let logbookSortAmountAsc = t("logbook.sortAmountAsc", "Chlynschte Betrag zerscht")
    public static let logbookAllCategories = t("logbook.allCategories", "Alli Kategorie")
    public static let logbookAllPayers = t("logbook.allPayers", "Alli Zahler")
    public static let logbookResetFilter = t("logbook.resetFilter", "Filter zrüggsetze")

    public static func logbookCount(_ count: Int) -> String {
        String(localized: "logbook.count", defaultValue: "\(count) Uusgabe")
    }

    // MARK: - Uswertig

    public static let analysisTitle = t("analysis.title", "Uswertig")
    public static let analysisByCategory = t("analysis.byCategory", "Nach Kategorie")
    public static let analysisByPayer = t("analysis.byPayer", "Nach Zahler")
    public static let analysisEmpty = t("analysis.empty", "No nüt z uswerte.")
    public static let analysisSharePercent = t("analysis.sharePercent", "Aateil")
    public static let analysisByPayerHint = t("analysis.byPayerHint", "Wär het wie viel usgleit")

    // MARK: - Abrächnig

    public static let settlementTitle = t("settlement.title", "Abrächnig")
    public static let settlementFinal = t("settlement.final", "Schlussabrächnig")
    public static let settlementBalanced = t("settlement.balanced", "Alles usglyche")
    public static let settlementExport = t("settlement.export", "CSV exportiere")
    public static let settlementExportFailed = t("settlement.exportFailed", "Dr Export het nid klappet.")
    public static let settlementCloseTrip = t("settlement.closeTrip", "Reis abschlüsse")
    public static let settlementReopenTrip = t("settlement.reopenTrip", "Reis wieder ufmache")
    public static let settlementClosedNotice = t("settlement.closedNotice", "Die Reis isch abgschlosse.")
    public static let settlementDetails = t("settlement.details", "Detail")
    public static let settlementCloseConfirm = t("settlement.closeConfirm",
                                                 "Reis abschlüsse? Drufabe chasch kei Uusgabe meh erfasse, ändere oder lösche.")

    // MARK: - Reise

    public static let tripsTitle = t("trips.title", "Reise")
    public static let tripsActive = t("trips.active", "Aktivi Reise")
    public static let tripsClosed = t("trips.closed", "Abgschlosseni Reise")
    public static let tripsEmpty = t("trips.empty", "No kei Reise aagleit.")
    public static let tripNew = t("trip.new", "Nöii Reis")
    public static let tripEditTitle = t("trip.editTitle", "Reis bearbeite")
    public static let tripName = t("trip.name", "Name")
    public static let tripNamePlaceholder = t("trip.namePlaceholder", "z. B. Toskana 2026")
    public static let tripPeriod = t("trip.period", "Zytruum")
    public static let tripStart = t("trip.start", "Vo")
    public static let tripEnd = t("trip.end", "Bis")
    public static let tripCurrency = t("trip.currency", "Landeswärig")
    public static let tripPeople = t("trip.people", "Persone")
    public static let tripPeopleHint = t("trip.peopleHint",
                                         "So viel Persone wie du wottsch. Zum Lösche nach links wüsche – Persone mit Uusgabe blybe gschützt.")
    public static let tripCostShare = t("trip.costShare", "Choschteschlüssel")
    public static let tripCostShareHint = t("trip.costShareHint",
                                            "Wär trait wie viel vo de gmeinsame Choschte? D Summe isch immer genau 100 % – wenn du eine verschiebsch, passe sich di andere automatisch a.")
    public static let tripCostShareSingle = t("trip.costShareSingle",
                                              "Mit nume einere Person trait die logischerwys 100 %.")
    public static let tripClosedHint = t("trip.closedHint",
                                         "Bi ere abgschlossene Reis chasch kei Uusgabe meh erfasse, ändere oder lösche.")
    public static let tripClosedBlocked = t("trip.closedBlocked",
                                            "Die Reis isch abgschlosse – zum Ändere muesch si zerscht wieder ufmache.")

    public static func tripParticipantCount(_ count: Int) -> String {
        String(localized: "trip.participantCount", defaultValue: "\(count) Persone")
    }
    public static let tripDeleteConfirm = t("trip.deleteConfirm", "Die Reis mit allne Uusgabe lösche?")
    public static let tripUnnamed = t("trip.unnamed", "Ohni Name")
    public static let tripStatusActive = t("trip.statusActive", "Aktiv")
    public static let tripStatusClosed = t("trip.statusClosed", "Abgschlosse")
    public static let tripSelect = t("trip.select", "Uswähle")
    public static let tripNoName = t("trip.noName", "Bitte gib dr Reis e Name.")

    // MARK: - Teile (CloudKit-Sharing)

    public static let sharingSection = t("sharing.section", "Teile")
    public static let sharingInvite = t("sharing.invite", "Mit em Partner teile")
    public static let sharingManage = t("sharing.manage", "Teilnehmer verwalte")
    public static let sharingStop = t("sharing.stop", "Teile beände")
    public static let sharingSharedWith = t("sharing.sharedWith", "Teilt mit")
    public static let sharingNotShared = t("sharing.notShared", "No nid teilt")
    public static let sharingShared = t("sharing.shared", "Teilt")
    public static let sharingHint = t("sharing.hint",
                                      "D Reis wird über iCloud teilt. Dyn Partner überchunnt e Iiladig und gseht drufabe genau di gliiche Date – ou mit em eigete Apple-Account.")
    public static let sharingOnlyOwner = t("sharing.onlyOwner", "Nume wär d Reis aagleit het, cha si teile.")
    public static let sharingUnknownParticipant = t("sharing.unknownParticipant", "Unbekannte Teilnehmer")
    public static let sharingNoSharedStore = t("sharing.noSharedStore", "Dr geteilti Spycher isch nid bereit.")
    public static let sharingAccepted = t("sharing.accepted", "Iiladig aagno – d Reis isch jetz da.")
    public static let sharingCreateFailed = t("sharing.createFailed", "D Freigab het nid chönne erstellt wärde.")
    public static let sharingParticipant = t("sharing.participant", "Du bisch iiglade worde")

    public static func sharingAcceptFailed(_ detail: String) -> String {
        String(localized: "sharing.acceptFailed", defaultValue: "Iiladig het nid chönne aagno wärde: \(detail)")
    }

    // MARK: - Iistellige

    public static let settingsTitle = t("settings.title", "Iistellige")
    public static let settingsRates = t("settings.rates", "Wächselkürs")
    public static let settingsMarkup = t("settings.markup", "Ufschlag uf Kurs (%)")
    public static let settingsMarkupHint = t("settings.markupHint",
                                             "D EZB publiziert Referänz- bzw. Mittelkürs. Mit em Ufschlag chasch e Bank-Verkoufskurs nachebilde. 0 % = reine EZB-Kurs.")
    public static let settingsRefreshRates = t("settings.refreshRates", "Kürs jetz aktualisiere")
    public static let settingsNeverRefreshed = t("settings.neverRefreshed", "No nie aktualisiert")
    public static let settingsSyncLog = t("settings.syncLog", "Sync-Protokoll")
    public static let settingsSyncMode = t("settings.syncMode", "Betriebsart")
    public static let settingsDeviceLabel = t("settings.deviceLabel", "Name vo däm Grät")
    public static let settingsDeviceLabelDefault = t("settings.deviceLabelDefault", "Mys iPhone")
    public static let settingsICloud = t("settings.icloud", "iCloud")
    public static let settingsICloudOk = t("settings.icloudOk", "Bereit")
    public static let settingsICloudMissing = t("settings.icloudMissing", "Kei iCloud-Account – dr Sync isch us")
    public static let settingsICloudRestricted = t("settings.icloudRestricted", "iCloud isch ygschränkt")
    public static let settingsICloudUnknown = t("settings.icloudUnknown", "Status unbekannt")

    public static func settingsLastRefresh(_ date: String) -> String {
        String(localized: "settings.lastRefresh", defaultValue: "Zletscht aktualisiert: \(date)")
    }

    public static func settingsCachedDays(_ count: Int) -> String {
        String(localized: "settings.cachedDays", defaultValue: "\(count) Kurstäg gspicheret")
    }

    // MARK: - Betriebsart (Lokalmodus / iCloud)

    public static let syncModeLocal = t("syncMode.local", "Nume lokal – ohni iCloud")
    public static let syncModeCloud = t("syncMode.cloud", "iCloud-Sync isch a")
    public static let syncModeLocalHint = t("syncMode.localHint",
                                            "D App louft im Lokalmodus: alli Date blybe uf däm Grät, es git kei Sync und kei Teile mit em Partner. Für ds Teile bruuchts es zahlts Apple Developer Program – wie me umschaltet, steit im README under «Lokalmodus».")
    public static let syncModeFallbackNotice = t("syncMode.fallbackNotice",
                                                 "iCloud isch nid verfüegbar gsi – d App isch automatisch uf Lokalmodus umgschtellt.")
    public static let sharingLocalMode = t("sharing.localMode", "Im Lokalmodus cha me nüt teile.")

    // MARK: - Sync-Protokoll

    public static let syncLogTitle = t("syncLog.title", "Sync-Protokoll")
    public static let syncLogEmpty = t("syncLog.empty", "No kei Änderige vom andere Grät.")
    public static let syncLogClear = t("syncLog.clear", "Protokoll leere")
    public static let syncLogHint = t("syncLog.hint",
                                      "Da gsehsch alli Änderige, wo vom andere Grät cho si – so wird nüt still überschriebe.")
    public static let syncLogStarted = t("syncLog.started", "Sync isch gstartet.")
    public static let syncLogStartedLocal = t("syncLog.startedLocal", "App im Lokalmodus gstartet – kei iCloud.")
    public static let syncLogCloudUnavailable = t("syncLog.cloudUnavailable",
                                                  "iCloud het nid chönne gstartet wärde – d App louft lokal wyter.")
    public static let syncLogStoreReset = t("syncLog.storeReset",
                                            "S Datemodäll het gänderet – dr lokal Spycher isch nöi ufboue worde.")
    public static let syncLogAuthorCloud = t("syncLog.authorCloud", "iCloud")

    public static func syncLogInserted(_ subject: String) -> String {
        String(localized: "syncLog.inserted", defaultValue: "Nöi: \(subject)")
    }

    public static func syncLogUpdated(_ subject: String) -> String {
        String(localized: "syncLog.updated", defaultValue: "Gänderet: \(subject)")
    }

    public static func syncLogUpdatedFields(_ subject: String, _ fields: String) -> String {
        String(localized: "syncLog.updatedFields", defaultValue: "Gänderet: \(subject) – \(fields)")
    }

    public static func syncLogDeleted(_ subject: String) -> String {
        String(localized: "syncLog.deleted", defaultValue: "Glöscht: \(subject)")
    }

    public static func syncLogSaveFailed(_ detail: String) -> String {
        String(localized: "syncLog.saveFailed", defaultValue: "Spichere het nid klappet: \(detail)")
    }

    // MARK: - Feldbezeichnige (fürs Protokoll)

    public static let fieldAmount = t("field.amount", "Betrag")
    public static let fieldCurrency = t("field.currency", "Wärig")
    public static let fieldCategory = t("field.category", "Kategorie")
    public static let fieldNote = t("field.note", "Verwändigszwäck")
    public static let fieldPayer = t("field.payer", "Zahler")
    public static let fieldDate = t("field.date", "Datum")
    public static let fieldName = t("field.name", "Name")
    public static let fieldPeriod = t("field.period", "Zytruum")
    public static let fieldStatus = t("field.status", "Status")
    public static let fieldCostShare = t("field.costShare", "Choschteschlüssel")
    public static let fieldParticipants = t("field.participants", "Persone")
    public static let fieldCategories = t("field.categories", "Kategorie")
    public static let fieldAppearance = t("field.appearance", "Darstellig")

    // MARK: - Kursquelle

    public static let rateSourceEcbLive = t("rateSource.ecbLive", "EZB-Kurs vom Tag")
    public static let rateSourceEcbCached = t("rateSource.ecbCached", "EZB-Kurs us em Spycher")
    public static let rateSourceIdentity = t("rateSource.identity", "Gliichi Wärig")
    public static let rateSourceManual = t("rateSource.manual", "Vo Hand")
    public static let rateSourceUnavailable = t("rateSource.unavailable", "Kei Kurs verfüegbar")
    public static let rateSourceUnknown = t("rateSource.unknown", "Unbekannt")

    // MARK: - Fähler

    public static func errorFeedMalformed(_ detail: String) -> String {
        String(localized: "error.feedMalformed", defaultValue: "D Kursdate si nid läsbar: \(detail)")
    }

    public static func errorUnsupportedCurrency(_ code: String) -> String {
        String(localized: "error.unsupportedCurrency", defaultValue: "D Wärig \(code) wird nid unterstützt.")
    }

    public static func errorNoRate(_ currency: String, _ day: String) -> String {
        String(localized: "error.noRate", defaultValue: "Kei Kurs für \(currency) am \(day).")
    }

    public static func errorNetwork(_ detail: String) -> String {
        String(localized: "error.network", defaultValue: "Kei Verbindig zur EZB: \(detail)")
    }

    // MARK: - CSV-Export

    public static let csvHeaderTrip = t("csv.headerTrip", "Reis")
    public static let csvHeaderPeriod = t("csv.headerPeriod", "Zytruum")
    public static let csvHeaderCurrency = t("csv.headerCurrency", "Reisewärig")
    public static let csvHeaderExported = t("csv.headerExported", "Exportiert am")
    public static let csvSectionTransactions = t("csv.sectionTransactions", "Einzeltransaktione")
    public static let csvSectionCategories = t("csv.sectionCategories", "Kategorie-Summe")
    public static let csvSectionSettlement = t("csv.sectionSettlement", "Schlusssaldo")
    public static let csvColDate = t("csv.colDate", "Datum")
    public static let csvColTime = t("csv.colTime", "Zyt")
    public static let csvColCategory = t("csv.colCategory", "Kategorie")
    public static let csvColPurpose = t("csv.colPurpose", "Verwändigszwäck")
    public static let csvColPayer = t("csv.colPayer", "Zahler")
    public static let csvColAmount = t("csv.colAmount", "Betrag")
    public static let csvColCurrency = t("csv.colCurrency", "Wärig")
    public static let csvColRate = t("csv.colRate", "Kurs zu CHF")
    public static let csvColAmountCHF = t("csv.colAmountCHF", "Betrag CHF")
    public static let csvColRateDate = t("csv.colRateDate", "Kursdatum")
    public static let csvColRateSource = t("csv.colRateSource", "Kursquelle")
    public static let csvColCount = t("csv.colCount", "Aazahl")
    public static let csvTotal = t("csv.total", "Total")
    public static let csvHeaderParticipants = t("csv.headerParticipants", "Persone")
    public static let csvSectionBalance = t("csv.sectionBalance", "Bilanz pro Person")
    public static let csvColPerson = t("csv.colPerson", "Person")
    public static let csvColCostShare = t("csv.colCostShare", "Choschteaateil (%)")
    public static let csvColPaidCHF = t("csv.colPaidCHF", "Usgleit CHF")
    public static let csvColShareCHF = t("csv.colShareCHF", "Choschteaateil CHF")
    public static let csvColNetCHF = t("csv.colNetCHF", "Saldo CHF")
    public static let csvColFrom = t("csv.colFrom", "Vo")
    public static let csvColTo = t("csv.colTo", "A")

    public static func csvColAmountTrip(_ currency: String) -> String {
        String(localized: "csv.colAmountTrip", defaultValue: "Betrag \(currency)")
    }

    public static func csvColPaidBy(_ name: String) -> String {
        String(localized: "csv.colPaidBy", defaultValue: "Usgleit \(name)")
    }

    public static func csvColPaidTrip(_ currency: String) -> String {
        String(localized: "csv.colPaidTrip", defaultValue: "Usgleit \(currency)")
    }

    public static func csvColShareTrip(_ currency: String) -> String {
        String(localized: "csv.colShareTrip", defaultValue: "Choschteaateil \(currency)")
    }

    public static func csvColNetTrip(_ currency: String) -> String {
        String(localized: "csv.colNetTrip", defaultValue: "Saldo \(currency)")
    }

    public static func csvNoteMissingRates(_ count: Int) -> String {
        String(localized: "csv.noteMissingRates",
               defaultValue: "Hiwys: \(count) Uusgabe ohni Wächselkurs – nid i de CHF-Summe drin.")
    }
}
