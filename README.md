# Räpplispauter

iOS-App zur gemeinsamen Verwaltung von Ferienausgaben für **beliebig viele
Personen**, mit automatischer iCloud-Synchronisation zwischen getrennten
Apple-Accounts.

- SwiftUI (App-Lifecycle), Dark Mode als primäres Erscheinungsbild
- Core Data + CloudKit (`NSPersistentCloudKitContainer`) mit CloudKit Sharing
- Offline-First: lokal ist die Wahrheit, Sync läuft im Hintergrund
- Kein eigener Server – ausschliesslich iCloud
- UI-Texte in Bärndütsch, zentral in `Resources/Strings.swift` + `Localizable.xcstrings`
- Deployment-Target: **iOS 26.0**
- Für die App-Store-Veröffentlichung vorbereitet – siehe `RELEASE.md`

---

## 0. Betriebsart: iCloud oder nur lokal

Die App kennt zwei Betriebsarten. **Ausgeliefert wird sie im iCloud-Modus.**

| | iCloud-Modus (Standard) | Lokalmodus |
|---|---|---|
| Apple-Account | **Apple Developer Program (99 $/Jahr)** | gratis Apple-ID reicht |
| Erfassen, Bilanz, Logbuch, Auswertung, Abrechnung, CSV | ✅ | ✅ |
| Sync zwischen Geräten | ✅ | ❌ |
| Reise mit anderen teilen | ✅ | ❌ |
| App läuft nach Installation | 1 Jahr | 7 Tage, dann neu installieren |

### Umschalten – zwei Stellen, beide müssen zusammenpassen

**1. Code:** `Raepplispauter/App/AppConfiguration.swift`

```swift
public static let syncMode: SyncMode = .cloudKit   // bzw. .localOnly
```

**2. Signierung:** Xcode → Projekt **Raepplispauter** → TARGETS → **Raepplispauter**
→ **Build Settings** → oben **All** wählen → nach `Code Signing Entitlements`
suchen → Wert setzen:

| `syncMode` | Code Signing Entitlements |
|---|---|
| `.cloudKit` | `Config/Raepplispauter.entitlements` |
| `.localOnly` | `Config/Raepplispauter-Local.entitlements` |

> **Warum beides?** Eine gratis Apple-ID kann keine iCloud-Entitlements
> signieren – wären sie aktiv, scheiterte schon das Erstellen des
> Provisioning-Profils, noch vor dem ersten Build.

### Sicherheitsnetz

Ist iCloud nicht verfügbar (fehlendes Entitlement, kein iCloud-Account, kein
Container), **stürzt die App nicht ab**: `PersistenceController` fällt automatisch
auf den Lokalmodus zurück und vermerkt das im Sync-Protokoll sowie in den
Einstellungen. Abschaltbar über `AppConfiguration.allowsAutomaticLocalFallback`.

### Datenbestand beim Wechsel

Beide Modi benutzen dieselbe Datei (`private.sqlite`). Wer vom Lokal- in den
iCloud-Modus wechselt, **behält seine erfassten Reisen**; sie werden beim ersten
Start hochgeladen.


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
├─ Config/                     Info.plist, Entitlements (iCloud + lokal)
├─ Tools/                      generate-xcstrings.py
├─ PRIVACY.md                  Entwurf der Datenschutzerklärung
├─ RELEASE.md                  Checkliste für den App Store
└─ Raepplispauter/
   ├─ App/                     Einstieg, Navigation, Theme, Konfiguration
   ├─ Model/                   Core Data: Trip, Participant, ExpenseCategory,
   │                           Expense, PaymentShare
   ├─ Persistence/             Container (privat + geteilt), Konflikt-Protokoll
   ├─ Sharing/                 CKShare erstellen, einladen, annehmen
   ├─ Exchange/                EZB-Kurse: Feed, Cache, Umrechnung, Nachtrag
   ├─ Logic/                   Rundung, Aufteilung, Bilanz, Abrechnung, CSV
   ├─ Views/                   Bilanz, Logbuch, Auswertung, Abrechnung,
   │                           Reisen, Kategorien, Einstellungen
   └─ Resources/               Strings.swift, Localizable.xcstrings,
                               PrivacyInfo.xcprivacy, Assets
```

Die Schichten sind bewusst getrennt: `Logic/` kennt weder Core Data noch SwiftUI
und ist deshalb vollständig unit-testbar (`RaepplispauterTests`).


## 3. Das Rechenmodell (wichtig zu verstehen)

Eine Reise hat **beliebig viele Personen**. Jede Ausgabe hat zwei Dimensionen:

| Dimension | Bedeutung | Wo eingestellt |
|-----------|-----------|----------------|
| **Zahler** | Wer hat *ausgelegt*? | pro Ausgabe |
| **Kostenschlüssel** | Wer *trägt* die Kosten? | pro Reise, je Person ein Schieber |

* Zahler = **eine Person** → sie hat 100 % ausgelegt
* Zahler = **Gmeinsam** → mehrere haben ausgelegt, nach den Schiebern der Ausgabe

Die Bilanz je Person ist dann schlicht:

```
Saldo(Person) = ausgelegt(Person) − getragen(Person)
```

**Beispiel** – drei Personen zu je einem Drittel, Anna zahlt 90 € Hotel:

| Person | ausgelegt | getragen | Saldo |
|---|---|---|---|
| Anna | 90 | 30 | **+60** |
| Beat | 0 | 30 | −30 |
| Cem | 0 | 30 | −30 |

### Die 100-%-Regel

Beide Schieberblöcke (Kostenschlüssel und Auslage) summieren sich **immer genau
auf 100 %**. Bewegt man einen Schieber, verteilt `SplitCalculator` den Rest
proportional auf die übrigen Personen – über 100 % zu kommen ist konstruktiv
unmöglich, es braucht keine Fehlermeldung. Der Knopf *Glychmässig* verteilt
gleichmässig.

### Schlussabrechnung bei mehreren Personen

Statt „jeder mit jedem“ rechnet `SettlementCalculator` die Salden gegeneinander
auf: grösster Schuldner gegen grössten Gläubiger, bis alles ausgeglichen ist.
Bei n Personen ergibt das **höchstens n−1 Zahlungen**.

### Kategorien

Kategorien gehören zur Reise, nicht zum Gerät – sie wandern beim Teilen mit.
Beim Anlegen einer Reise entsteht ein Startsatz (Unterkunft, Restaurant,
Läbesmittel, ÖV, Outo, Sightseeing); eigene lassen sich jederzeit ergänzen
(auch direkt beim Erfassen einer Ausgabe), umbenennen, einfärben und – solange
keine Ausgabe sie verwendet – löschen.

### „Das bin ich"

Die App fragt einmal pro Reise, welche Person an diesem Gerät sitzt. Danach:

* zeigt die Bilanz die Zahlungen aus eigener Sicht („Du zahlsch Beat" statt
  „Anna → Beat"), und die eigenen Zahlungen stehen zuoberst
* ist man beim Erfassen einer Ausgabe als Zahler vorbelegt
* ist die eigene Zeile in der Personenliste mit „du" markiert

Die Zuordnung liegt bewusst **nur auf dem Gerät** (`UserDefaults`, Schlüssel
`myParticipant.<Reise-UUID>`), nicht im Datenmodell:

* Auf dem Gerät der Partnerin ist die Antwort eine andere – im geteilten
  Datensatz gäbe es gar keinen eindeutigen Wert.
* Es braucht keine CloudKit-Schemaänderung, die Zuordnung ist also auch nach
  der Veröffentlichung noch änderbar.
* Es wird keine iCloud-Kennung gespeichert, nur eine App-interne UUID.

Ändern lässt sie sich jederzeit in den Reise-Einstellungen unter „Wär bisch du?".

### Abgeschlossene Reisen

Ist eine Reise abgeschlossen, sind Erfassen, Ändern und Löschen von Ausgaben
gesperrt, ebenso Personen und Kostenschlüssel. Die Abrechnung bleibt damit
stabil. Über *Abrächnig → Reis wieder ufmache* lässt sich die Sperre lösen.


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

## 5. CloudKit-Sharing zwischen getrennten Accounts

Die App führt **zwei** Core-Data-Stores auf demselben Modell:

| Store | CloudKit-Datenbank | Inhalt |
|-------|--------------------|--------|
| `private.sqlite` | private | Reisen, die man selber angelegt hat |
| `shared.sqlite` | shared | Reisen, die der Partner geteilt hat |

**Ablauf**

1. **Einladen** – In der Reise „Mit em Partner teile“ tippen.
   `NSPersistentCloudKitContainer.share(_:to:)` verschiebt die Reise samt
   Personen, Kategorien und Ausgaben in eine eigene, geteilte CloudKit-Zone und
   erzeugt einen `CKShare`.
   Der `UICloudSharingController` verschickt die Einladung (Nachricht, Mail, Link).
2. **Annehmen** – Der Partner tippt auf den Link, iOS ruft
   `application(_:userDidAcceptCloudKitShareWith:)` auf, die App ruft
   `acceptShareInvitations(from:into:)` mit dem *shared* Store auf.
**Reichweite der Freigabe:** In der Apple-Freigabeoberfläche lässt sich zwischen
„nur iiglademi Lüt" (namentlich eingeladene Apple-Accounts) und „jede, wo dr Link
het" wählen. Für eine Ferienabrechnung ist Letzteres meist praktischer: Link in
die Gruppe schicken, fertig. Sobald die Freigabe einmal gespeichert ist, gibt es
in den Reise-Einstellungen zusätzlich **„Iiladigs-Link verschicke"**, das den Link
direkt an Nachrichten, Mail, WhatsApp & Co. übergibt.

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
python3 Tools/generate-xcstrings.py
```

Das Skript liest die Parametertypen aus den Swift-Signaturen und setzt den
passenden Platzhalter (`Int` → `%lld`, `String` → `%@`). Lässt sich ein
Platzhalter nicht zuordnen, bricht es ab, statt zu raten – ein falscher
Platzhalter führt zur Laufzeit zum Absturz, weil Foundation eine Zahl sonst
als Zeiger liest.

> **Hinweis:** `SWIFT_EMIT_LOC_STRINGS` steht bewusst auf `NO`. Sonst schreibt
> Xcode bei jedem Bauen selbst in `Localizable.xcstrings` und der Katalog
> kollidiert bei jedem `git pull`.

---

## 8. Tests

`RaepplispauterTests` deckt die Berechnungslogik ab (⌘U in Xcode):

* `MoneyTests` – 5-Rappen-Rundung, Betragserfassung
* `SplitCalculatorTests` – die 100-%-Regel, gleichmässig verteilen, Person dazu/weg
* `BalanceCalculatorTests` – Zahler, geteilte Auslagen, Kostenschlüssel, 2–3 Personen
* `SettlementCalculatorTests` – Ausgleich über mehrere Personen, Auswertung
* `CSVExporterTests` – Aufbau, Maskierung, Spalte je Person, Dateiname
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
* Solange `AppConfiguration.resetStoreOnIncompatibleModel` auf `true` steht, baut
  die App bei einer Datenmodell-Änderung den lokalen Speicher neu auf. **Vor der
  App-Store-Veröffentlichung auf `false` setzen** – siehe `RELEASE.md`.
