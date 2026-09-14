# Räpplispauter

iOS-App zur gemeinsamen Verwaltung von Ferienausgaben für **beliebig viele
Personen**, mit automatischer iCloud-Synchronisation zwischen getrennten
Apple-Accounts.

- SwiftUI (App-Lifecycle), Dark Mode als primäres Erscheinungsbild
- Core Data + CloudKit (`NSPersistentCloudKitContainer`) mit CloudKit Sharing
- Offline-First: lokal ist die Wahrheit, Sync läuft im Hintergrund
- Kein eigener Server – ausschliesslich iCloud
- UI-Texte in Bärndütsch, zentral in `Resources/Strings.swift`
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
| Kassä mit anderen teilen | ✅ | ❌ |
| Sperrbildschirm-Widget | ✅ | ❌ (App-Group braucht das Programm) |
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
iCloud-Modus wechselt, **behält seine erfassten Kassä**; sie werden beim ersten
Start hochgeladen.


## 1. Projekt öffnen und einrichten

```bash
open Raepplispauter/Raepplispauter.xcodeproj
```

### Signierung einrichten (einmalig)

Die Team-Kennung steht **nicht** in der Projektdatei, sondern in einer lokalen
Datei, die git ignoriert:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Dort die eigene Kennung eintragen (Xcode ▸ Settings ▸ Accounts ▸ Account wählen
▸ Team – die Zeichenfolge in Klammern, etwa `A1B2C3D4E5`):

```
DEVELOPMENT_TEAM = A1B2C3D4E5
```

**Warum der Umweg?** Die Kennung gehört zum Entwickler-Account, nicht zum
Projekt. Stünde sie in `project.pbxproj`, läge sie im öffentlichen Repository –
und, praktisch wichtiger: Xcode schreibt sie beim Team-Auswählen dort hinein,
womit die Datei lokal geändert wäre und jeder `git pull` mit
*„Your local changes would be overwritten by merge"* abbräche. Über
`Config/Signing.xcconfig` bleibt die Projektdatei unangetastet.

Wählt man das Team trotzdem über die Xcode-Oberfläche aus, schreibt Xcode es
wieder in die Projektdatei und der Effekt ist dahin. Also: nur
`Config/Local.xcconfig` bearbeiten.

### Weiteres in Xcode

1. **Bundle Identifier** anpassen, falls `ch.hebera.raepplispauter` schon vergeben ist.
   Betrifft alle drei Targets – App, Widget (`…​.widget`) und Tests (`…​.tests`).

Die folgenden Punkte betreffen **nur den iCloud-Modus** (siehe Abschnitt 0):

2. **iCloud-Container** prüfen: Die App erwartet `iCloud.ch.hebera.raepplispauter`.
   Wird ein anderer Container verwendet, müssen **zwei** Stellen angepasst werden:
   - `Config/Raepplispauter.entitlements`
   - `PersistenceController.cloudKitContainerID`

Die Capabilities *iCloud → CloudKit*, *Background Modes → Remote notifications* und
*Push Notifications* sind über die Entitlements- und Info.plist-Dateien bereits
vorbereitet; Xcode zeigt sie nach dem Setzen des Teams automatisch an.

> **Erster Start mit CloudKit:** Beim ersten Lauf legt der Container das
> CloudKit-Schema in der Development-Umgebung an. Vor dem Verteilen an das zweite
> Gerät im CloudKit-Dashboard **„Deploy Schema to Production“** ausführen.

### Wenn `git pull` an der Projektdatei scheitert

Xcode schreibt `project.pbxproj` beim Öffnen und Bauen um: Es sortiert
Einstellungen alphabetisch, klammert Abschnitte anders und lässt Vorgabewerte
weg. Inhaltlich ändert das nichts – die Datei sieht danach nur anders aus.
Trotzdem gilt sie git als geändert und blockiert den nächsten Pull:

```
error: Your local changes to the following files would be overwritten by merge:
	Raepplispauter.xcodeproj/project.pbxproj
```

Seit die Signierung ausgelagert ist, steckt in dieser Umformatierung **nichts
Erhaltenswertes**. Sie lässt sich darum gefahrlos verwerfen:

```bash
git checkout -- Raepplispauter.xcodeproj/project.pbxproj
git pull
```

Vor dem Verwerfen kurz `git status` – steht dort noch eine andere Datei, ist
die separat anzusehen.

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
├─ Config/                     Info.plist, Entitlements (App + Widget)
├─ Shared/                     Code, den App *und* Widget brauchen
├─ RaepplispauterWidget/       Sperrbildschirm-Widget (Erweiterung)
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
   │                           Kassä, Kategorien, Einstellungen
   ├─ Widget/                  schreibt die Momentaufnahme fürs Widget
   └─ Resources/               Strings.swift, PrivacyInfo.xcprivacy, Assets
```

Die Schichten sind bewusst getrennt: `Logic/` kennt weder Core Data noch SwiftUI
und ist deshalb vollständig unit-testbar (`RaepplispauterTests`).


## 3. Das Rechenmodell (wichtig zu verstehen)

Eine Kassä hat **beliebig viele Personen**. Jede Ausgabe hat zwei Dimensionen:

| Dimension | Bedeutung | Wo eingestellt |
|-----------|-----------|----------------|
| **Zahler** | Wer hat *ausgelegt*? | pro Ausgabe, frei einstellbar |
| **Kostenanteil** | Wer *trägt* die Kosten? | fix: gleichmässig durch die Anzahl Personen |

* Zahler = **eine Person** → sie hat 100 % ausgelegt
* Zahler = **Gmeinsam** → mehrere haben ausgelegt, nach den Schiebern der Ausgabe

Getragen wird immer zu gleichen Teilen. Einen einstellbaren Kostenschlüssel gab
es früher, er ist bewusst entfallen: ein Regler, den praktisch niemand
verstellt, der aber bei jeder neuen Kassä eine Entscheidung kostete. Was im
Alltag wirklich wechselt – wer gerade ausgelegt hat – bleibt frei einstellbar.

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

Die Schieber der Auslage summieren sich **immer genau auf 100 %**. Bewegt man
einen, verteilt `SplitCalculator` den Rest proportional auf die übrigen Personen
– über 100 % zu kommen ist konstruktiv unmöglich, es braucht keine
Fehlermeldung. Der Knopf *Glychmässig* verteilt gleichmässig.

Dieselbe Zusage gilt für die Kostenanteile: `SplitCalculator.equalShares` legt
den Rundungsrest auf die ersten Personen, damit drei Personen exakt
33.4 / 33.3 / 33.3 tragen und nicht 99.9 % in der Summe.

### Schlussabrechnung bei mehreren Personen

Statt „jeder mit jedem“ rechnet `SettlementCalculator` die Salden gegeneinander
auf: grösster Schuldner gegen grössten Gläubiger, bis alles ausgeglichen ist.
Bei n Personen ergibt das **höchstens n−1 Zahlungen**.

### Kategorien

Kategorien gehören zur Kassä, nicht zum Gerät – sie wandern beim Teilen mit.
Beim Anlegen einer Kassä entsteht ein Startsatz (Unterkunft, Restaurant,
Läbesmittel, ÖV, Outo, Sightseeing); eigene lassen sich jederzeit ergänzen
(auch direkt beim Erfassen einer Ausgabe), umbenennen, einfärben und – solange
keine Ausgabe sie verwendet – löschen.

### „Das bin ich"

Die App fragt einmal pro Kassä, welche Person an diesem Gerät sitzt. Danach:

* zeigt die Bilanz die Zahlungen aus eigener Sicht („Du zahlsch Beat" statt
  „Anna → Beat"), und die eigenen Zahlungen stehen zuoberst
* ist man beim Erfassen einer Ausgabe als Zahler vorbelegt
* ist die eigene Zeile in der Personenliste mit „du" markiert

Die Zuordnung liegt bewusst **nur auf dem Gerät** (`UserDefaults`, Schlüssel
`myParticipant.<Kassä-UUID>`), nicht im Datenmodell:

* Auf dem Gerät der Partnerin ist die Antwort eine andere – im geteilten
  Datensatz gäbe es gar keinen eindeutigen Wert.
* Es braucht keine CloudKit-Schemaänderung, die Zuordnung ist also auch nach
  der Veröffentlichung noch änderbar.
* Es wird keine iCloud-Kennung gespeichert, nur eine App-interne UUID.

Ändern lässt sie sich jederzeit in den Kassä-Einstellungen unter „Wär bisch du?".

### Abgeschlossene Kassä

Ist eine Kassä abgeschlossen, sind Erfassen, Ändern und Löschen von Ausgaben
gesperrt, ebenso die Personen. Die Abrechnung bleibt damit
stabil. Über *Abrächnig → Kassä wieder ufmache* lässt sich die Sperre lösen.


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
| `private.sqlite` | private | Kassä, die man selber angelegt hat |
| `shared.sqlite` | shared | Kassä, die der Partner geteilt hat |

**Ablauf**

1. **Einladen** – In der Kassä „Mit em Partner teile“ tippen.
   `NSPersistentCloudKitContainer.share(_:to:)` verschiebt die Kassä samt
   Personen, Kategorien und Ausgaben in eine eigene, geteilte CloudKit-Zone und
   erzeugt einen `CKShare`.
   Der `UICloudSharingController` verschickt die Einladung (Nachricht, Mail, Link).
2. **Annehmen** – Die eingeladene Person tippt auf den Link, iOS übergibt die
   Einladung an die App, die App ruft `acceptShareInvitations(from:into:)` mit
   dem *shared* Store auf.

   **An wen iOS die Einladung übergibt, hängt davon ab, ob die App Szenen
   benutzt:**

   | App | Methode |
   |---|---|
   | ohne Szenen | `UIApplicationDelegate.application(_:userDidAcceptCloudKitShareWith:)` |
   | mit Szenen | `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` |

   Jede SwiftUI-App mit `WindowGroup` ist szenenbasiert. Die App-Delegate-
   Methode allein wird also **nie** aufgerufen – die Einladung kommt an, wird
   aber nirgends entgegengenommen, und die geteilte Kassä erscheint auf dem
   zweiten Gerät nie. Das Symptom ist tückisch, weil alles davor funktioniert:
   Der Link öffnet sich, iOS fragt „beitreten?", die App startet. Nur danach
   passiert nichts.

   Implementiert sind deshalb beide Wege – der Szenen-Weg, der greift, und der
   App-Weg als Rückfall. Der `SceneDelegate` implementiert bewusst **nur** die
   CloudKit-Methode: `scene(_:willConnectTo:options:)` würde den Fensteraufbau
   übernehmen, den SwiftUI selbst erledigt, und die App bliebe leer.
**Zwei Wege zum Einladen – und warum sie sich unterscheiden**

| Knopf | Wer kommt herein |
|---|---|
| *Mit em Partner teile* | Apple-Freigabeoberfläche: namentlich eingeladene Apple-Accounts |
| *Iiladigs-Link verschicke* | jede Person, die den Link hat |

Der Unterschied steckt in `CKShare.publicPermission`. Ein frisch erstellter
Share steht auf `.none` – herein kommt dann **nur**, wer vorher namentlich als
Teilnehmer eingetragen wurde. Ein solcher Link ist technisch gültig, aber für
niemanden freigeschaltet; beim Empfänger endet er mit

> Objekt nicht verfügbar. Die Person, der die Datei gehört, teilt diese nicht
> mehr oder dein Account ist nicht berechtigt, sie zu öffnen.

`SharingController.makeLinkShare(for:)` setzt deshalb `publicPermission` auf
`.readWrite` **und** speichert den Share über `persistUpdatedShare(_:in:)` nach
iCloud. Das Setzen allein genügt nicht: Es ändert nur die lokale Kopie des
Datensatzes. (Nebenbei kommt dabei auch der Titel der Einladung beim Server an,
der sonst nie gespeichert würde.)

> **Voraussetzung auf dem anderen Gerät:** Dort muss die App **installiert**
> sein, sonst öffnet der Link nur eine iCloud-Website. Solange die App nicht im
> App Store ist, heisst das: über TestFlight verteilen oder per Xcode
> installieren. Und beide Geräte müssen dieselbe CloudKit-Umgebung benutzen –
> eine per Xcode installierte App spricht mit *Development*, eine aus
> TestFlight oder dem App Store mit *Production*. Eine Freigabe aus der einen
> Umgebung ist in der anderen nicht sichtbar.

3. **Betrieb** – Beide Geräte schreiben in dieselbe Zone. Neue Ausgaben landen
   automatisch in der Zone ihrer Kassä (`context.assign(_:to:)` sorgt dafür, dass
   sie im richtigen Store liegen).

Voraussetzung ist `CKSharingSupported = YES` in der Info.plist.

**Wenn die geteilte Kassä nicht erscheint:** Auf dem Gerät der eingeladenen
Person **Iistellige ▸ Sync-Protokoll** öffnen. Steht dort „Iiladig empfange",
kam die Einladung an und das Annehmen ist das Problem – ein Fehler dazu steht
direkt darunter. Steht dort nichts, wurde die Einladung nie übergeben; dann ist
der Weg über den `SceneDelegate` zu prüfen. Fehler beim Annehmen zeigt die App
zusätzlich als Hinweis an, sobald sie im Vordergrund ist.

---

## 6. Konflikte und Nachvollziehbarkeit

* Merge-Policy `mergeByPropertyObjectTrump` löst Konflikte **feldweise** – zwei
  Personen, die offline verschiedene Ausgaben erfassen, kommen beide durch.
* Damit nichts *still* überschrieben wird, liest `ConflictAuditor` die
  **Persistent History** und protokolliert jede Änderung, die von einem anderen
  Gerät kommt: was, welche Felder, wann, von wem.
  Sichtbar unter **Kassä → Einstellungen → Sync-Protokoll**.
* Zusätzlich trägt jede Ausgabe `updatedAt` und `lastEditedBy`.
* Das Protokoll ist bewusst gerätelokal (JSON-Datei) – würde es synchronisiert,
  löste jeder Eintrag wieder eine Änderung aus.

---

## 7. Sperrbildschirm-Widget

Auf dem Sperrbildschirm lässt sich der eigene Saldo einblenden – in drei
Grössen: eine Zeile über der Uhr (*inline*), rund (*circular*) und als Kachel
(*rectangular*).

**Hinzufügen am iPhone:** Sperrbildschirm gedrückt halten → *Anpassen* →
*Sperrbildschirm* → auf den Bereich unter der Uhr tippen → *Räpplispauter*.

### Wie die Daten hinkommen

Das Widget ist eine eigene App-Erweiterung mit eigenem Prozess – es kann nicht
einfach in den Speicher der App greifen. Der Weg ist deshalb:

```
App                                    Widget
 │                                       │
 │ jede Änderung (auch aus iCloud)       │
 ▼                                       │
WidgetSnapshotWriter                     │
 │ rechnet Bilanz, formatiert Beträge    │
 ▼                                       │
App-Group (UserDefaults) ────────────────▶ liest nur noch fertige Werte
 │
 └─ WidgetCenter.reloadTimelines(…)
```

**Warum nicht Core Data im Widget?** Das wäre der naheliegende Weg, kostet aber
viel: Die Speicherdateien müssten in den App-Group-Container umziehen (samt
Migration bestehender Kassä), das Datenmodell wäre im Widget nochmals nötig,
und CloudKit müsste aus einer Erweiterung heraus laufen. Für drei Zahlen auf
dem Sperrbildschirm ist das zu viel Angriffsfläche – ein Fehler im Widget
könnte dann die Kassä-Daten beschädigen. Mit der Momentaufnahme bleibt der
Datenspeicher unberührt.

Die Beträge stehen **fertig formatiert** in der Momentaufnahme. Formatiert wird
in `Money` im App-Target; würde das Widget selbst rechnen, könnten
Sperrbildschirm und App verschiedene Zahlen zeigen.

### Was nötig ist

| Stelle | Wert |
|---|---|
| App-Group | `group.ch.hebera.raepplispauter` |
| Bundle-ID des Widgets | `ch.hebera.raepplispauter.widget` |
| Entitlements App | `Config/Raepplispauter.entitlements` |
| Entitlements Widget | `Config/RaepplispauterWidget.entitlements` |
| Kennung im Code | `WidgetSharing.appGroupID` |

Alle vier müssen dieselbe App-Group nennen. Ändert man sie an einer Stelle,
findet das Widget die Daten der App nicht mehr – es zeigt dann stumm seinen
leeren Zustand, es gibt keine Fehlermeldung.

> **App-Groups setzen das bezahlte Apple Developer Program voraus** – wie
> iCloud. Im Lokalmodus (gratis Apple-ID) lässt sich das Widget-Target nicht
> signieren; es muss dann im Schema abgewählt werden. Die App selbst läuft
> davon unberührt.

### Ohne „Das bin ich" kein persönlicher Saldo

Ist auf dem Gerät nicht festgelegt, welche Person hier sitzt, kann das Widget
keinen persönlichen Saldo zeigen – irgendeine Person zu wählen wäre geraten. Es
zeigt dann *„Wär bisch du?"* und die Gesamtsumme.


## 8. Texte ändern

Alle UI-Texte stehen in `Raepplispauter/Resources/Strings.swift` – und nur dort.
Text ändern, speichern, bauen. Mehr ist nicht nötig.

```swift
public static let settlementCloseTrip = t("settlement.closeTrip", "Kassä abschliessä")
//                                         └ Schlüssel (stabil)    └ angezeigter Text
```

**Warum es keinen String-Katalog gibt.** Naheliegend wäre eine
`Localizable.xcstrings` neben dieser Datei. Genau die hat aber laufend Ärger
gemacht: Es ist eine *generierte* Kopie derselben Texte, und Xcode fasst sie beim
Bauen an. Damit schrieben zwei Stellen in dieselbe versionierte Datei, und jedes
`git pull` scheiterte an lokalen Änderungen.

Nötig ist der Katalog ohnehin erst ab der zweiten Sprache: Findet Foundation
keinen Katalogeintrag, liefert `String(localized:defaultValue:)` den
`defaultValue` zurück – also exakt den Text, der hier steht. Die App ist
einsprachig (`developmentRegion = de`), der Katalog wäre reine Dopplung. Er ist
deshalb entfernt, in `.gitignore` eingetragen und `SWIFT_EMIT_LOC_STRINGS` steht
auf `NO`.

Soll die App später übersetzt werden: `SWIFT_EMIT_LOC_STRINGS` auf `YES`, den
`.gitignore`-Eintrag entfernen, dann legt Xcode den Katalog aus den
`defaultValue`s selbst wieder an.

---

## 9. Tests

`RaepplispauterTests` deckt die Berechnungslogik ab (⌘U in Xcode):

* `MoneyTests` – 5-Rappen-Rundung, Betragserfassung
* `SplitCalculatorTests` – die 100-%-Regel, gleichmässig verteilen, Person dazu/weg
* `BalanceCalculatorTests` – Zahler, geteilte Auslagen, Kostenschlüssel, 2–3 Personen
* `SettlementCalculatorTests` – Ausgleich über mehrere Personen, Auswertung
* `CSVExporterTests` – Aufbau, Maskierung, Spalte je Person, Dateiname
* `ExchangeRateTests` – EZB-Parser, Kreuzkurse, Cache, Umrechnung

---

## 10. Bekannte Einschränkungen

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
