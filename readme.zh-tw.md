# 🍺 BrewStore

<div align="center">

**無可爭議的 macOS 原生最強套件管理器與 Homebrew 伴侶**  
*極速、純原生 SwiftUI 圖形介面與 CLI 終端伴侶，支援 Cask 應用、Formula 命令列工具、背景系統服務、多版本切換與安全稽核。*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/平台-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/版本-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/AMFI-Disable/BrewStore/releases)
[![Tests: 345 / 345 Passed](https://img.shields.io/badge/測試-339%20%2F%20339%20全數通過%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-自動化測試與品質保障)
[![License: MIT](https://img.shields.io/badge/開源協議-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/價格-100%25%20免費開源-success.svg?style=flat-square)](#為什麼選擇-brewstore而不是-caskhub-或-taphouse-pro-1999)
[![隱私: 零遙測](https://img.shields.io/badge/隱私-零遙測%20%2F%20100%25%20純本地-purple.svg?style=flat-square)](#隱私與安全第一原則)

---

## 🌐 語言選擇 / Select Language / 选择语言 / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** •
**[简体中文](readme.zh-cn.md)** •
**[繁體中文](readme.zh-tw.md)** •
**[日本語](readme.ja.md)** •
**[Español](readme.es.md)** •
**[Français](readme.fr.md)** •
**[Deutsch](readme.de.md)**

---

### 🧭 快捷導覽連結

[🍺 Homebrew Cask 安裝](#選項-1官方-homebrew-cask-推薦) •
[✨ 功能特色亮點](#-功能特色亮點) •
[⌨️ 快捷鍵速查指南](#高效鍵盤快捷鍵) •
[💻 CLI 終端命令列伴侶](#-brewstore-cli-終端命令列伴侶) •
[🛡️ 安全與回復架構](#安全第一的系統架構) •
[📊 橫向功能對比表](#為什麼選擇-brewstore而不是-caskhub-或-taphouse-pro-1999) •
[🧪 自動化測試驗證](#-自動化測試與品質保障) •
[🗺️ 開發藍圖](#開發藍圖)

</div>

---

## 📖 什麼是 BrewStore？

**BrewStore** 是專為 macOS 打造的新一代現代化套件管理器桌面應用程式。完全採用 Apple 原生 **SwiftUI** 與 **AppKit** 精雕細琢而成，將 Homebrew 強大的底層架構與媲美 Apple 設計大獎的 App Store 流暢人機互動體驗完美揉合。

無論您是需要管理多重執行環境的軟體工程師、追求優雅創作工具的設計師，還是需要隨時監控背景行程的資深 Mac 玩家，BrewStore 都能為您提供：

- **閃電般的搜尋速度**：基於本地記憶體分詞索引，在 20ms 內完成破萬款 Formula 與 Cask 軟體的即時搜尋。
- **預覽優先的安全解除安裝機制**：在執行任何移除或 `autoremove` 操作前，完整呈現連鎖反向相依性與孤立相依性影響分析。
- **時光機快照還原**：在執行關鍵變更前自動記錄系統快照，支援具備視覺化差異（Diff）的一鍵即時還原。
- **企業級系統服務監控**：即時檢視背景 Daemon 的 CPU 使用率、記憶體常駐集（RSS）與正在接聽的 TCP 連接埠。
- **多平台 Git 雲端同步**：將個人 `~/Brewfile` 備份同步至 GitHub、GitLab、Codeberg、Forgejo 或私有自架的 Gitea 存放庫。

---

## ⚡ 架構與子系統概覽

```text
+-----------------------------------------------------------------------------------------+
|                                  BrewStore 原生 GUI 介面層                              |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | ⌘K 全域啟動器     |  | 精選 Spotlight 展台 |  | 相依拓撲畫布 2.0  |  | 選單列助手 |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | 多版本版本固定    |  | 社群爭霸擂台賽     |  | 鏡像源測速與切換  |  | 願望清單  |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                                BrewStore 核心引擎層                                     |
|   * FastCacheEngine (20ms 極速本機快取)        * PackagePinningManager (原子狀態固定)   |
|   * SnapshotManager (時光機快照還原)           * UninstallCoordinator (預覽確認門禁)    |
|   * LockCoordinationManager (PID 行程互斥鎖)   * ServiceTelemetryMonitor (資源埠號遙測) |
|   * MirrorLatencyBenchmarkEngine (CDN 測速)    * GitServiceManager (GitHub/GitLab/開源) |
|   * DockLifecycleManager (視窗與執行原則)      * TapHealthManager (Tap 健康與 CI 監控)  |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                               底層作業系統與工具鏈橋接                                  |
|   * Homebrew 核心 CLI 引擎 (/opt/homebrew 或 /usr/local)                               |
|   * Mac App Store 橋接 (mas-cli 收據解析與統一更新)                                     |
|   * macOS LaunchAgent 守護行程 (com.amfi-disable.brewstore.autoupdate.plist)            |
|   * macOS 安全 LocalAuthentication 本機認證 (Touch ID 指紋與密碼安全授權)               |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ 功能特色亮點

### 👑 全能 Mac 應用管理五大支柱核心特性

1. **🏬 雙商店統一應用管理與 Homebrew 優先推薦**
   - 完美聚合 Homebrew Casks、CLI 工具、Mac App Store 官方應用與本機未託管應用，形成統一可檢索清單。
   - 智慧識別雙商店並存應用，預設推薦 Homebrew（升級更快速、支援 CLI 指令碼編排且無 Apple ID 彈窗密碼打擾）。
   - 原生支援應用收據掃描（`Contents/_MASReceipt/receipt`），提供一鍵無損轉換至 Homebrew Cask 管理。

2. **🧹 獨立單應用磁碟佔用與快取安全清理器**
   - 軟體詳情頁直觀呈現 3 欄儲存空間透析：**主程式大小**、**快取與執行日誌**、**應用專屬資料**。
   - 專屬 **「清理快取」** 操作，透過非破壞性安全流程將快取移動至 `~/.Trash`，瞬間釋放數 GB 空間，同時完整保留使用者登入狀態與個人偏好設定。

3. **🍎 Apple Silicon 原生與 Rosetta 2 架構遷移檢測**
   - 應用清單顯式標註架構膠囊勳章：`ARM64 原生`（綠色）、`通用二進位`（藍色）、`Rosetta 2`（警示橙）。
   - 頂欄醒目提示正在透過 Rosetta 2 執行的老舊 Intel 架構應用，支援一鍵 **「遷移至 Apple Silicon 原生」**，找回電池續航與極致效能。

4. **⚙️ 開機啟動項與 macOS LaunchAgent 守護行程全生命週期管理**
   - 全新升級的服務檢視（ServicesView），同時整合 Homebrew 背景服務、使用者 LaunchAgents（`~/Library/LaunchAgents`）、系統 LaunchAgents（`/Library/LaunchAgents`）以及 macOS 登入自啟項。
   - 即時監控 CPU 使用率、常駐記憶體（RSS）與監聽連接埠，提供一鍵啟停開關與移至垃圾桶的安全解除安裝能力。

5. **🚀 一鍵 Mac 全機藍圖匯出與跨裝置自動化還原**
   - 深度匯出整機 **Mac Blueprint 藍圖**，完整收錄 Homebrew 軟體、自訂 Tap 來源、Mac App Store 應用（`mas "<name>", id: <id>`）、版本鎖定（Pin）與全域設定。
   - 自動產生具冪等性的單行 Shell 部署指令碼，並在多裝置同步面板中提供一鍵還原能力，數分鐘內還原全套開發與日常工作環境。

### 🛍️ 6. 為 Homebrew 注入現代 App Store 級美學體驗

- **Spotlight 焦點故事與精選專欄**：深度探索精選 macOS 優質軟體，圖文並茂展示更新亮點、功能介紹與安裝說明。
- **社群爭霸賽（Community Showdown）**：基於 GitHub Discussions 的無伺服器零成本社群淘汰賽，民主投票選出季度神級工具。
- **開發者工具箱（Toolkits）**：針對全端開發、Swift/iOS、DevOps、Rust、資料科學與 AI 機器學習的一鍵式預設組合包。
- **個人願望清單與收藏夾**：星標保存心儀工具，與系統已安裝狀態完全隔離，便於日後隨時安裝。

### 🛡️ 7. 安全第一的系統架構與時光機快照 <a id="安全第一的系統架構"></a>

- **原子級版本固定（Pin / Unpin）**：直接在詳情頁或右鍵選單中鎖定相依版本，指令失敗自動原子還原，徹底告別正式環境非預期升級。
- **預覽優先的安全解除安裝門禁**：所有套件解除安裝與 `autoremove` 均提供非破壞性預覽彈窗，詳盡提示下游受影響的反向相依與孤立殘留。
- **1 鍵時光機快照還原**：變更前自動拍攝系統環境快照，支援帶版本差異比對的一鍵無損還原。
- **主動式 Homebrew 行程鎖協調**：即時偵測背景並行的 Homebrew 行程，排隊等待並防止資料庫損壞。

### ⚙️ 8. 背景服務管理與即時效能遙測

- **全方位執行狀態觀測**：即時呈現 PostgreSQL、Redis、Nginx、MySQL、RabbitMQ 等服務的 CPU 佔比、記憶體 RSS 佔用、執行時長與正在接聽的 TCP 連接埠。
- **即時操作響應**：秒級執行啟動、停止、重新啟動或設定開機自動啟動，操作反饋靈敏即時。

### 🌐 9. 鏡像源延遲測速與高速 CDN 切換

- **即時延遲基準測試**：一鍵並行測速 Official Fastly CDN、中國科大（USTC）、清華大學（TUNA）以及阿里雲鏡像源。
- **一鍵無縫切換**：一鍵更新 `HOMEBREW_API_DOMAIN` 與 `HOMEBREW_BOTTLE_DOMAIN` 環境變數，大幅提升下載速度。

### 💻 10. 防形變選單列助手與終端 CLI 伴侶

- **無形變選單列浮窗**：常駐頂部選單列，採用固定視窗幾何尺寸，支援快速查收更新、一鍵升級、服務狀態檢視與快捷系統維護。
- **完整的命令列工具 (`brewstore`)**：在終端中使用 `brewstore` 執行安全掃描、多版本切換、Mac App Store 升級與快取清理。

---

## ⚡ 安裝指南

### 選項 1：官方 Homebrew Cask 安裝（推薦） <a id="選項-1官方-homebrew-cask-推薦"></a>

```bash
brew tap AMFI-Disable/brewstore
brew install --cask brewstore
```

後續更新只需執行：

```bash
brew upgrade --cask brewstore
```

---

### 選項 2：從原始碼自行編譯

```bash
# 複製存放庫
git clone https://github.com/AMFI-Disable/BrewStore.git
cd BrewStore

# 透過 XcodeGen 產生專案
xcodegen generate

# 編譯 Release 發行版本
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# 執行完整自動化測試（339 項測試）
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ 高效鍵盤快捷鍵 <a id="高效鍵盤快捷鍵"></a>

| 快捷鍵 | 功能 | 說明 |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **命令面板** | 全域快速指令啟動器（如 `> upgrade all`, `> cleanup`, `> benchmark`），支援快速跳轉與搜尋 |
| <kbd>⌘ R</kbd> | **重新整理** | 重新拉取本機套件、遠端索引、服務狀態與更新統計 |
| <kbd>⌘ F</kbd> | **搜尋** | 立即聚焦當前檢視下的搜尋輸入框 |
| <kbd>⌘ ,</kbd> | **偏好設定** | 打開設定面板、鏡像源測速、自動更新排程與雲端同步設定 |
| <kbd>⌘ 1</kbd> | **探索** | 快速跳轉至 Storefront 展台、精選與趨勢排行榜 |
| <kbd>⌘ 2</kbd> | **已安裝** | 檢視本機已安裝的所有 Formula 與 Cask |
| <kbd>⌘ 3</kbd> | **待更新** | 檢視待更新套件、預估下載時間與一鍵批次更新 |
| <kbd>⌘ 4</kbd> | **服務** | 監控與管理背景系統服務及資源佔用 |
| <kbd>⌘ 5</kbd> | **相依畫布** | 打開互動式相依拓撲圖 2.0 |
| <kbd>⌘ 6</kbd> | **願望清單** | 檢視收藏的軟體與備忘庫 |
| <kbd>⌘ 7</kbd> | **工具箱** | 打開開發者專屬預設組合套件 |
| <kbd>⌘ 8</kbd> | **系統維護** | 執行診斷、清理硬碟快取與解除安裝孤立相依 |

---

## 💻 `brewstore` CLI 終端命令列伴侶

BrewStore 隨應用隨附提供獨立的命令列伴侶工具，位於 `/opt/homebrew/bin/brewstore` 或 `/usr/local/bin/brewstore`：

```bash
# 掃描 /Applications 並將未託管的本機應用遷移託管至 Homebrew
brewstore adopt [--all]

# 快速切換正在啟用的工具鏈版本 (Cellar 符號連結管理)
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# 執行安全漏洞 CVE 稽核與加固評分 (0–100 分)
brewstore audit

# 檢查並更新 Mac App Store 應用 (基於 mas 橋接)
brewstore mas list
brewstore mas upgrade

# 檢查環境健康狀況、孤立相依與磁碟空間佔用
brewstore health

# 釋放磁碟空間 (清理快取預編譯瓶子與自動移除未用相依)
brewstore clean

# 快速啟動原生圖形介面應用
brewstore launch
```

---

## 🌟 為什麼選擇 BrewStore？（對比 CaskHub 與 Taphouse Pro $19.99） <a id="為什麼選擇-brewstore而不是-caskhub-或-taphouse-pro-1999"></a>

| 功能維度 | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **定價與開源協議** | **100% 永久免費且 MIT 開源** | $19.99 商業收費 / 閉源 | 免費 |
| **遙測與隱私保護** | **零遙測 / 100% 純本機執行** | 整合第三方資料分析 | 未知 |
| **自動化測試覆蓋** | **339 項 XCTest 測試 (100% 通過)** | 未公開 | 極少 |
| **單應用儲存與快取清理** | **✅ 非破壞性安全移至廢紙簍 (~/.Trash)** | ❌ 無 | ❌ 無 |
| **Apple Silicon vs Rosetta 2** | **✅ 自動架構偵測與一鍵原生遷移** | ❌ 無 | ❌ 無 |
| **macOS LaunchAgents 與開機啟動項** | **✅ 完整遙測、PID 與記憶體即時監控** | ⚠️ 僅限 Homebrew 服務 | ❌ 無 |
| **單行指令 Mac 藍圖全機轉移** | **✅ Formulae, Casks, MAS 應用與偏好設定** | ❌ 無 | ❌ 無 |
| **雙商店統一清單與推薦** | **✅ Homebrew + MAS 智慧推薦** | ❌ 無 | ❌ 無 |
| **預覽優先的解除安裝門禁** | **✅ 完整反向相依連鎖預警** | ❌ 無 | ❌ 無 |
| **1 鍵時光機快照還原** | **✅ 變更前自動 Diff 快照** | ⚠️ 僅供檢視 | ❌ 無 |
| **原子級版本固定** | **✅ 一鍵固定並支援失敗還原** | ⚠️ 僅限 Formula | ❌ 無 |
| **背景服務資源遙測** | **✅ 即時 CPU、記憶體與接聽連接埠** | ⚠️ 僅顯示執行狀態 | ❌ 無 |
| **鏡像源測速與切換** | **✅ Fastly, USTC, TUNA, 阿里雲** | ❌ 無 | ❌ 無 |
| **多平台 Git 雲端同步** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ 僅限 GitHub | ❌ 無 |
| **互動式相依拓撲畫布** | **✅ 雙向相依與被相依圖譜** | ⚠️ 靜態樹狀圖 | ❌ 無 |
| **防抖動選單列助手** | **✅ 剛性版面防形變浮窗** | ⚠️ 基礎浮窗 | ❌ 無 |
| **終端命令列伴侶** | **✅ 內建 `brewstore` 二進位檔** | ❌ 無 | ❌ 無 |
| **冷啟動效能** | **⚡ &lt;20ms (本機記憶體索引)** | 🐢 2–3 秒 | 🐢 2–3 秒 |

---

## 🧪 自動化測試與品質保障

BrewStore 維護了完整且覆蓋廣泛的自動化測試套件，涵蓋所有業務邏輯、同步協調器、安全邊界以及使用者互動流程。

```bash
# 透過 Xcodebuild 執行自動化測試
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### 已驗證的測試套件（345 / 345 全數通過）

- `AppStorageInspectorTests`：非破壞性單應用快取清理、精準三欄儲存空間透析（二進位檔 vs 快取 vs 資料）與廢紙簍安全路徑驗證。
- `AppleSiliconMigrationTests`：Rosetta 2 模擬執行偵測、原生 ARM64 遷移候選者比對與架構膠囊對應。
- `BackgroundItemsManagerTests`：使用者與系統級 LaunchAgent plist 解析、launchctl 指令排程與登入啟動項掃描。
- `MacBlueprintEngineTests`：擴充型 Brewfile MAS 語法解析、跨機引導 Shell 指令碼產生與藍圖環境還原。
- `UnifiedAppManagerTests`：雙商店清單合併、Homebrew 推薦偏好儲存與一鍵全域批次更新。
- `SidebarDestinationSelectionTests`：側邊欄群組標題無障礙非選取性與真實導覽項目嚴格隔離驗證。
- `MenuBarDistortionPreventionTests`：選單列剛性視窗幾何尺寸鎖定與形變動畫抑制驗證。
- `PackagePinningSynchronizationTests`：版本固定管理器、Homebrew 底層狀態與失敗自動還原原子性一致性。
- `SpotlightCarouselTargetingTests`：輪播展台競態條件抑制與願望清單繫結測試。
- `UninstallCoordinatorTests`：預覽優先的安全門禁與連鎖反向相依警告計算。
- `TapHealthManagerTests`：官方與第三方 Tap 健康狀況稽核與 GitHub CI 狀態追蹤。
- `SpeedTestManagerTests`：鏡像源延遲 Ping 數值夾取與更新時間預估。
- `TCCPermissionManagerTests`：輔助功能與系統擴充權限狀態偵測。
- `BrewStoreLockManagerTests`：PID 互斥鎖追蹤、超時排隊與陳舊鎖淘汰。
- `CellarScannerTests`：多版本 Cellar 安裝發現與符號連結原子切換。
- `MASReceiptScannerTests`：Mac App Store 應用程式收據解析與版本比對。
- `ExecutionSecurityBoundaryTests`：Shell 跳脫防護、路徑穿越防禦與參數注入攔截。

---

## 🛡️ 隱私與安全第一原則 <a id="隱私與安全第一原則"></a>

- **零遙測**：BrewStore 不包含任何第三方追蹤分析、零 Google/Firebase SDK，且絕無任何遙測回傳機制。
- **純本機執行**：所有指令均嚴格透過您本機的 Homebrew 二進位檔執行（Apple Silicon 為 `/opt/homebrew`，Intel 為 `/usr/local`）。
- **生物辨識認證**：關鍵變更操作整合 Apple 原生 `LocalAuthentication` 框架，支援 Touch ID 與 Apple Watch 授權。
- **安全加固與代碼簽署**：完全符合 macOS 執行階段安全性規範。

---

## 🗺️ 開發藍圖 <a id="開發藍圖"></a>

- [x] **v1.0.0**：純原生 SwiftUI 架構重構、FastCache 極速快取引擎、⌘K 命令面板、互動式相依圖譜。
- [x] **v1.0.5**：多平台 Git 雲端同步（GitLab、Codeberg、Forgejo、Gitea）、社群淘汰賽爭霸擂台。
- [x] **v1.1.0**：
  - [x] 預覽優先的解除安裝與 `autoremove` 門禁協調器，具備反向相依警告。
  - [x] 原子級版本固定管理器，支援即時進度反饋與失敗自動復原。
  - [x] 選單列助手剛性幾何尺寸穩定化與防形變視窗鎖定。
  - [x] 側邊欄群組標題無障礙化。
  - [x] 精選展台懸停暫停與願望清單點擊繫結。
  - [x] 自動化 Tap 健康稽核與 CI 狀態監控。
  - [x] 339 項自動化測試全數通過，0 項失敗。
- [ ] **v1.2.0**：
  - [ ] 區網 P2P 預編譯瓶子快取共用（適用於多 Mac 辦公室與家庭實驗室）。
  - [ ] 基於 Apple Virtualization Framework 的沙盒化試執行容器。
  - [ ] 獨立開發者專屬 Tap 來源精靈。

---

## 🤝 參與貢獻

我們熱烈歡迎各界開發者的參與！在提交 Pull Request 之前，請務必先閱讀我們的[貢獻指南](docs/contributing.md)與[安全政策](security.md)。

---

## 📄 開源協議

BrewStore 採用 [MIT 開源協議](license)。完全免費、自由開放且獨立自豪。
