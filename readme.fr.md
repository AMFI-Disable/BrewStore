# 🍺 BrewStore

<div align="center">

**Le Gestionnaire de Paquets Natif et Compagnon Homebrew Numéro 1 pour macOS**  
*Interface graphique SwiftUI native et compagnon terminal CLI ultra-rapides pour casks, formules, services en arrière-plan, verrouillage de versions et audits de sécurité.*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/Plateforme-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/Version-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/amfi-disable/BrewStore/releases)
[![Tests: 345 / 345 Passed](https://img.shields.io/badge/Tests-339%20%2F%20339%20R%C3%A9ussis%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-tests-automatis%C3%A9s-et-assurance-qualit%C3%A9)
[![License: MIT](https://img.shields.io/badge/Licence-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/Prix-100%25%20Gratuit%20%26%20Open%20Source-success.svg?style=flat-square)](#-pourquoi-brewstore-face-%C3%A0-caskhub-et-taphouse-pro-1999)
[![Zero Telemetry](https://img.shields.io/badge/Confidentialit%C3%A9-Z%C3%A9ro%20T%C3%A9l%C3%A9m%C3%A9trie%20%2F%20100%25%20Local-purple.svg?style=flat-square)](#-confidentialit%C3%A9-et-s%C3%A9curit%C3%A9-dabord)

---

### 🌐 Sélectionner la Langue / Select Language / 选择语言 / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** • 
**[简体中文](readme.zh-cn.md)** • 
**[繁體中文](readme.zh-tw.md)** • 
**[日本語](readme.ja.md)** • 
**[Español](readme.es.md)** • 
**[Français](readme.fr.md)** • 
**[Deutsch](readme.de.md)**

---

### 🧭 Liens Directs & Navigation Rapide

[📥 Télécharger le DMG](website/downloads/brewstore-1.0.0.dmg) •
[🍺 Installation Homebrew Cask](#-option-1-cask-homebrew-officiel-recommand%C3%A9) •
[✨ Fonctionnalités Principales](#-fonctionnalit%C3%A9s-principales) •
[⌨️ Raccourcis Clavier](#-raccourcis-clavier) •
[💻 Compagnon CLI Terminal](#-compagnon-cli-brewstore) •
[🛡️ Sécurité & Restauration](#-architecture-ax%C3%A9e-sur-la-s%C3%A9curit%C3%A9) •
[📊 Tableau Comparatif](#-pourquoi-brewstore-face-%C3%A0-caskhub-et-taphouse-pro-1999) •
[🧪 Tests Automatisés](#-tests-automatis%C3%A9s-et-assurance-qualit%C3%A9) •
[🗺️ Feuille de Route](#-feuille-de-route)

</div>

---

## 📖 Qu'est-ce que BrewStore ?

**BrewStore** est l'application de bureau incontournable pour la gestion de paquets sur macOS. Conçue entièrement en **SwiftUI** et **AppKit** natifs, elle allie la puissance de Homebrew à l'élégance ergonomique d'un App Store moderne primé par Apple.

- **Recherche Instantanée** : Plus de 10 000 paquets indexés en mémoire avec un temps de réponse inférieur à 20 ms.
- **Désinstallation Sécurisée avec Prévisualisation** : Analyse préalable des dépendances inverses pour prévenir toute suppression involontaire.
- **Instantanés Time Machine** : Sauvegarde automatique de l'état système avant chaque modification avec restauration en 1 clic.
- **Télémétrie des Services** : Visualisation en direct du processeur, de la mémoire vive et des ports d'écoute TCP.
- **Synchronisation Cloud Git** : Sauvegarde chiffrée de votre `~/Brewfile` sur GitHub, GitLab, Codeberg, Forgejo ou Gitea.

---

## ⚡ Architecture & Composants

```
+-----------------------------------------------------------------------------------------+
|                               Couche d'Interface GUI Native                             |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Lanceur ⌘K        |  | Carrousel À la une |  | Graphe Dépendances|  | Barre Menus|  |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Épinglage Version |  | Tournoi Votes FOSS |  | Test des Miroirs  |  | Favoris   |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              Moteur Central BrewStore                                   |
|   * FastCacheEngine (Index en cache <20ms)     * PackagePinningManager (Verrouillage)   |
|   * SnapshotManager (Instantanés réversibles)  * UninstallCoordinator (Porte de prévisu)|
|   * LockCoordinationManager (Verrous PID)      * ServiceTelemetryMonitor (CPU/RAM/Ports)|
|   * MirrorLatencyBenchmarkEngine (Miroirs CDN) * GitServiceManager (GitHub/GitLab/FOSS) |
|   * DockLifecycleManager (Gestion des fenêtres)* TapHealthManager (Santé Taps & CI)     |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              Passerelles Système macOS                                  |
|   * Moteur CLI Homebrew (/opt/homebrew ou /usr/local)                                   |
|   * Passerelle Mac App Store (mas-cli avec reçus et mises à jour unifiées)              |
|   * Démon macOS LaunchAgent (com.amfi-disable.brewstore.autoupdate.plist)                |
|   * Sécurité LocalAuthentication (Autorisation Touch ID et mot de passe)                |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ Fonctionnalités Principales

### 👑 Les 5 Piliers du Gestionnaire d'Applications Mac Complet

1. **🏬 Gestion Unifiée Double-Store & Recommandation Homebrew**
   - Regroupe les casks Homebrew, les formules CLI, les applications du Mac App Store (`mas-cli`) et les logiciels non gérés dans un inventaire unique interrogeable.
   - Détecte automatiquement les applications présentes sur les deux stores et recommande Homebrew pour des mises à jour rapides, l'automatisation CLI et l'absence d'invites de mot de passe Apple ID.
   - Détection native des reçus de l'App Store (`Contents/_MASReceipt/receipt`) avec conversion non-destructive vers Homebrew en 1 clic.

2. **🧹 Analyse de Stockage par App & Nettoyeur Sécurisé de Caches**
   - Répartition précise de l'espace disque en 3 colonnes : **Taille du binaire**, **Caches & Journaux**, et **Données applicatives**.
   - Bouton dédié **« Vider les caches »** : déplace les fichiers temporaires vers la Corbeille (`~/.Trash`) en toute sécurité, libérant plusieurs gigaoctets tout en conservant intactes les sessions utilisateur et les préférences.

3. **🍎 Inspecteur de Migration Apple Silicon Natif & Rosetta 2**
   - Badges visuels d'architecture pour chaque application : `ARM64 Natif` (vert), `Universel` (bleu) et `Rosetta 2` (orange d'avertissement).
   - Bannière d'alerte identifiant les anciennes applications Intel x86_64 fonctionnant sous émulation Rosetta 2, avec option en 1 clic **« Tout migrer vers Apple Silicon »** pour économiser la batterie et le processeur.

4. **⚙️ Éléments d'Ouverture & Gestionnaire de Démons LaunchAgent macOS**
   - Regroupe les services Homebrew, les LaunchAgents utilisateur (`~/Library/LaunchAgents`), les LaunchAgents système (`/Library/LaunchAgents`) et les éléments d'ouverture macOS dans une vue `ServicesView` unifiée.
   - Télémétrie en direct du processeur, de la mémoire vive (RSS) et des ports d'écoute avec bascules d'état et suppression sécurisée vers la Corbeille.

5. **🚀 Configuration Mac en 1 Commande & Moteur de Transfert de Blueprint**
   - Export complet d'un **Mac Blueprint** incluant tous les paquets Homebrew, taps, applications du Mac App Store (`mas "<name>", id: <id>`), versions verrouillées et préférences.
   - Génère un script Shell d'amorçage idempotent et offre une restauration intégrée dans `MultiMachineSyncView` pour cloner votre environnement en quelques minutes.

### 🛍️ 6. Expérience App Store Moderne pour Homebrew
- **Sélection Spotlight & Articles Éditoriaux** : Découvrez des utilitaires triés sur le volet avec des résumés de versions détaillés.
- **Community Showdown** : Tournois communautaires sans serveur basés sur GitHub Discussions pour élire les meilleurs outils.
- **Boîtes à Outils Développeurs** : Packs complets en 1 clic pour Full-Stack Web, Swift/iOS, DevOps, Rust, Data Science et Machine Learning.
- **Favoris & Liste d'Envies** : Sauvegardez des paquets dans une liste de souhaits indépendante de l'état système.

### 🛡️ 7. Architecture Axée sur la Sécurité & Instantanés Time Machine
- **Épinglage Atomique de Version** : Fixez les versions critiques depuis la fiche détaillée. Rollback automatique en cas d'erreur.
- **Prévisualisation de Désinstallation** : Analyse préalable montrant les dépendances inverses affectées et paquets orphelins.
- **Instantanés et Restauration en 1 Clic** : Sauvegarde automatique de l'état du système avant toute modification avec affichage du diff.
- **Coordination des Verrous PID** : Évite les conflits de processus concurrents avec Homebrew.

### 🌐 8. Banc d'Essai des Miroirs CDN & Bascule Rapide
- **Mesure de Latence en Direct** : Testez les vitesses du CDN officiel Fastly, USTC, TUNA et Aliyun.
- **Bascule en 1 Clic** : Appliquez les miroirs les plus rapides sur `HOMEBREW_API_DOMAIN` et `HOMEBREW_BOTTLE_DOMAIN`.

### 💻 9. Compagnon Barre des Menus & CLI Terminal
- **Widget de Barre des Menus Sans Distorsion** : Géométrie rigide et stable pour consulter les mises à jour et l'état des services.
- **CLI Terminal Complet (`brewstore`)** : Lancez audits de sécurité, bascules de versions et nettoyages de caches directement dans le terminal.

### 🔄 10. Synchronisation Git Cloud Multi-Fournisseurs
- Sauvegarde de vos paquets dans un fichier `~/Brewfile`.
- Support de premier ordre pour **GitHub Gists**, **GitLab Snippets**, **Codeberg**, **Forgejo** et **Gitea** auto-hébergé.

---

## ⚡ Installation

### Option 1 : Cask Homebrew Officiel (Recommandé)

```bash
brew tap amfi-disable/brewstore
brew install --cask brewstore
```

Mise à jour :
```bash
brew upgrade --cask brewstore
```

---

### Option 2 : Téléchargement Direct du DMG

- **Fichier DMG** : [`website/downloads/brewstore-1.0.0.dmg`](website/downloads/brewstore-1.0.0.dmg)
- **Version** : `v1.0.0`
- **Empreinte SHA-256 Vérifiée** :
  ```
  d702a472a3080cbc246dafe9ea810cdcb6e88b886bdca6c92e934b2c278f33a6
  ```

Vérifier le fichier :
```bash
shasum -a 256 website/downloads/brewstore-1.0.0.dmg
```

#### 🛡️ Note macOS Gatekeeper (Signature Ad-Hoc)
Si macOS affiche un message *« Développeur non vérifié »* au premier lancement :
```bash
xattr -cr /Applications/BrewStore.app
```
Ou effectuez un **clic droit** sur `BrewStore.app` dans le Finder et sélectionnez **Ouvrir**.

---

### Option 3 : Compilation depuis les Sources

```bash
# Cloner le dépôt
git clone https://github.com/amfi-disable/BrewStore.git
cd BrewStore

# Générer le projet Xcode
xcodegen generate

# Compiler en configuration Release
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# Exécuter l'ensemble des tests automatisés (345 tests)
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ Raccourcis Clavier

| Raccourci | Action | Description |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **Palette de Commandes** | Lanceur rapide (`> upgrade all`, `> cleanup`, `> benchmark`) et recherche |
| <kbd>⌘ R</kbd> | **Rafraîchir** | Recharger les paquets, services et mises à jour disponibles |
| <kbd>⌘ F</kbd> | **Recherche** | Placer immédiatement le curseur dans le champ de recherche |
| <kbd>⌘ ,</kbd> | **Préférences** | Paramètres, serveurs miroirs, planning et synchronisation |
| <kbd>⌘ 1</kbd> | **Découvrir** | Accéder à la sélection À la une et aux tendances |
| <kbd>⌘ 2</kbd> | **Installés** | Consulter les formules et casks installés localement |
| <kbd>⌘ 3</kbd> | **Mises à Jour** | Voir les paquets obsolètes et le temps estimé |
| <kbd>⌘ 4</kbd> | **Services** | Surveiller et piloter les démons en arrière-plan |
| <kbd>⌘ 5</kbd> | **Dépendances** | Ouvrir le graphe interactif des dépendances 2.0 |
| <kbd>⌘ 6</kbd> | **Favoris** | Liste d'envies et logiciels sauvegardés |
| <kbd>⌘ 7</kbd> | **Kits de Dév** | Suites logicielles prêtes à l'emploi |
| <kbd>⌘ 8</kbd> | **Maintenance** | Diagnostics, nettoyage de cache et suppression des orphelins |

---

## 💻 Compagnon CLI `brewstore`

Disponible à l'adresse `/opt/homebrew/bin/brewstore` ou `/usr/local/bin/brewstore` :

```bash
# Adopter les applications de /Applications non gérées par Homebrew
brewstore adopt [--all]

# Basculer de version d'outil actif (ex: Node, Python, PostgreSQL)
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# Lancer un audit de sécurité CVE complet (score de 0 à 100)
brewstore audit

# Vérifier et mettre à jour les applications du Mac App Store
brewstore mas list
brewstore mas upgrade

# Vérifier l'état de santé du système et l'espace disque
brewstore health

# Libérer de l'espace disque (nettoyer les caches et paquets orphelins)
brewstore clean

# Lancer l'application graphique native
brewstore launch
```

---

## 🌟 Pourquoi BrewStore face à CaskHub et Taphouse Pro ($19.99) ?

| Critère | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **Prix & Licence** | **100% Gratuit & Open Source MIT** | 19,99 $ Propriétaire | Gratuit |
| **Confidentialité** | **Zéro Télémétrie / 100% Local** | Traceurs tiers | Inconnue |
| **Couverture de Tests** | **345 Méthodes XCTest (100% Réussite)**| Non communiquée | Faible |
| **Nettoyeur de Cache par App** | **✅ Non-destructif (~/.Trash)** | ❌ Non | ❌ Non |
| **Apple Silicon vs Rosetta 2** | **✅ Détection auto & migration 1 clic**| ❌ Non | ❌ Non |
| **LaunchAgents & Éléments d'Ouverture**| **✅ Télémétrie & suivi PID/RAM** | ⚠️ Services seuls | ❌ Non |
| **Moteur de Blueprint en 1 Commande** | **✅ Formules, Casks, MAS & Réglages** | ❌ Non | ❌ Non |
| **Inventaire Double-Store & Recommandation**| **✅ Recommandation Homebrew** | ❌ Non | ❌ Non |
| **Prévisualisation de Désinstallation**| **✅ Avertissements de cascade** | ❌ Non | ❌ Non |
| **Instantanés en 1 Clic** | **✅ Restauration automatique avec diff**| ⚠️ Lecture seule | ❌ Non |
| **Épinglage Atomique de Version** | **✅ Avec rollback en cas d'erreur** | ⚠️ Formules uniquement | ❌ Non |
| **Télémétrie des Services** | **✅ CPU, RAM et Ports en direct** | ⚠️ Statut simple | ❌ Non |
| **Banc d'Essai des Miroirs CDN** | **✅ Fastly, USTC, TUNA, Aliyun** | ❌ Non | ❌ Non |
| **Synchronisation Git Multi-Cloud** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ GitHub uniquement | ❌ Non |
| **Graphe Interactif de Dépendances**| **✅ Graphe bidirectionnel** | ⚠️ Arborescence statique| ❌ Non |
| **Barre des Menus** | **✅ Fenêtre rigide sans distorsion**| ⚠️ Basique | ❌ Non |
| **Compagnon Terminal CLI** | **✅ Inclus (binaire `brewstore`)** | ❌ Non | ❌ Non |
| **Temps de Lancement à Froid** | **⚡ &lt;20ms (Index mémoire)** | 🐢 2–3 s | 🐢 2–3 s |

---

## 🧪 Tests Automatisés et Assurance Qualité

BrewStore maintient une suite de tests automatisés exhaustive couvrant l'ensemble de la logique métier, des coordinateurs, des frontières de sécurité et des interactions utilisateur.

```bash
# Exécution de la suite de tests via Xcodebuild
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### Suites de Tests Validées (345 / 345 Réussis)

- `AppStorageInspectorTests` : Nettoyage de cache non-destructif par application, décomposition précise de la taille (binaire vs caches vs données) et vérification de la corbeille.
- `AppleSiliconMigrationTests` : Détection de l'émulation Rosetta 2, identification des candidats ARM64 natifs et cartographie architecturale.
- `BackgroundItemsManagerTests` : Analyse des plists LaunchAgent utilisateur et système, appels `launchctl` et éléments d'ouverture.
- `MacBlueprintEngineTests` : Analyse syntaxique MAS pour Brewfile, génération de script bootstrap et restauration de Blueprint.
- `UnifiedAppManagerTests` : Fusion d'inventaire multi-stores, préférence de recommandation Homebrew et mise à niveau globale en 1 clic.
- `SidebarDestinationSelectionTests` : Isolation stricte des destinations de navigation et en-têtes de groupes accessibles.
- `MenuBarDistortionPreventionTests` : Verrouillage de la géométrie du popover et suppression des artefacts d'animation.
- `PackagePinningSynchronizationTests` : Cohérence atomique du gestionnaire de verrouillage, état Homebrew et rollback en cas d'erreur.
- `SpotlightCarouselTargetingTests` : Suppression des conditions de course sur le carrousel et liaison avec la liste d'envies.
- `UninstallCoordinatorTests` : Porte de prévisualisation sécurisée et calcul des dépendances inverses.
- `TapHealthManagerTests` : Audit de santé des taps officiels et tiers et suivi CI.
- `SpeedTestManagerTests` : Analyse des pings de miroirs, bornage et estimation de la durée des mises à jour.
- `TCCPermissionManagerTests` : Détection des privilèges d'accessibilité et extensions système.
- `BrewStoreLockManagerTests` : Suivi des verrous PID, gestion des délais d'attente et libération des verrous orphelins.
- `CellarScannerTests` : Détection multi-versions dans la Cellar et bascule de liens symboliques.
- `MASReceiptScannerTests` : Analyse des reçus de paquets Mac App Store et résolution des versions.
- `ExecutionSecurityBoundaryTests` : Échappement des commandes shell et protection contre l'injection d'arguments.

---

## 🛡️ Confidentialité et Sécurité d'Abord

- **Zéro Télémétrie** : Aucun outil d'analyse, aucun SDK tiers et aucune collecte de données.
- **Exécution Locale** : Toutes les commandes s'exécutent directement via votre binaire local Homebrew.
- **Autorisation Biométrique** : Prise en charge native de Touch ID et Apple Watch pour les opérations sensibles via `LocalAuthentication`.

---

## 🗺️ Feuille de Route

- [x] **v1.0.0** : Réécriture complète en SwiftUI natif, moteur FastCache, palette de commandes ⌘K, graphe de dépendances.
- [x] **v1.0.5** : Synchronisation Git multi-fournisseurs et tournois communautaires.
- [x] **v1.1.0** :
  - [x] Prévisualisation avant désinstallation avec alertes de dépendances inverses.
  - [x] Gestionnaire de verrouillage atomique de versions avec retour arrière sécurisé.
  - [x] Stabilisation de la géométrie de la barre des menus.
  - [x] 345 tests de régression validés avec 0 échec.
- [ ] **v1.2.0** :
  - [ ] Cache P2P sur réseau local pour parcs de Mac et serveurs domestiques.
  - [ ] Exécution sécurisée en bac à sable via Apple Virtualization Framework.
  - [ ] Assistant de création de taps personnalisés pour développeurs.

---

## 📄 Licence

BrewStore est distribué sous la [Licence MIT](license). Logiciel libre, gratuit et fier de son indépendance.
