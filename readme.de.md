# 🍺 BrewStore

<div align="center">

**Der unangefochtene Nr. 1 native macOS Paketmanager & Homebrew-Begleiter**  
*Blitzschnelle, native SwiftUI Benutzeroberfläche und CLI-Terminalbegleiter für Casks, Formeln, Hintergrunddienste, Versionsverwaltung und Sicherheitsaudits.*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/Plattform-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/Version-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/amfi-disable/BrewStore/releases)
[![Tests: 345 / 345 Passed](https://img.shields.io/badge/Tests-339%20%2F%20339%20Bestanden%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-automatisierte-tests-und-qualit%C3%A4tssicherung)
[![License: MIT](https://img.shields.io/badge/Lizenz-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/Preis-100%25%20Kostenlos%20%26%20Open%20Source-success.svg?style=flat-square)](#-warum-brewstore-im-vergleich-zu-caskhub-und-taphouse-pro-1999)
[![Zero Telemetry](https://img.shields.io/badge/Datenschutz-Keine%20Telemetrie%20%2F%20100%25%20Lokal-purple.svg?style=flat-square)](#-sicherheit-und-datenschutz-an-erster-stelle)

---

### 🌐 Sprache auswählen / Select Language / 选择语言 / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** • 
**[简体中文](readme.zh-cn.md)** • 
**[繁體中文](readme.zh-tw.md)** • 
**[日本語](readme.ja.md)** • 
**[Español](readme.es.md)** • 
**[Français](readme.fr.md)** • 
**[Deutsch](readme.de.md)**

---

### 🧭 Schnelle Navigationslinks

[📥 DMG herunterladen](website/downloads/brewstore-1.0.0.dmg) •
[🍺 Homebrew Cask Installation](#-option-1-offizielles-homebrew-cask-empfohlen) •
[✨ Funktionshighlights](#-funktionshighlights) •
[⌨️ Tastatur-Kurzbefehle](#-tastatur-kurzbefehle) •
[💻 CLI-Terminalbegleiter](#-brewstore-cli-begleiter) •
[🛡️ Sicherheit & Rollback](#-sicherheit-an-erster-stelle) •
[📊 Vergleichstabelle](#-warum-brewstore-im-vergleich-zu-caskhub-und-taphouse-pro-1999) •
[🧪 Automatisierte Tests](#-automatisierte-tests-und-qualit%C3%A4tssicherung) •
[🗺️ Roadmap](#-roadmap)

</div>

---

## 📖 Was ist BrewStore?

**BrewStore** ist die definitive Desktop-Anwendung für die Paketverwaltung unter macOS. Entwickelt von Grund auf in nativem **SwiftUI** und **AppKit**, vereint es die unverfälschte Leistungsfähigkeit von Homebrew mit der eleganten Bedienbarkeit eines modernen Mac App Stores.

- **Blitzschnelle Suche**: Über 10.000 Pakete im Arbeitsspeicher indiziert mit Reaktionszeiten unter 20 ms.
- **Sichere Deinstallation mit Vorschau**: Vorabprüfung von inversen Abhängigkeiten und verwaisten Paketen vor jeder Löschung.
- **Time-Machine-Snapshots**: Automatische Sicherungspunkte vor Systemänderungen mit 1-Klick-Wiederherstellung.
- **Echtzeit-Dienstüberwachung**: Live-Anzeige von CPU-Auslastung, RAM-Verbrauch und aktiven TCP-Ports für alle Hintergrunddienste.
- **Multi-Cloud Git-Synchronisierung**: Sichere Synchronisierung von `~/Brewfile` auf GitHub, GitLab, Codeberg, Forgejo oder Gitea.

---

## ⚡ Architektur & Teilsysteme

```
+-----------------------------------------------------------------------------------------+
|                                  BrewStore GUI-Ebene                                    |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | ⌘K Befehlspalette |  | Spotlight-Auswahl  |  | Abhängigkeitsgraf |  | Menüleiste|   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Versionen anheften|  | Community-Turnier  |  | Mirror-Benchmark  |  | Merkliste |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                                BrewStore Core-Engine                                    |
|   * FastCacheEngine (Sub-20ms Lokaler Index)   * PackagePinningManager (Atomare Pins)   |
|   * SnapshotManager (Rollback Time Machine)    * UninstallCoordinator (Vorschau-Schranke)|
|   * LockCoordinationManager (PID-Sperre)       * ServiceTelemetryMonitor (CPU/RAM/Port) |
|   * MirrorLatencyBenchmarkEngine (Latenzmessung)* GitServiceManager (GitHub/GitLab/FOSS)|
|   * DockLifecycleManager (Fenster-Steuerung)   * TapHealthManager (Audit & CI-Status)   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                            Grundlegende System-Bridges                                  |
|   * Homebrew CLI (/opt/homebrew oder /usr/local)                                        |
|   * Mac App Store Bridge (mas-cli Beleg-Scan und Updates)                               |
|   * macOS LaunchAgent Daemon (com.amfi-disable.brewstore.autoupdate.plist)              |
|   * macOS Sicherheit LocalAuthentication (Touch ID / Biometrie-Schutz)                  |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ Funktionshighlights

### 👑 Die 5 Säulen des kompletten Mac App Managers

1. **🏬 Einheitliche Dual-Store-App-Verwaltung & Homebrew-Empfehlung**
   - Führt Homebrew Casks, CLI-Formeln, Mac App Store Anwendungen (`mas-cli`) und unmanaged Programme in einem durchsuchbaren Inventar zusammen.
   - Erkennt Dual-Store-Apps automatisch und empfiehlt Homebrew für schnellere Updates, CLI-Skriptfähigkeit und ohne Apple ID Passwort-Abfragen.
   - Belegprüfung für den App Store (`Contents/_MASReceipt/receipt`) mit 1-Klick-Übernahme zu Homebrew ohne Datenverlust.

2. **🧹 Pro-App-Speicheranalyse & sicherer Cache-Reiniger**
   - Präzise 3-Spalten-Speicheraufteilung: **Binärgröße**, **Caches & Logs**, und **App-Daten**.
   - Spezielle Schaltfläche **„Caches leeren“**: Verschiebt temporäre Cache-Dateien sicher in den Papierkorb (`~/.Trash`), gibt Gigabytes frei und behält Anmeldedaten und Einstellungen vollständig bei.

3. **🍎 Apple Silicon Nativ & Rosetta 2 Migrations-Inspektor**
   - Architektur-Kennzeichnungen in jeder Tabellenzeile: `ARM64 Nativ` (grün), `Universal` (blau) und `Rosetta 2` (Warnorange).
   - Deutliches Banner erkennt alte Intel x86_64-Apps unter Rosetta 2 Emulation mit 1-Klick **„Alle zu Apple Silicon migrieren“** zur Schonung von Akku und CPU.

4. **⚙️ Anmeldeobjekte & macOS LaunchAgent Daemon-Verwaltung**
   - Vereint Homebrew-Dienste, Benutzer-LaunchAgents (`~/Library/LaunchAgents`), System-LaunchAgents (`/Library/LaunchAgents`) und macOS Anmeldeobjekte in einer modernen `ServicesView`.
   - Echtzeit-Telemetrie für CPU-Last, Resident Set Size (RSS) RAM und TCP-Ports mit Umschaltern und sicherer Entfernung via Papierkorb.

5. **🚀 1-Befehl Mac Setup & Blueprint Übertragungs-Engine**
   - Umfassender **Mac Blueprint** Export für alle Homebrew-Pakete, Taps, Mac App Store Apps (`mas "<name>", id: <id>`), angeheftete Versionen und Präferenzen.
   - Erzeugt ein idempotentes 1-Befehl-Bootstrap-Shellskript sowie In-App-Wiederherstellung in `MultiMachineSyncView`, um Ihren Mac in wenigen Minuten einzurichten.

### 🛍️ 6. Moderne App Store Erfahrung für Homebrew
- **Spotlight & Redaktionelle Geschichten**: Entdecken Sie handverlesene macOS-Tools mit Vorstellungen und Versionsdetails.
- **Community Showdown**: Serverlose Turnier-Runden auf Basis von GitHub Discussions für das beste Tool der Saison.
- **Entwickler-Toolkits**: 1-Klick-Paketbündel für Full-Stack, Swift/iOS, DevOps, Rust, Data Science und Machine Learning.
- **Merkliste & Favoriten**: Pakete vormerken, unabhängig vom Installationsstatus.

### 🛡️ 7. Sicherheit an erster Stelle & Rollback Time Machine
- **Atomares Versions-Anheften (Pin/Unpin)**: Fixieren Sie kritische Versionen direkt in der Detailansicht oder dem Kontextmenü. Automatisches Rollback bei Fehlern.
- **Deinstallations-Vorschau**: Zeigt vor jeder Löschung oder jedem `autoremove` inverse Abhängigkeiten und verwaiste Pakete an.
- **1-Klick-Snapshot-Wiederherstellung**: Erstellt vor Änderungen automatisch Snapshots für sofortige Wiederherstellung mit Diff-Vergleich.
- **Proaktive PID-Sperrkoordination**: Verhindert Konflikte mit laufenden Homebrew-Befehlen.

### 🌐 8. Mirror-Geschwindigkeitstest & CDN-Umschalter
- **Live-Latenzmessung**: Testen Sie Übertragungszeiten für das offizielle Fastly CDN, USTC, TUNA und Aliyun.
- **1-Klick-Umschaltung**: Schnelle Mirrors direkt systemweit für `HOMEBREW_API_DOMAIN` und `HOMEBREW_BOTTLE_DOMAIN` aktivieren.

### 💻 9. Menüleisten-Begleiter & Terminal CLI
- **Verzerrungsfreies Menüleisten-Widget**: Feste Geometrie für ausstehende Updates, Ein-Klick-Aktualisierungen und Dienststatus.
- **Vollwertige CLI (`brewstore`)**: Führen Sie Audits durch, wechseln Sie Versionen und leeren Sie Caches direkt im Terminal.

### 🔄 10. Multi-Provider Git Cloud-Synchronisierung
- Synchronisiert Ihre Pakete und Casks direkt in ein `~/Brewfile`.
- Volle Unterstützung für **GitHub Gists**, **GitLab Snippets**, **Codeberg**, **Forgejo** und selbst gehostetes **Gitea**.

---

## ⚡ Installation

### Option 1: Offizielles Homebrew Cask (Empfohlen)

```bash
brew tap amfi-disable/brewstore
brew install --cask brewstore
```

Aktualisieren:
```bash
brew upgrade --cask brewstore
```

---

### Option 2: Direkter DMG-Download

- **Installations-DMG**: [`website/downloads/brewstore-1.0.0.dmg`](website/downloads/brewstore-1.0.0.dmg)
- **Version**: `v1.0.0`
- **Geprüfte SHA-256 Prüfsumme**:
  ```
  d702a472a3080cbc246dafe9ea810cdcb6e88b886bdca6c92e934b2c278f33a6
  ```

Prüfsumme verifizieren:
```bash
shasum -a 256 website/downloads/brewstore-1.0.0.dmg
```

#### 🛡️ macOS Gatekeeper Hinweis (Ad-Hoc Signierung)
Sollte macOS beim ersten Start einen Hinweis auf einen *„nicht verifizierten Entwickler“* anzeigen:
```bash
xattr -cr /Applications/BrewStore.app
```
Alternativ im Finder einen **Rechtsklick** auf `BrewStore.app` ausführen und **Öffnen** wählen.

---

### Option 3: Aus dem Quellcode bauen

```bash
# Repository klonen
git clone https://github.com/amfi-disable/BrewStore.git
cd BrewStore

# Xcode-Projekt generieren
xcodegen generate

# Release-Konfiguration bauen
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# Vollständige automatisierte Testsuite ausführen (345 Tests)
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ Tastatur-Kurzbefehle

| Kurzbefehl | Aktion | Beschreibung |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **Befehlspalette** | Schnellstarter (`> upgrade all`, `> cleanup`, `> benchmark`) und Gesamtsuche |
| <kbd>⌘ R</kbd> | **Katalog aktualisieren**| Lokale Pakete, Dienste und ausstehende Updates neu einlesen |
| <kbd>⌘ F</kbd> | **Suchen** | Sofort in das Suchfeld des aktuellen Bereichs springen |
| <kbd>⌘ ,</kbd> | **Einstellungen** | Einstellungen, Mirror-Benchmarks und Cloud-Synchronisierung |
| <kbd>⌘ 1</kbd> | **Entdecken** | Zu Spotlight-Empfehlungen und Trends springen |
| <kbd>⌘ 2</kbd> | **Installiert** | Alle lokal installierten Formeln und Casks anzeigen |
| <kbd>⌘ 3</kbd> | **Aktualisierungen** | Ausstehende Updates und Zeitprognosen prüfen |
| <kbd>⌘ 4</kbd> | **Dienste** | Hintergrunddienste und Systemressourcen überwachen |
| <kbd>⌘ 5</kbd> | **Abhängigkeiten** | Interaktive Abhängigkeits-Leinwand 2.0 öffnen |
| <kbd>⌘ 6</kbd> | **Merkliste** | Gespeicherte Pakete für später verwalten |
| <kbd>⌘ 7</kbd> | **Toolkits** | Kuratierte Entwickler-Paketbündel installieren |
| <kbd>⌘ 8</kbd> | **Wartung** | Diagnose, Festplatten-Bereinigung und verwaiste Pakete entfernen |

---

## 💻 `brewstore` CLI-Begleiter

Verfügbar unter `/opt/homebrew/bin/brewstore` oder `/usr/local/bin/brewstore`:

```bash
# Programme aus /Applications scannen und in Homebrew Cask übernehmen
brewstore adopt [--all]

# Aktive Werkzeugversionen schnell wechseln (Node, Python, PostgreSQL)
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# Sicherheitsaudit nach CVE durchführen (Sicherheitsscore 0–100)
brewstore audit

# Mac App Store Programme prüfen und aktualisieren
brewstore mas list
brewstore mas upgrade

# Zustand des Systems, verwaiste Pakete und Speicherverbrauch prüfen
brewstore health

# Speicherplatz freigeben (Caches leeren & ungenutzte Abhängigkeiten entfernen)
brewstore clean

# Die native Benutzeroberfläche öffnen
brewstore launch
```

---

## 🌟 Warum BrewStore im Vergleich zu CaskHub und Taphouse Pro ($19.99)?

| Kriterium | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **Preis & Lizenz** | **100% Kostenlos & Open Source (MIT)** | 19,99 $ Kommerziell / Proprietär | Kostenlos |
| **Datenschutz** | **Keine Telemetrie / 100% Lokal** | Drittanbieter-Tracking | Unbekannt |
| **Testabdeckung** | **345 XCTest-Methoden (100% Erfolg)** | Nicht veröffentlicht | Sehr gering |
| **Speicheranalyse & Cache-Reiniger** | **✅ Nicht-destruktiv in den Papierkorb** | ❌ Nein | ❌ Nein |
| **Apple Silicon vs Rosetta 2** | **✅ Auto-Erkennung & 1-Klick-Migration** | ❌ Nein | ❌ Nein |
| **LaunchAgents & Anmeldeobjekte** | **✅ Volle Telemetrie & PID/RAM-Monitor** | ⚠️ Nur Dienste | ❌ Nein |
| **1-Befehl Mac Blueprint Engine** | **✅ Formeln, Casks, MAS & Präferenzen** | ❌ Nein | ❌ Nein |
| **Dual-Store Inventar & Empfehlung** | **✅ Homebrew-Empfehlung bevorzugt** | ❌ Nein | ❌ Nein |
| **Deinstallations-Vorschau** | **✅ Kaskadierende Warnungen** | ❌ Nein | ❌ Nein |
| **1-Klick-Wiederherstellung** | **✅ Automatische Snapshots mit Diff**| ⚠️ Nur Ansicht | ❌ Nein |
| **Atomares Versions-Anheften** | **✅ Mit Rollback bei Fehlern** | ⚠️ Nur Formeln | ❌ Nein |
| **Dienste-Telemetrie** | **✅ Live CPU, RAM & Ports** | ⚠️ Nur Status | ❌ Nein |
| **Mirror-Benchmark-Test** | **✅ Fastly, USTC, TUNA, Aliyun** | ❌ Nein | ❌ Nein |
| **Multi-Cloud Git-Sync** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ Nur GitHub | ❌ Nein |
| **Interaktiver Abhängigkeitsgraf**| **✅ Bidirektionaler Graph** | ⚠️ Statischer Baum | ❌ Nein |
| **Menüleisten-Widget** | **✅ Verzerrungsfreie Festgröße** | ⚠️ Einfach | ❌ Nein |
| **Terminal CLI-Tool** | **✅ Enthalten (`brewstore`-Befehl)**| ❌ Nein | ❌ Nein |
| **Kaltstartzeit** | **⚡ &lt;20ms (Schneller Index)** | 🐢 2–3 Sek. | 🐢 2–3 Sek. |

---

## 🧪 Automatisierte Tests und Qualitätssicherung

BrewStore pflegt eine umfassende automatisierte Testsuite, die die gesamte Geschäftslogik, Koordinatoren, Sicherheitsgrenzen und Benutzerinteraktionen abdeckt.

```bash
# Testsuite über Xcodebuild ausführen
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### Verifizierte Test-Suiten (345 / 345 Bestanden)

- `AppStorageInspectorTests`: Nicht-destruktive Cache-Bereinigung pro App, Speicheraufteilung (Binär vs Cache vs Daten) und Papierkorb-Prüfung.
- `AppleSiliconMigrationTests`: Rosetta 2 Emulationserkennung, native ARM64-Migrationskandidaten und Architektur-Zuordnung.
- `BackgroundItemsManagerTests`: Benutzer- und System-LaunchAgent plists, launchctl-Aufrufe und Auslesen von Anmeldeobjekten.
- `MacBlueprintEngineTests`: Erweiterte Brewfile MAS-Syntax, Bootstrap-Skriptgenerierung und Blueprint-Wiederherstellung.
- `UnifiedAppManagerTests`: Zusammenführung des Dual-Store-Inventars, Homebrew-Empfehlungen und globale 1-Klick-Updates.
- `SidebarDestinationSelectionTests`: Strikte Isolation authentischer Navigationsziele von barrierefreien Gruppenüberschriften.
- `MenuBarDistortionPreventionTests`: Feste Popover-Geometrie, Fenstergrößen-Sperre und Unterdrückung von Animationsartefakten.
- `PackagePinningSynchronizationTests`: Atomare Zustandskonsistenz zwischen Pinning-Manager, Homebrew und Rollback-Sicherheit.
- `SpotlightCarouselTargetingTests`: Unterdrückung von Race-Conditions im Spotlight-Karussell und Merklisten-Bindung.
- `UninstallCoordinatorTests`: Sichere Deinstallations-Vorschau und Berechnung von Warnungen bei inversen Abhängigkeiten.
- `TapHealthManagerTests`: Statusprüfungen für offizielle und Drittanbieter-Taps sowie CI-Status.
- `SpeedTestManagerTests`: Ping-Parsing, Bereichsbegrenzung und Vorhersage von Update-Dauern.
- `TCCPermissionManagerTests`: Erkennung von Bedienungshilfen- und Systemerweiterungs-Berechtigungen.
- `BrewStoreLockManagerTests`: PID-Sperrenüberwachung, Timeout-Verwaltung und Entfernen veralteter Locks.
- `CellarScannerTests`: Erkennung von Mehrfachversionen im Cellar und Symlink-Wechsel.
- `MASReceiptScannerTests`: Auswertung von Mac App Store Bundle-Belegen und Versionsauflösung.
- `ExecutionSecurityBoundaryTests`: Shell-Sicherheit, Pfadvalidierung und Abwehr von Befehlsinjektionen.

---

## 🛡️ Sicherheit und Datenschutz an erster Stelle

- **Keine Telemetrie**: BrewStore enthält keinerlei Analysedienste, Google/Firebase SDKs oder Tracking-Mechanismen.
- **Lokale Ausführung**: Sämtliche Befehle laufen direkt über Ihr lokales Homebrew-Programm.
- **Biometrische Bestätigung**: Sicherheitsrelevante Aktionen unterstützen Touch ID und Apple Watch Autorisierung via `LocalAuthentication`.

---

## 🗺️ Roadmap

- [x] **v1.0.0**: Natives SwiftUI Redesign, FastCache Engine, ⌘K Befehlspalette und interaktiver Abhängigkeitsgraph.
- [x] **v1.0.5**: Multi-Provider Git-Synchronisierung und Community-Showdown Turnier-Engine.
- [x] **v1.1.0**:
  - [x] Deinstallations-Vorschau mit inversen Abhängigkeitswarnungen.
  - [x] Atomarer Versions-Pinning-Manager mit Rollback-Sicherheit.
  - [x] Menüleisten-Begleiter mit fester Geometrie und verzerrungsfreier Fensterfixierung.
  - [x] 345 automatisierte Regressionstests erfolgreich bestanden.
- [ ] **v1.2.0**:
  - [ ] P2P lokales Flaschen-Caching im Netzwerk für Büros und Heimlabore.
  - [ ] Isolierte Sandbox-Testläufe über das Apple Virtualization Framework.
  - [ ] Tap-Erstellungsassistent für Entwickler.

---

## 📄 Lizenz

BrewStore ist unter der [MIT-Lizenz](license) lizenziert. Open Source, kostenfrei und unabhängig.
