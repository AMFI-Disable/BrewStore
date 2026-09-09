# 🍺 BrewStore

<div align="center">

**macOS 史上最強のネイティブパッケージマネージャー ＆ Homebrew コンパニオン**  
*超高速・100% ネイティブ SwiftUI GUI ＆ CLI ターミナルコンパニオン。Cask、Formula、バックグラウンドサービス、複数バージョン切り替え、セキュリティ監査を網羅。*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/プラットフォーム-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/リリース-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/amfi-disable/BrewStore/releases)
[![Tests: 339 / 339 Passed](https://img.shields.io/badge/テスト-339%20%2F%20339%20合格%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-自動テストと品質保証)
[![License: MIT](https://img.shields.io/badge/ライセンス-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/価格-100%25%20無料＆オープンソース-success.svg?style=flat-square)](#-なぜ-brewstore-が選ばれるのか)
[![Zero Telemetry](https://img.shields.io/badge/プライバシー-完全ローカル%20%2F%20テレメトリゼロ-purple.svg?style=flat-square)](#-セキュリティとプライバシー最優先)

---

### 🌐 言語を選択 / Select Language / 选择语言 / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** • 
**[简体中文](readme.zh-cn.md)** • 
**[繁體中文](readme.zh-tw.md)** • 
**[日本語](readme.ja.md)** • 
**[Español](readme.es.md)** • 
**[Français](readme.fr.md)** • 
**[Deutsch](readme.de.md)**

---

### 🧭 クイックナビゲーション

[📥 DMG をダウンロード](website/downloads/brewstore-1.0.0.dmg) •
[🍺 Homebrew Cask でインストール](#-オプション-1公式-homebrew-cask-推奨) •
[✨ 主な機能と特徴](#-主な機能と特徴) •
[⌨️ キーボードショートカット](#-便利なキーボードショートカット) •
[💻 CLI ターミナルコンパニオン](#-brewstore-cli-コンパニオン) •
[🛡️ 安全性とロールバック機構](#-安全性最優先のアーキテクチャ) •
[📊 他ツールとの比較表](#-なぜ-brewstore-が選ばれるのか) •
[🧪 自動テスト結果](#-自動テストと品質保証) •
[🗺️ ロードマップ](#-ロードマップ)

</div>

---

## 📖 BrewStore とは？

**BrewStore** は、macOS のためにゼロから設計された次世代のパッケージ管理デスクトップアプリケーションです。純粋な **SwiftUI** と **AppKit** で構築されており、Homebrew の持つ柔軟で強力な機能性と、Apple Design Award レベルの美しい App Store 風 UI を高次元で融合しています。

複数ランタイムを切り替えるエンジニア、クリエイティブツールを揃えるデザイナー、システムデーモンを監視するパワーユーザーまで、すべての Mac ユーザーに快適な操作性を提供します：
- **瞬時のインデックス検索**: メモリ内インデックスキャッシュにより、10,000 件以上のパッケージを 20ms 未満で検索。
- **事前プレビュー付きの安全なアンインストール**: 削除や `autoremove` の実行前に、依存関係の連鎖的な影響を警告。
- **タイムマシン・スナップショット**: 変更前にシステム状態を自動バックアップし、差分比較付きでワンクリック復元。
- **高精度バックグラウンドサービス監視**: 各種デーモン（PostgreSQL、Redis、Nginx 等）の CPU 使用率、常駐メモリ（RSS）、リッスン中の TCP ポートをリアルタイム表示。
- **マルチクラウド Git 同期**: `~/Brewfile` を GitHub Gist、GitLab、Codeberg、Forgejo、自前 Gitea とセキュアに同期。

---

## ⚡ アーキテクチャ構成

```
+-----------------------------------------------------------------------------------------+
|                               BrewStore ネイティブ GUI 層                                |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | ⌘K コマンドパレット |  | Spotlight ピックアップ |  | 依存関係キャンバス |  | メニューバー|   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | バージョンピン留め |  | コミュニティ投票戦  |  | ミラー速度測定    |  | ウィッシュ |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                               BrewStore コアエンジン層                                   |
|   * FastCacheEngine (20ms 高速インデックス)    * PackagePinningManager (原子性ピン留め) |
|   * SnapshotManager (タイムマシン復元)         * UninstallCoordinator (プレビュー関門)  |
|   * LockCoordinationManager (プロセスロック)   * ServiceTelemetryMonitor (CPU/RAM/ポート)|
|   * MirrorLatencyBenchmarkEngine (CDN 測定)    * GitServiceManager (GitHub/GitLab/FOSS) |
|   * DockLifecycleManager (ウィンドウ制御)      * TapHealthManager (Tap 健全性・CI 監視) |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                               基盤システム・ブリッジ層                                  |
|   * Homebrew CLI (/opt/homebrew または /usr/local)                                     |
|   * Mac App Store ブリッジ (mas-cli レシート解析とアップデート統合)                     |
|   * macOS LaunchAgent デーモン (com.amfi-disable.brewstore.autoupdate.plist)            |
|   * macOS セキュリティ LocalAuthentication (Touch ID 指紋認証・パスコード保護)          |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ 主な機能と特徴

### 👑 完全な Mac アプリマネージャー 5 つの柱 (The 5 Pillars)

1. **🏬 2大ストア統合アプリ管理と Homebrew 優先推奨**
   - Homebrew Cask、CLI Formula、Mac App Store アプリ (`mas-cli`)、ローカル未管理アプリを単一の検索可能インベントリに統合。
   - 両ストアに存在するアプリを自動検知し、高速更新・CLI 自動化・Apple ID パスワード入力不要な Homebrew バージョンを優先推奨。
   - アプリレシートスキャン (`Contents/_MASReceipt/receipt`) を標準装備し、ワンクリックで非破壊的に Homebrew 管理へ移行。

2. **🧹 アプリ別ストレージ分析＆キャッシュ安全クリーナー**
   - 詳細画面で 3 項目に分かれた正確なディスク内訳を表示：**バイナリ本体**、**キャッシュ＆ログ**、**アプリデータ**。
   - 専用の **「キャッシュを消去」** ボタン：ユーザーのログインセッションやアプリ設定を完全に保持したまま、数 GB に及ぶ不要キャッシュのみを安全に `~/.Trash` へ退避。

3. **🍎 Apple Silicon ネイティブ ＆ Rosetta 2 移行インスペクター**
   - アプリ一覧にアーキテクチャバッジを表示：`ARM64 Native`（緑）、`Universal`（青）、`Rosetta 2`（警告オレンジ）。
   - Rosetta 2 エミュレーション下で動作している旧 Intel x86_64 アプリを検知する警告バナーを表示し、ワンクリックで **「Apple Silicon ネイティブへ移行」** してバッテリー消費と CPU 負荷を削減。

4. **⚙️ ログイン項目 ＆ macOS LaunchAgent デーモン管理**
   - Homebrew サービス、ユーザー LaunchAgents (`~/Library/LaunchAgents`)、システム LaunchAgents (`/Library/LaunchAgents`)、macOS ログイン項目を刷新された `ServicesView` に集約。
   - リアルタイムな CPU 使用率、物理常駐メモリ（RSS）、リッスン中ポートの監視と、`launchctl` による状態切り替え・安全なゴミ箱退避に対応。

5. **🚀 ワンコマンド Mac 全体ブループリント作成＆移行エンジン**
   - Homebrew パッケージ、Tap、Mac App Store アプリ (`mas "<name>", id: <id>`)、ピン留めバージョン、アプリ設定を網羅した **Mac Blueprint** をエクスポート。
   - 冪等性を備えた 1 行のブートストラップ Shell スクリプトを自動生成し、`MultiMachineSyncView` 内で数分で Mac 環境を完全再現可能。

### 🛍️ 6. Homebrew に現代の App Store 体験を
- **Spotlight ピックアップと独自記事**: 厳選された注目の macOS アプリを特集ストーリーとともに紹介。
- **コミュニティ投票トーナメント (Community Showdown)**: GitHub Discussions を活用した完全サーバーレスの投票トーナメント。
- **開発者向けツールキット**: Web 開発、Swift/iOS、DevOps、Rust、データサイエンス、機械学習向けのワンクリック一括導入パッケージ。
- **ウィッシュリストとお気に入り**: インストール状態とは独立して、気になるツールをブックマーク保存。

### 🛡️ 7. 安全性最優先のアーキテクチャ ＆ ロールバック
- **原子性バージョンピン留め**: 詳細画面やコンテキストメニューから特定バージョンを固定。エラー発生時は自動でロールバック。
- **事前プレビュー付きアンインストール関門**: 依存関係の連鎖的な影響や孤立パッケージを事前にモーダル表示。
- **1クリック・スナップショット復元**: 変更前に自動で差分スナップショットを作成し、いつでも直前の状態に復元。
- **排他制御 (PID ロック協調)**: バックグラウンドの Homebrew プロセスと競合しないよう自動制御。

### 🌐 8. ミラー速度測定と CDN 切り替え
- **リアルタイム速度ベンチマーク**: 公式 Fastly CDN、中国科大 (USTC)、清華大学 (TUNA)、Aliyun ミラーの Ping 値を計測。
- **ワンクリック切り替え**: 高速なミラー環境変数をワンタップでシステム全体に反映。

### 💻 9. メニューバー常駐 ＆ ターミナル CLI
- **歪みのないメニューバー助手**: ウィンドウサイズが崩れない固定ジオメトリ設計。保留中のアップデート確認やワンクリック更新が可能。
- **フル機能 CLI (`brewstore`)**: ターミナルから直接監査、バージョン切り替え、キャッシュ消去を実行。

### 🔄 10. マルチプロバイダー Git クラウド同期
- パッケージ構成を `~/Brewfile` に同期。
- **GitHub Gists**、**GitLab Snippets**、**Codeberg**、**Forgejo**、自前 **Gitea** に対応。

---

## ⚡ インストール方法

### オプション 1: 公式 Homebrew Cask（推奨）

```bash
brew tap amfi-disable/brewstore
brew install --cask brewstore
```

アップデート:
```bash
brew upgrade --cask brewstore
```

---

### オプション 2: DMG の直接ダウンロード

- **インストーラー DMG**: [`website/downloads/brewstore-1.0.0.dmg`](website/downloads/brewstore-1.0.0.dmg)
- **バージョン**: `v1.0.0`
- **検証済み SHA-256 チェックサム**:
  ```
  07c3ac83f1c814973d5d5033a0b816e919a2fe982541172ac42f8f2a07231753
  ```

検証コマンド:
```bash
shasum -a 256 website/downloads/brewstore-1.0.0.dmg
```

#### 🛡️ macOS Gatekeeper の注意（アドホック署名）
初回起動時に「開発元を検証できない」警告が表示された場合：
```bash
xattr -cr /Applications/BrewStore.app
```
または Finder で `BrewStore.app` を**右クリック**して**「開く」**を選択してください。

---

### オプション 3: ソースからビルド

```bash
# リポジトリのクローン
git clone https://github.com/amfi-disable/BrewStore.git
cd BrewStore

# XcodeGen でプロジェクト生成
xcodegen generate

# Release ビルド
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# 全自動テスト実行（339 項目）
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ 便利なキーボードショートカット

| ショートカット | 機能 | 説明 |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **コマンドパレット** | クイックランチャー (`> upgrade all`, `> cleanup`, `> benchmark`) と全体検索 |
| <kbd>⌘ R</kbd> | **カタログ更新** | パッケージリスト、サービス状態、更新数を最新に再読込 |
| <kbd>⌘ F</kbd> | **検索** | 現在のセクションの検索フィールドへフォーカス |
| <kbd>⌘ ,</kbd> | **設定** | 環境設定、ミラー測定、自動更新、Git 同期の設定 |
| <kbd>⌘ 1</kbd> | **見つける** | Spotlight ピックアップ、おすすめアプリへジャンプ |
| <kbd>⌘ 2</kbd> | **インストール済み** | インストール済みの全 Formula と Cask を確認 |
| <kbd>⌘ 3</kbd> | **アップデート** | 保留中の更新、所要時間予測、一括アップデート |
| <kbd>⌘ 4</kbd> | **サービス** | バックグラウンドデーモンのリソース監視と管理 |
| <kbd>⌘ 5</kbd> | **依存関係** | 双方向の依存関係キャンバス 2.0 を表示 |
| <kbd>⌘ 6</kbd> | **ウィッシュリスト** | 保存したお気に入りアプリ一覧を表示 |
| <kbd>⌘ 7</kbd> | **ツールキット** | 開発スタック向け一括セットアップ |
| <kbd>⌘ 8</kbd> | **メンテナンス** | ドクター診断、キャッシュ削除、孤立パッケージの除去 |

---

## 💻 `brewstore` CLI コンパニオン

`/opt/homebrew/bin/brewstore` または `/usr/local/bin/brewstore` から利用可能です：

```bash
# /Applications 内の未管理アプリを Homebrew Cask に取り込み
brewstore adopt [--all]

# 使用中のツールバージョンをワンコマンドで切り替え
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# セキュリティ脆弱性 CVE 監査とセキュリティスコア診断 (0–100点)
brewstore audit

# Mac App Store アプリの確認と一括アップデート
brewstore mas list
brewstore mas upgrade

# システムの健全性、孤立パッケージ、ディスク使用量の監査
brewstore health

# ディスククリーンアップ (キャッシュ削除と不要依存の自動削除)
brewstore clean

# ネイティブ GUI アプリを起動
brewstore launch
```

---

## 🌟 なぜ BrewStore が選ばれるのか

| 機能項目 | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **価格とライセンス** | **100% 無料・MIT オープンソース** | $19.99 商用有償・プロプライエタリ | 無料 |
| **プライバシー** | **テレメトリゼロ・完全ローカル** | サードパーティ解析あり | 不明 |
| **自動テスト合格数** | **339 項目 XCTest (100% 合格)** | 非公開 | 僅少 |
| **アプリ別ストレージ＆キャッシュ消去** | **✅ 非破壊的・安全ゴミ箱退避 (~/.Trash)** | ❌ なし | ❌ なし |
| **Apple Silicon vs Rosetta 2** | **✅ 自動検知＆ワンクリック移行** | ❌ なし | ❌ なし |
| **macOS LaunchAgents ＆ ログイン項目** | **✅ 完全テレメトリ・PID / RAM 監視** | ⚠️ サービスのみ | ❌ なし |
| **ワンコマンド Mac ブループリント移行** | **✅ Formulae, Casks, MAS, 設定一括** | ❌ なし | ❌ なし |
| **2大ストア統合インベントリ** | **✅ Homebrew 優先推奨** | ❌ なし | ❌ なし |
| **事前プレビュー安全関門** | **✅ 逆依存への連鎖影響を警告** | ❌ なし | ❌ なし |
| **1クリック・スナップショット** | **✅ 自動差分記録＆即時復元** | ⚠️ 閲覧のみ | ❌ なし |
| **原子性ピン留め** | **✅ 失敗時ロールバック付き** | ⚠️ Formula のみ | ❌ なし |
| **バックグラウンドサービス監視** | **✅ リアルタイム CPU/RAM/ポート** | ⚠️ 状態表示のみ | ❌ なし |
| **ミラー速度測定と切り替え** | **✅ Fastly, USTC, TUNA, Aliyun** | ❌ なし | ❌ なし |
| **マルチクラウド Git 同期** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ GitHub のみ | ❌ なし |
| **インタラクティブ依存関係図** | **✅ 双方向グラフキャンバス** | ⚠️ 静的ツリー | ❌ なし |
| **メニューバー常駐** | **✅ 歪みのない固定サイズ表示** | ⚠️ 簡易版 | ❌ なし |
| **CLI ターミナルツール** | **✅ 付属 (`brewstore` コマンド)** | ❌ なし | ❌ なし |
| **起動速度** | **⚡ &lt;20ms (高速インデックス)** | 🐢 2〜3秒 | 🐢 2〜3秒 |

---

## 🧪 自動テストと品質保証

BrewStore は、すべてのビジネスロジック、同期調整、セキュリティ境界、ユーザーインタラクションを網羅する自動テストスイートを維持しています。

```bash
# Xcodebuild によるテスト実行
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### 検証済みテストスイート（339 / 339 全て合格）

- `AppStorageInspectorTests`: 非破壊的なアプリ別キャッシュ削除、ディスク内訳（バイナリ vs キャッシュ vs データ）、ゴミ箱退避の検証。
- `AppleSiliconMigrationTests`: Rosetta 2 エミュレーション検知、ネイティブ ARM64 移行候補検出、アーキテクチャマッピング。
- `BackgroundItemsManagerTests`: ユーザーおよびシステム LaunchAgent plist 解析、launchctl 実行、ログイン項目スキャン。
- `MacBlueprintEngineTests`: 拡張 Brewfile MAS 構文解析、ブートストラップスクリプト生成、ブループリント復元。
- `UnifiedAppManagerTests`: 2大ストアインベントリ統合、Homebrew 推奨設定、ワンクリック一括更新。
- `SidebarDestinationSelectionTests`: サイドバーグループ見出しの非選択性と安全なナビゲーション。
- `MenuBarDistortionPreventionTests`: メニューバーの固定ジオメトリと歪み防止。
- `PackagePinningSynchronizationTests`: ピン留め状態の一貫性と失敗時ロールバック。
- `SpotlightCarouselTargetingTests`: カルーセルの競合防止とウィッシュリスト連携。
- `UninstallCoordinatorTests`: 事前プレビュー関門と逆依存関係警告の計算。
- `TapHealthManagerTests`: 公式およびサードパーティ Tap の健全性監査と CI 監視。
- `SpeedTestManagerTests`: ミラー Ping 測定値のクランプと所要時間予測。
- `TCCPermissionManagerTests`: アクセシビリティおよびシステム拡張権限の検出。
- `BrewStoreLockManagerTests`: PID ロック追跡とタイムアウト処理。
- `CellarScannerTests`: 複数バージョン Cellar 検出とシンボリックリンク切り替え。
- `MASReceiptScannerTests`: Mac App Store バンドルレシート解析。
- `ExecutionSecurityBoundaryTests`: シェルエスケープ防止、引数インジェクション対策。

---

## 🛡️ セキュリティとプライバシー最優先

- **完全テレメトリゼロ**: 分析トラッキング、サードパーティ SDK、テレメトリ収集は一切含まれていません。
- **完全ローカル実行**: すべてのコマンドはお手元のローカル Homebrew バイナリ経由で安全に実行されます。
- **生体認証 (Touch ID)**: 重要なシステム操作には Apple の `LocalAuthentication` を利用可能。

---

## 🗺️ ロードマップ

- [x] **v1.0.0**: ネイティブ SwiftUI による完全刷新、FastCache、⌘K パレット、依存関係キャンバス。
- [x] **v1.0.5**: マルチプロバイダー Git 同期 (GitLab, Codeberg, Forgejo, Gitea)、コミュニティ対戦ブラケット。
- [x] **v1.1.0**:
  - [x] プレビュー優先のアンインストール関門と逆依存関係警告。
  - [x] 原子性ピン留め管理とロールバック機構。
  - [x] メニューバー常駐ウィンドウの固定ジオメトリ化。
  - [x] 339 項目すべての回帰テストに合格。
- [ ] **v1.2.0**:
  - [ ] 同一 LAN 内での P2P ボトルキャッシュ共有。
  - [ ] Apple Virtualization Framework によるサンドボックス安全実行。
  - [ ] 個人開発者向けカスタム Tap 作成ウィザード。

---

## 📄 ライセンス

BrewStore は [MIT ライセンス](license) のもとで公開されているオープンソースソフトウェアです。
