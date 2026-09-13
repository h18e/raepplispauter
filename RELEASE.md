# Weg in den App Store

Checkliste für die Veröffentlichung von Räpplispauter. Abgehakt ist, was im
Projekt bereits vorbereitet ist; offen ist, was nur du erledigen kannst.

---

## 1. Im Projekt bereits erledigt

| Anforderung | Umsetzung |
|---|---|
| **Privacy Manifest** (seit 2024 Pflicht) | `Raepplispauter/Resources/PrivacyInfo.xcprivacy`: kein Tracking, keine Datenerhebung, begründete Nutzung von UserDefaults und Datei-Zeitstempeln |
| **Export-Compliance** | `ITSAppUsesNonExemptEncryption = false` in `Config/Info.plist` – erspart die Rückfrage bei jedem Build |
| **Keine ATS-Ausnahmen** | Einziger Netzzugriff läuft über HTTPS zur EZB; `NSAppTransportSecurity` ist bewusst nicht gesetzt |
| **Keine unnötigen Berechtigungen** | Kein Zugriff auf Kamera, Kontakte, Standort, Fotos, Mikrofon oder Tracking |
| **Keine Gerätekennungen** | Statt `UIDevice.current.name` gibt es einen frei wählbaren Gerätenamen in den Einstellungen |
| **Datensparsamkeit** | Kein eigener Server, kein Konto, keine Analyse; alles liegt lokal bzw. in der privaten iCloud des Nutzers |
| **Datenschutzerklärung** | Fertiger Entwurf in `PRIVACY.md` |
| **Offline-Tauglichkeit** | Voll nutzbar ohne Netz – ein häufiger Ablehnungsgrund bei Reise-Apps |
| **Widget ohne eigene Daten** | Das Sperrbildschirm-Widget liest nur eine Momentaufnahme aus der App-Group; es greift weder aufs Netz noch auf den Datenspeicher zu |

## 2. Vor der Einreichung erledigen

### 2.1 App-Icon
`Raepplispauter/Resources/Assets.xcassets/AppIcon.appiconset` enthält nur den
leeren Platz. **Ohne 1024×1024-PNG (ohne Transparenz, ohne Alphakanal) wird die
Einreichung abgelehnt.**

### 2.2 Datenmodell absichern
In `Raepplispauter/App/AppConfiguration.swift`:

```swift
public static let resetStoreOnIncompatibleModel = false
```

Solange das auf `true` steht, baut die App bei einer Modelländerung den lokalen
Speicher neu auf. In der Entwicklung ist das praktisch, nach der
Veröffentlichung wäre es Datenverlust. Ab dann gilt: neue Modellversion anlegen
(Xcode → *Editor → Add Model Version*) und Lightweight Migration nutzen.

### 2.3 CloudKit in Produktion bringen
Im [CloudKit-Dashboard](https://icloud.developer.apple.com/dashboard) den
Container `iCloud.ch.hebera.raepplispauter` öffnen und
**Deploy Schema to Production** ausführen. Ohne das findet die App-Store-Version
keine Datenbank – auch wenn die Entwicklungsversion einwandfrei läuft.

### 2.4 App-Group für das Widget registrieren
Das Sperrbildschirm-Widget liest seine Daten über eine App-Group. Diese muss im
[Developer-Portal](https://developer.apple.com/account/resources/identifiers)
existieren und beiden App-IDs zugeordnet sein:

| | |
|---|---|
| App-Group | `group.ch.hebera.raepplispauter` |
| App-ID | `ch.hebera.raepplispauter` |
| App-ID des Widgets | `ch.hebera.raepplispauter.widget` |

Bei automatischer Signierung legt Xcode beides beim ersten Bauen selbst an –
prüfen lässt es sich unter *Signing & Capabilities* je Target. Fehlt die Gruppe,
baut die App trotzdem; das Widget bleibt dann einfach leer, **ohne
Fehlermeldung**. Nach dem Einrichten einmal auf dem Gerät testen.

### 2.5 Version und Signierung
* `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` setzen
* `DEVELOPMENT_TEAM` gefüllt, automatische Signierung aktiv
* `aps-environment` wechselt beim Archivieren automatisch auf `production`

### 2.6 Datenschutzerklärung veröffentlichen
`PRIVACY.md` ausfüllen, unter einer öffentlichen URL ablegen und diese in App
Store Connect eintragen. Zusätzlich braucht es eine **Support-URL**.

## 3. Angaben in App Store Connect

### App-Datenschutz („Nutrition Label“)
Wähle **„Es werden keine Daten erfasst“**. Das trifft zu: Die Daten wandern
ausschliesslich in die private iCloud des Nutzers, nicht zum Anbieter. Diese
Angabe muss zum Privacy Manifest passen – hier tut sie das.

### Alterseinstufung
4+ – kein anstössiger Inhalt, keine nutzergenerierten öffentlichen Inhalte, keine
Werbung, keine Käufe.

### Beschreibungstext
Erwähne, dass die App iCloud für Synchronisation und Freigabe verwendet, und dass
Wechselkurse von der EZB stammen. Nenne keine Funktionen, die es nicht gibt –
Abweichungen zwischen Beschreibung und App sind ein häufiger Ablehnungsgrund.

### Hinweise für die Prüfung („App Review Information“)
Formuliere dort sinngemäss:

> Die App benötigt kein Konto. Zum Prüfen des Teilens werden zwei Geräte mit
> unterschiedlichen iCloud-Accounts gebraucht; ohne iCloud ist die App
> vollständig nutzbar, nur ohne Synchronisation. Wechselkurse stammen vom
> öffentlichen XML-Feed der Europäischen Zentralbank.

## 4. Typische Ablehnungsgründe – und wie diese App sie vermeidet

| Grund | Status |
|---|---|
| Fehlendes oder falsches Privacy Manifest | vorhanden und inhaltlich passend |
| Datenschutzangaben widersprechen dem Verhalten der App | keine Erhebung, keine Netzwerkziele ausser der EZB |
| App unbrauchbar ohne Netz | Offline-First, voll funktionsfähig |
| Abstürze bei fehlendem iCloud-Account | automatischer Rückfall auf den Lokalmodus |
| Berechtigung ohne erkennbaren Zweck | es wird keine einzige angefordert |
| Platzhalterinhalte oder Blindtext | keine vorhanden |
| Fehlendes App-Icon | **noch zu erledigen (2.1)** |

## 5. Nach der Freigabe

* Modelländerungen nur noch mit Migration
* CloudKit-Schemaänderungen sind additiv: Felder dürfen dazukommen, bestehende
  weder umbenannt noch gelöscht werden
* Vor jedem Update das Schema erneut in die Produktion überführen
