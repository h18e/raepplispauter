# Räpplispauter

iOS-App zur gemeinsamen Verwaltung von Ferienausgaben für zwei Personen
(**Raphi** = Person A, **Gini** = Person B) mit automatischer iCloud-Synchronisation
zwischen **zwei getrennten Apple-Accounts**.

- SwiftUI (App-Lifecycle), Dark Mode als primäres Erscheinungsbild
- Core Data + CloudKit (`NSPersistentCloudKitContainer`) mit CloudKit Sharing
- Offline-First: lokal ist die Wahrheit, Sync läuft im Hintergrund
- Kein eigener Server – ausschliesslich iCloud
- UI-Texte in Bärndütsch, zentral in `Resources/Strings.swift` + `Localizable.xcstrings`
- Deployment-Target: **iOS 26.0**
- **Lokalmodus** für Tests mit einer gratis Apple-ID (Standard, siehe Abschnitt 0)

---

## 0. Lokalmodus vs. iCloud-Modus

Die App kennt zwei Betriebsarten. **Ausgeliefert wird sie im Lokalmodus**, damit
sie sich mit einer gratis Apple-ID sofort aufs iPhone spielen lässt.

| | Lokalmodus (Standard) | iCloud-Modus |
|---|---|---|
| Apple-Account | gratis Apple-ID reicht | **Apple Developer Program (99 $/Jahr)** |
| Erfassen, Bilanz, Logbuch, Auswertung, Abrechnung, CSV | ✅ | ✅ |
| Sync zwischen zwei Geräten | ❌ | ✅ |
| Reise mit dem Partner teilen | ❌ | ✅ |
| App läuft nach Installation | 7 Tage, dann neu installieren | 1 Jahr |

### Umschalten – zwei Stellen, beide müssen zusammenpassen

**1. Code:** `Raepplispauter/App/AppConfiguration.swift`

```swift
public static let syncMode: SyncMode = .localOnly   // bzw. .cloudKit
```

**2. Signierung:** Xcode → Projekt **Raepplispauter** → TARGETS → **Raepplispauter**
→ **Build Settings** → oben **All** wählen → nach `Code Signing Entitlements`
suchen → Wert setzen:

| `syncMode` | Code Signing Entitlements |
|---|---|
| `.localOnly` | `Config/Raepplispauter-Local.entitlements` |
| `.cloudKit` | `Config/Raepplispauter.entitlements` |

> **Warum beides?** Eine gratis Apple-ID kann keine iCloud-Entitlements
> signieren – wären sie aktiv, scheiterte schon das Erstellen des
> Provisioning-Profils, noch vor dem ersten Build.

### Sicherheitsnetz

Steht `syncMode` auf `.cloudKit`, ist iCloud aber nicht verfügbar (fehlendes
Entitlement, kein iCloud-Account, kein Container), **stürzt die App nicht ab**:
`PersistenceController` fällt automatisch auf den Lokalmodus zurück und vermerkt
das im Sync-Protokoll sowie in den Einstellungen. Abschalten lässt sich dieses
Verhalten über `AppConfiguration.allowsAutomaticLocalFallback`.

### Datenbestand beim Wechsel

Beide Modi benutzen dieselbe Datei (`private.sqlite`). Wer später vom Lokal- in
den iCloud-Modus wechselt, **behält seine erfassten Reisen und Ausgaben**; sie
werden beim ersten Start in iCloud hochgeladen.

---

## 1. Projekt öffnen und einrichten

```bash
open Raepplispauter/Raepplispauter.xcodeproj
```

Danach in Xcode setzen:

1. **Target „Raepplispauter“ → Signing & Capabilities → Team** auswählen.
2. **Bundle Identifier** anpassen, falls `ch.hebera.raepplispauter` schon vergeben ist.

Die folgenden Punkte betreffen **nur den iCloud-Modus** (siehe Abschnitt 0):

3. **iCloud-Container** prüfen: Die App erwartet `iCloud.ch.hebera.raepplispauter`.
   Wird ein anderer Container verwendet, müssen **zwei** Stellen angepasst werden:
   - `Config/Raepplispauter.entitlements`
   - `PersistenceController.cloudKitContainerID`

Die Capabilities *iCloud → CloudKit*, *Background Modes → Remote notifications* und
*Push Notifications* sind über die Entitlements- und Info.plist-Dateien bereits
vorbereitet; Xcode zeigt sie nach dem Setzen des Teams automatisch an.

> **Erster Start mit CloudKit:** Beim ersten Lauf legt der Container das
> CloudKit-Schema in der Development-Umgebung an. Vor dem Verteilen an das zweite
> Gerät im CloudKit-Dashboard **„Deploy Schema to Production“** ausführen.

### Projekt neu generieren (optional)

Falls die `.pbxproj` je Ärger macht, lässt sich das Projekt aus `project.yml`
neu erzeugen:

```bash
brew install xcodegen
cd Raepplispauter && xcodegen generate
```

---

## 2. Aufbau

```
Raepplispauter/
├─ Raepplispauter.xcodeproj
├─ Config/                     Info.plist, Entitlements
├─ Tools/                      generate-xcstrings.py
└─ Raepplispauter/
   ├─ App/                     Einstieg, Navigation, Theme, Einstellungen
   ├─ Model/                   Core-Data-Modell + NSManagedObject-Klassen
   ├─ Persistence/             Container (privat + geteilt), Konflikt-Protokoll
   ├─ Sharing/                 CKShare erstellen, einladen, annehmen
   ├─ Exchange/                EZB-Kurse: Feed, Cache, Umrechnung, Nachtrag
   ├─ Logic/                   Rundung, Bilanz, Abrechnung, CSV  (Core-Data-frei)
   ├─ Views/                   Bilanz, Logbuch, Auswertung, Abrechnung, Reisen
   └─ Resources/               Strings.swift, Localizable.xcstrings, Assets
```

Die Schichten sind bewusst getrennt: `Logic/` kennt weder Core Data noch SwiftUI
und ist deshalb vollständig unit-testbar (`RaepplispauterTests`).

---

## 3. Das Rechenmodell (wichtig zu verstehen)

Jede Ausgabe hat **zwei** Dimensionen:

| Dimension | Bedeutung | Wo eingestellt |
|-----------|-----------|----------------|
| **Zahler** | Wer hat *ausgelegt*? | pro Ausgabe |
| **Kostenschlüssel** | Wer *trägt* die Kosten? | pro Reise (Standard 50/50) |

* Zahler **Raphi** → Raphi hat 100 % ausgelegt
* Zahler **Gini** → Gini hat 100 % ausgelegt
* Zahler **Gmeinsam** → beide haben ausgelegt, im Verhältnis des
  Aufteilungsschlüssels der Ausgabe (Standard 50/50, z. B. auf 60/40 stellbar)

Die Bilanz ist dann schlicht:

```
Saldo(Raphi) = ausgelegt(Raphi) − getragen(Raphi)
```

**Beispiele** (Kostenschlüssel 50/50):

| Ausgabe | Zahler | Ergebnis |
|---------|--------|----------|
| 100 € | Raphi | Gini schuldet Raphi 50 € |
| 100 € | Gmeinsam 50/50 | ausgeglichen |
| 100 € | Gmeinsam 60/40 | Gini schuldet Raphi 10 € |

Bei einem Reise-Kostenschlüssel von z. B. 70/30 trägt Raphi 70 % aller Ausgaben –
zahlt er 100 €, steht er nur mit 30 € im Plus.

---

## 4. Wechselkurse (EZB)

**Datenquelle** – offener XML-Feed der Europäischen Zentralbank, kein API-Key:

| Feed | URL |
|------|-----|
| Tageskurse | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` |
| 90 Tage | `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml` |

Alle Kurse sind gegen EUR notiert; Fremdwährung → CHF wird als Kreuzkurs über EUR
gerechnet (`DailyRates.crossRate`).

### Referenzkurs statt Verkaufskurs

Die EZB publiziert **Referenz-/Mittelkurse**, keine Bank-Verkaufskurse. Um den in
der Spezifikation gewünschten Verkaufskurs abzubilden, gibt es in den
Einstellungen einen **Aufschlag in Prozent** (`AppSettings.rateMarkupPercent`,
Standard **0 %**). Der effektiv verwendete Kurs wird pro Ausgabe eingefroren und
erscheint im CSV-Export.

### Offline und der Platzhalter-Fall

1. Kurs des Erfassungstages im Cache → wird verwendet
2. sonst der jüngste Kurs davor (Wochenende, Feiertag) → als Cache-Kurs markiert
3. gar kein Kurs (Erstinstallation ohne Netz) → **Platzhalter**: die Ausgabe wird
   gespeichert und mit „Kurs fählt“ markiert, aus der CHF-Bilanz herausgehalten und
   von `RateBackfillService` automatisch nachgerechnet, sobald wieder Kurse da sind

Es wird **nie** stillschweigend ein erfundener Kurs verwendet.

CHF-Beträge werden immer auf **5 Rappen** gerundet (`Money.roundToFiveRappen`).

---

## 5. CloudKit-Sharing zwischen zwei Accounts

Die App führt **zwei** Core-Data-Stores auf demselben Modell:

| Store | CloudKit-Datenbank | Inhalt |
|-------|--------------------|--------|
| `private.sqlite` | private | Reisen, die man selber angelegt hat |
| `shared.sqlite` | shared | Reisen, die der Partner geteilt hat |

**Ablauf**

1. **Einladen** – In der Reise „Mit em Partner teile“ tippen.
   `NSPersistentCloudKitContainer.share(_:to:)` verschiebt die Reise samt allen
   Ausgaben in eine eigene, geteilte CloudKit-Zone und erzeugt einen `CKShare`.
   Der `UICloudSharingController` verschickt die Einladung (Nachricht, Mail, Link).
2. **Annehmen** – Der Partner tippt auf den Link, iOS ruft
   `application(_:userDidAcceptCloudKitShareWith:)` auf, die App ruft
   `acceptShareInvitations(from:into:)` mit dem *shared* Store auf.
3. **Betrieb** – Beide Geräte schreiben in dieselbe Zone. Neue Ausgaben landen
   automatisch in der Zone ihrer Reise (`context.assign(_:to:)` sorgt dafür, dass
   sie im richtigen Store liegen).

Voraussetzung ist `CKSharingSupported = YES` in der Info.plist.

---

## 6. Konflikte und Nachvollziehbarkeit

* Merge-Policy `mergeByPropertyObjectTrump` löst Konflikte **feldweise** – zwei
  Personen, die offline verschiedene Ausgaben erfassen, kommen beide durch.
* Damit nichts *still* überschrieben wird, liest `ConflictAuditor` die
  **Persistent History** und protokolliert jede Änderung, die von einem anderen
  Gerät kommt: was, welche Felder, wann, von wem.
  Sichtbar unter **Reise → Einstellungen → Sync-Protokoll**.
* Zusätzlich trägt jede Ausgabe `updatedAt` und `lastEditedBy`.
* Das Protokoll ist bewusst gerätelokal (JSON-Datei) – würde es synchronisiert,
  löste jeder Eintrag wieder eine Änderung aus.

---

## 7. Texte ändern

Alle UI-Texte stehen in `Raepplispauter/Resources/Strings.swift`. Nach einer
Änderung den String-Katalog nachführen:

```bash
cd Raepplispauter && python3 Tools/generate-xcstrings.py
```

---

## 8. Tests

`RaepplispauterTests` deckt die Berechnungslogik ab (⌘U in Xcode):

* `MoneyTests` – 5-Rappen-Rundung, Betragserfassung
* `BalanceCalculatorTests` – Zahler, Aufteilungsschlüssel, Kostenschlüssel
* `SettlementCalculatorTests` – Schuldrichtung, Kategorien-/Zahler-Auswertung
* `CSVExporterTests` – Aufbau, Maskierung, Dateiname
* `ExchangeRateTests` – EZB-Parser, Kreuzkurse, Cache, Umrechnung

---

## 9. Bekannte Einschränkungen

* **Währungen** sind auf jene begrenzt, für die die EZB einen Referenzkurs
  publiziert (siehe `Currencies.supported`) – für alles andere gäbe es keine
  belastbare CHF-Umrechnung.
* Ein **App-Icon** ist als leerer Asset-Slot vorbereitet
  (`Assets.xcassets/AppIcon.appiconset`); dort noch ein 1024×1024-PNG einsetzen.
* Der **CloudKit-Sync lässt sich nur auf echten Geräten** mit angemeldetem
  iCloud-Account sinnvoll testen, nicht im Simulator ohne Account.
* Mit einer **gratis Apple-ID** gilt: App läuft 7 Tage, danach in Xcode nochmals
  ⌘R (die erfassten Daten bleiben erhalten, solange die App nicht gelöscht wird);
  maximal 3 selbst signierte Apps pro Gerät; kein iCloud, kein TestFlight.
