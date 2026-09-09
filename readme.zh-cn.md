# 🍺 BrewStore

<div align="center">

**无可争议的 macOS 原生最强包管理器与 Homebrew 伴侣**  
*极速、纯原生 SwiftUI 图形界面与 CLI 终端伴侣，支持 Cask 应用、Formula 命令行工具、后台系统服务、多版本版本切换与安全审计。*

[![Platform: macOS Sonoma+](https://img.shields.io/badge/平台-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/版本-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/amfi-disable/BrewStore/releases)
[![Tests: 339 / 339 Passed](https://img.shields.io/badge/测试-339%20%2F%20339%20全数通过-success.svg?style=flat-square&logo=checkmarx)](#-自动化测试与质量保障)
[![License: MIT](https://img.shields.io/badge/开源协议-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/价格-100%25%20免费开源-success.svg?style=flat-square)](#-为什么选择-brewstore而不是-caskhub-或-taphouse-pro-1999)
[![Zero Telemetry](https://img.shields.io/badge/隐私-零遥测%20%2F%20100%25%20本地-purple.svg?style=flat-square)](#-隐私与安全第一原则)

---

### 🌐 语言选择 / Select Language / 言語を選択 / Idioma / Langue / Sprache

**[English](readme.md)** • 
**[简体中文](readme.zh-cn.md)** • 
**[繁體中文](readme.zh-tw.md)** • 
**[日本語](readme.ja.md)** • 
**[Español](readme.es.md)** • 
**[Français](readme.fr.md)** • 
**[Deutsch](readme.de.md)**

---

### 🧭 快捷导航链接

[📥 下载 DMG 安装包](website/downloads/brewstore-1.0.0.dmg) •
[🍺 Homebrew Cask 安装](#-选项-1官方-homebrew-cask-推荐) •
[✨ 功能特性亮点](#-功能特性亮点) •
[⌨️ 快捷键速查指南](#-高效键盘快捷键) •
[💻 CLI 命令行伴侣](#-brewstore-cli-终端命令行伴侣) •
[🛡️ 安全与回滚架构](#-安全第一的系统架构) •
[📊 横向功能对比表](#-为什么选择-brewstore而不是-caskhub-或-taphouse-pro-1999) •
[🧪 自动化测试验证](#-自动化测试与质量保障) •
[🗺️ 开发路线图](#-开发路线图)

</div>

---

## 📖 什么是 BrewStore？

**BrewStore** 是专为 macOS 打造的新一代现代化包管理器桌面应用。完全采用苹果原生 **SwiftUI** 与 **AppKit** 精雕细琢而成，它将 Homebrew 强大的底层能力与媲美 Apple 设计大奖的 App Store 流畅人机交互体验完美融合。

无论您是日常需要管理多套运行环境的软件工程师、追求优雅创作工具的设计师，还是需要监控守护进程的资深极客，BrewStore 都能为您提供：
- **闪电般的检索速度**：基于本地内存分词索引，在 20ms 内完成逾万款 Formula 与 Cask 软件的即时搜索。
- **预览在先的安全卸载机制**：在执行任何卸载或 `autoremove` 操作前，完整呈现级联反向依赖与孤立依赖影响分析。
- **时光机快照回滚**：在执行关键变动前自动记录系统快照，支持带可视化差异（Diff）的一键即时回滚。
- **企业级系统服务监控**：实时查看后台守护进程的 CPU 占用率、物理内存常驻集（RSS）以及正在监听的 TCP 端口。
- **多平台 Git 云端同步**：将个人 `~/Brewfile` 实时备份同步至 GitHub、GitLab、Codeberg、Forgejo 或私有部署的 Gitea 仓库。

---

## ⚡ 架构与子系统概览

```
+-----------------------------------------------------------------------------------------+
|                                    BrewStore GUI Layer                                  |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | ⌘K Power Launcher |  | Spotlight Carousel |  | Dependency Canvas |  | Menu Bar  |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Version Pinning   |  | Community Showdown |  | Mirror Benchmark  |  | Wishlist  |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              BrewStore Core Engine                                      |
|   * FastCacheEngine (Sub-20ms Local Index)     * PackagePinningManager (Atomic State)   |
|   * SnapshotManager (Rollback Time Machine)    * UninstallCoordinator (Preview Gate)    |
|   * LockCoordinationManager (PID Safe Guard)   * ServiceTelemetryMonitor (CPU/RAM/Port) |
|   * MirrorLatencyBenchmarkEngine               * GitServiceManager (GitHub/GitLab/FOSS) |
|   * DockLifecycleManager (Scene & Status)      * TapHealthManager (Audit & CI Status)   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                              Underlying System Bridges                                  |
|   * Homebrew CLI Engine (/opt/homebrew or /usr/local)                                   |
|   * Mac App Store Bridge (mas-cli receipt scanning & updates)                           |
|   * macOS LaunchAgent Daemon (com.amfi-disable.brewstore.autoupdate.plist)              |
|   * macOS Security LocalAuthentication (Touch ID / Biometrics)                          |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ 功能特性亮点

### 👑 全能 Mac 应用管理五大支柱核心特性

1. **🏬 双商店统一应用管理与 Homebrew 优先推荐**
   - 完美聚合 Homebrew Casks、CLI 工具、Mac App Store 官方应用与本地未托管应用，形成统一可检索清单。
   - 智能识别双商店并存应用，默认推荐 Homebrew（升级更快捷、支持 CLI 脚本编排且无 Apple ID 弹窗密码打扰）。
   - 原生支持应用收据扫描（`Contents/_MASReceipt/receipt`），提供一键无损转换至 Homebrew Cask 管理。

2. **🧹 独立单应用磁盘占用与缓存安全清理器**
   - 软件详情页直观呈现 3 栏存储空间透析：**主程序体积**、**缓存与运行日志**、**应用专属数据**。
   - 专属 **“清理缓存”** 操作，通过非破坏性安全流程将缓存移动至 `~/.Trash`，瞬间释放数 GB 垃圾，同时完整保留用户登录状态与个人偏好设置。

3. **🍎 Apple Silicon 原生与 Rosetta 2 架构迁移检测**
   - 应用列表显式标注架构胶囊勋章：`ARM64 原生`（绿色）、`通用二进制`（蓝色）、`Rosetta 2`（警示橙）。
   - 顶栏醒目提示正在通过 Rosetta 2 运行的老旧 Intel 架构应用，支持一键 **“迁移至 Apple Silicon 原生”**，找回电池续航与极致性能。

4. **⚙️ 登录项与 macOS LaunchAgent 守护进程全生命周期管理**
   - 全新升级的服务视图（ServicesView），同时整合 Homebrew 后台服务、用户 LaunchAgents（`~/Library/LaunchAgents`）、系统 LaunchAgents（`/Library/LaunchAgents`）以及 macOS 登录自启项。
   - 实时监控 CPU 占用率、常驻内存（RSS）与监听端口，提供一键启停开关与移至废纸篓的安全卸载能力。

5. **🚀 一键 Mac 全盘蓝图导出与跨机自动化恢复**
   - 深度导出整机 **Mac Blueprint 蓝图**，完整收录 Homebrew 软件、自建 Tap 源、Mac App Store 应用（`mas "<name>", id: <id>`）、版本锁定（Pin）与全局设置。
   - 自动生成幂等的单行 Shell 部署脚本，并在多设备同步面板中提供一键恢复能力，数分钟内还原全套开发与日常工作环境。

### 🛍️ 1. 为 Homebrew 注入现代 App Store 级美学体验
- **Spotlight 焦点故事与精选专栏**：深度探索精选 macOS 优质软件，图文并茂展示更新亮点、功能介绍与安装说明。
- **社区争霸赛（Community Showdown）**：基于 GitHub Discussions 的无服务器零成本社区淘汰赛，民主投票选出季度神级工具。
- **开发者工具箱（Toolkits）**：针对全栈开发、Swift/iOS、DevOps、Rust、数据科学与 AI 机器学习的一键式预设组合包。
- **个人愿望单与收藏夹**：星标保存心仪工具，与系统已安装状态完全隔离，便于日后随时安装。

### 🛡️ 2. 安全第一的系统架构与时光机快照
- **原子级版本固定（Pin / Unpin）**：直接在详情页或右键菜单中锁定依赖版本，命令失败自动原子回滚，彻底告别生产环境非预期升级。
- **预览在先的安全卸载门禁**：所有包卸载与 `autoremove` 均提供非破坏性预览弹窗，详尽提示下游受影响的反向依赖与孤儿残留。
- **1 键时光机快照回滚**：变更前自动拍摄系统环境快照，支持带版本差异对比的一键无损回滚。
- **主动式 Homebrew 进程锁协调**：实时侦测后台并发的 Homebrew 进程，排队等待并防止数据库损坏。

### ⚙️ 3. 后台服务管理与实时性能遥测
- **全方位运行状态观测**：实时呈现 PostgreSQL、Redis、Nginx、MySQL、RabbitMQ 等服务的 CPU 占比、内存 RSS 占用、运行时长与正在监听的 TCP 端口。
- **即时操作响应**：秒级执行启动、停止、重启或配置开机自启，操作反馈灵敏即时。

### 🌐 4. 镜像源延迟测速与高速 CDN 切换
- **实时延迟基准测试**：一键并行测速 Official Fastly CDN、中国科大（USTC）、清华大学（TUNA）以及阿里云镜像源。
- **一键无缝切换**：一键更新 `HOMEBREW_API_DOMAIN` 与 `HOMEBREW_BOTTLE_DOMAIN` 环境变量，大幅提升下载速度。

### 💻 5. 防形变菜单栏助手与终端 CLI 伴侣
- **无形变菜单栏浮窗**：常驻顶部菜单栏，采用固定窗体几何尺寸，支持快速查收更新、一键升级、服务状态查看与快捷系统维护。
- **完整的命令行工具 (`brewstore`)**：在终端中使用 `brewstore` 运行安全扫描、多版本切换、Mac App Store 升级与缓存清理。

### 🔄 6. 多平台 Git 云端同步
- 支持一键导出并同步个人环境至 `~/Brewfile`。
- 原生支持 **GitHub Gists**、**GitLab Snippets**、**Codeberg**、**Forgejo** 以及私有部署的 **Gitea** 实例。

---

## ⚡ 安装指南

### 选项 1：官方 Homebrew Cask 安装（推荐）

通过 Homebrew 官方 Cask 一键安装 BrewStore 桌面应用及终端 CLI：

```bash
brew tap amfi-disable/brewstore
brew install --cask brewstore
```

后续更新应用只需运行：
```bash
brew upgrade --cask brewstore
```

---

### 选项 2：直接下载 DMG 安装镜像

从官方镜像源直接下载带代码签名的 DMG 安装文件：

- **DMG 安装包**：[`website/downloads/brewstore-1.0.0.dmg`](website/downloads/brewstore-1.0.0.dmg)
- **发布版本**：`v1.0.0`
- **已校验 SHA-256 校验码**：
  ```
  07c3ac83f1c814973d5d5033a0b816e919a2fe982541172ac42f8f2a07231753
  ```

验证下载文件的完整性：
```bash
shasum -a 256 website/downloads/brewstore-1.0.0.dmg
```

#### 🛡️ macOS Gatekeeper 提示处理说明
由于 BrewStore 为独立开源项目且未参与 Apple 付费开发者公证计划，首次启动若提示“无法验证开发者”：
```bash
xattr -cr /Applications/BrewStore.app
```
或在访达（Finder）中**右键点击** `BrewStore.app` 并选择**“打开”**即可。

---

### 选项 3：从源代码构建

```bash
# 克隆仓库
git clone https://github.com/amfi-disable/BrewStore.git
cd BrewStore

# 通过 XcodeGen 自动生成项目工程
xcodegen generate

# 编译 Release 配置
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# 运行完整的 339 项自动化单元测试
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ 高效键盘快捷键

| 快捷键 | 功能 | 说明 |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **命令面板** | 全局快速指令启动器（如 `> upgrade all`, `> cleanup`, `> benchmark`），支持快速跳转与搜索 |
| <kbd>⌘ R</kbd> | **刷新列表** | 重新拉取本地包、远端索引、服务状态与更新统计 |
| <kbd>⌘ F</kbd> | **搜索** | 立即聚焦当前视图下的搜索输入框 |
| <kbd>⌘ ,</kbd> | **偏好设置** | 打开设置面板、镜像源测速、自动更新计划与云端同步设置 |
| <kbd>⌘ 1</kbd> | **发现** | 快速跳转至 Storefront 展台、精选与趋势排行榜 |
| <kbd>⌘ 2</kbd> | **已安装** | 查看本地已安装的所有 Formula 与 Cask |
| <kbd>⌘ 3</kbd> | **待更新** | 查看待更新包、预估下载时间与一键批量更新 |
| <kbd>⌘ 4</kbd> | **服务** | 监控与管理后台系统服务及资源占用 |
| <kbd>⌘ 5</kbd> | **依赖画布** | 打开交互式依赖拓扑图 2.0 |
| <kbd>⌘ 6</kbd> | **愿望单** | 查看收藏的软件与备忘库 |
| <kbd>⌘ 7</kbd> | **工具箱** | 打开开发者专享预设组合套件 |
| <kbd>⌘ 8</kbd> | **系统维护** | 运行诊断、清理硬盘缓存与卸载孤儿依赖 |

---

## 💻 `brewstore` CLI 终端命令行伴侣

BrewStore 随应用捆绑提供独立的命令行伴侣工具，位于 `/opt/homebrew/bin/brewstore` 或 `/usr/local/bin/brewstore`：

```bash
# 扫描 /Applications 并将未受纳管的本地应用迁移纳管至 Homebrew
brewstore adopt [--all]

# 快速切换正在激活的工具链版本 (Cellar 软链接管理)
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# 执行安全漏洞 CVE 审计与加固评分 (0–100 分)
brewstore audit

# 检查并更新 Mac App Store 应用 (基于 mas 桥接)
brewstore mas list
brewstore mas upgrade

# 检查环境健康状况、孤立依赖与磁盘空间占用
brewstore health

# 释放磁盘空间 (清理缓存瓶子与自动移除未用依赖)
brewstore clean

# 快速唤起原生图形界面应用
brewstore launch
```

---

## 🌟 为什么选择 BrewStore？（对比 CaskHub 与 Taphouse Pro $19.99）

| 功能维度 | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **定价与开源协议** | **100% 永久免费且 MIT 开源** | $19.99 商业收费 / 闭源 | 免费 |
| **遥测与隐私保护** | **零遥测 / 100% 纯本地运行** | 集成第三方数据分析 | 未知 |
| **自动化测试覆盖** | **339 项 XCTest 测试 (100% 通过)** | 未公开 | 极少 |
| **单应用存储透析与缓存安全清理** | **✅ 非破坏性安全移至废纸篓** | ❌ 无 | ❌ 无 |
| **Apple Silicon 原生与 Rosetta 检测** | **✅ 智能检测与一键迁移原生** | ❌ 无 | ❌ 无 |
| **macOS LaunchAgent 与登录项管理** | **✅ 全生命周期与 CPU/RAM 遥测** | ⚠️ 仅限 brew 服务 | ❌ 无 |
| **一键整机 Mac Blueprint 蓝图恢复** | **✅ 完整收录应用、源与偏好** | ❌ 无 | ❌ 无 |
| **双商店统一检索与推荐转换** | **✅ 优先推荐 Homebrew / 无感纳管** | ❌ 无 | ❌ 无 |
| **预览在先的卸载门禁** | **✅ 完整反向依赖级联预警** | ❌ 无 | ❌ 无 |
| **1 键时光机快照回滚** | **✅ 变更前自动 Diff 快照** | ⚠️ 仅供查看 | ❌ 无 |
| **原子级版本固定** | **✅ 一键固定并支持失败回滚** | ⚠️ 仅限 Formula | ❌ 无 |
| **后台服务资源遥测** | **✅ 实时 CPU、内存与监听端口** | ⚠️ 仅显示运行状态 | ❌ 无 |
| **镜像源测速与切换** | **✅ Fastly, USTC, TUNA, 阿里云** | ❌ 无 | ❌ 无 |
| **多平台 Git 云端同步** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ 仅限 GitHub | ❌ 无 |
| **交互式依赖拓扑画布** | **✅ 双向依赖与被依赖图谱** | ⚠️ 静态树状图 | ❌ 无 |
| **防抖动菜单栏助手** | **✅ 刚性布局防形变浮窗** | ⚠️ 基础浮窗 | ❌ 无 |
| **终端命令行伴侣** | **✅ 内置 `brewstore` 二进制** | ❌ 无 | ❌ 无 |
| **冷启动性能** | **⚡ &lt;20ms (本地内存索引)** | 🐢 2–3 秒 | 🐢 2–3 秒 |

---

## 🧪 自动化测试与质量保障

BrewStore 配备了极其严格的端到端与单元测试套件，全面覆盖业务逻辑、同步管理器、安全边界与用户交互流程。

```bash
# 通过 Xcodebuild 运行全套测试
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### 核心测试套件概览 (339 / 339 全数通过)

- `AppStorageInspectorTests`：单应用存储透析，精确拆解主程序、缓存与数据体积，保证废纸篓删除安全性。
- `AppleSiliconMigrationTests`：Rosetta 2 运行侦测、原生 ARM64 迁移候选池生成及架构状态映射。
- `BackgroundItemsManagerTests`：用户与系统级 LaunchAgent Plist 解析、launchctl 交互与系统登录项提取。
- `MacBlueprintEngineTests`：增强版 Brewfile MAS 解析、单行 Bootstrap Shell 脚本生成与蓝图还原。
- `UnifiedAppManagerTests`：双商店多来源资产聚合、Homebrew 优先策略生效及全局一键升级。
- `SidebarDestinationSelectionTests`：严格保证侧边栏导航目的地与无障碍分组标题的隔离性。
- `MenuBarDistortionPreventionTests`：验证菜单栏助手在各类交互与操作下的防形变刚性窗口布局。
- `PackagePinningSynchronizationTests`：覆盖固定管理器、状态同步与 CLI 失败时的原子回滚机制。
- `SpotlightCarouselTargetingTests`：验证轮播图悬停暂停策略及针对选定包的愿望单绑定一致性。
- `UninstallCoordinatorTests`：验证卸载预览门禁、级联反向依赖分析及孤儿依赖探测。
- `TapHealthManagerTests`：覆盖官方与第三方 Tap 的健康度审计与分支追踪。
- `SpeedTestManagerTests`：验证镜像源网络测速数据解析、数值范围钳制与时间预估模型。
- `TCCPermissionManagerTests`：辅助功能与系统扩展安全权限检测。
- `BrewStoreLockManagerTests`：PID 锁超时判定、僵尸锁清理及并发保护。
- `CellarScannerTests`：多版本 Cellar 扫描与符号链接切换。
- `MASReceiptScannerTests`：Mac App Store 收据格式解析与本地应用发现。
- `ExecutionSecurityBoundaryTests`：Shell 参数校验、路径逃逸防御及指令注入安全门限。

---

## 🛡️ 隐私与安全第一原则

- **绝对零遥测**：BrewStore 不包含任何用户行为追踪 SDK，无 Google/Firebase 依赖，不发送任何遥测数据。
- **纯本地运行**：所有命令通过您本机的 Homebrew 环境（Apple Silicon 上的 `/opt/homebrew` 或 Intel 上的 `/usr/local`）直接执行。
- **生物识别授权**：敏感操作无缝调用 macOS 原生 `LocalAuthentication` 框架，支持 Touch ID 指纹与 Apple Watch 认证。
- **代码签名与运行时加固**：全面遵循 macOS 运行时安全标准。

---

## 🗺️ 开发路线图

- [x] **v1.0.0**：原生 SwiftUI 界面重构、FastCache 极速缓存引擎、⌘K 命令面板与交互式依赖图谱。
- [x] **v1.0.5**：多源 Git 云端同步（GitLab、Codeberg、Forgejo、Gitea）与社区争霸赛擂台系统。
- [x] **v1.1.0**：
  - [x] 预览在先的安全卸载与 `autoremove` 门禁系统（含级联反向依赖预警）。
  - [x] 原子级版本固定（Pinning）管理器，具备实时操作进度指示与失败自动回滚。
  - [x] 菜单栏助手彻底解决交互形变问题，锁定刚性视窗几何。
  - [x] 侧边栏分组标题无障碍化改造，完全隔绝非导航项被选中的情况。
  - [x] Spotlight 轮播交互防竞态与按包绑定的愿望单反馈机制。
  - [x] 自动化 Tap 健康监控与持续集成（CI）追踪。
  - [x] 276 项回归自动化测试 100% 通过。
- [ ] **v1.2.0**：
  - [ ] 局域网 P2P 预编译包（Bottle）本地缓存共享，加速团队多台 Mac 装机。
  - [ ] 基于 Apple Virtualization Framework 的沙盒容器化演练卸载与试运行。
  - [ ] 面向个人独立开发者的可视化自定义 Tap 创建向导。

---

## 🤝 参与贡献

我们极其欢迎社区力量！在提交 Pull Request 之前，请参阅我们的 [贡献指南](docs/contributing.md) 与 [安全策略](security.md)。

1. Fork 本仓库。
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)。
3. 提交您的修改 (`git commit -m 'feat: 增加超酷特性'`)。
4. 推送至您的分支 (`git push origin feature/amazing-feature`)。
5. 开启一个 Pull Request。

---

## 📄 开源协议

BrewStore 采用 [MIT 开源协议](license)。完全免费、自由开放且独立自豪。
