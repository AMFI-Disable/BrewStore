import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case german = "de"
    case french = "fr"
    case spanish = "es"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文 (Simplified Chinese)"
        case .traditionalChinese: "繁體中文 (Traditional Chinese)"
        case .japanese: "日本語 (Japanese)"
        case .german: "Deutsch (German)"
        case .french: "Français (French)"
        case .spanish: "Español (Spanish)"
        }
    }
}

@MainActor
final class BrewStoreLocalizationManager: ObservableObject {
    static let shared = BrewStoreLocalizationManager()

    private let defaults = UserDefaults.standard
    private let key = "pref_app_language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            defaults.set(currentLanguage.rawValue, forKey: key)
        }
    }

    private static let translations: [String: [AppLanguage: String]] = [
        // Navigation & Sidebar
        "Storefront": [
            .english: "Storefront",
            .simplifiedChinese: "商店精选",
            .traditionalChinese: "商店精選",
            .japanese: "ストアフロント",
            .german: "Storefront",
            .french: "Boutique",
            .spanish: "Tienda"
        ],
        "Discover": [
            .english: "Discover",
            .simplifiedChinese: "发现",
            .traditionalChinese: "探索",
            .japanese: "見つける",
            .german: "Entdecken",
            .french: "Découvrir",
            .spanish: "Descubrir"
        ],
        "Stories": [
            .english: "Stories",
            .simplifiedChinese: "专题故事",
            .traditionalChinese: "專題故事",
            .japanese: "ストーリー",
            .german: "Storys",
            .french: "Histoires",
            .spanish: "Historias"
        ],
        "Toolkits": [
            .english: "Toolkits",
            .simplifiedChinese: "开发套件",
            .traditionalChinese: "開發套件",
            .japanese: "ツールキット",
            .german: "Toolkits",
            .french: "Boîtes à outils",
            .spanish: "Herramientas"
        ],
        "Categories": [
            .english: "Categories",
            .simplifiedChinese: "分类全览",
            .traditionalChinese: "分類全覽",
            .japanese: "カテゴリ",
            .german: "Kategorien",
            .french: "Catégories",
            .spanish: "Categorías"
        ],
        "Library": [
            .english: "Library",
            .simplifiedChinese: "本地库",
            .traditionalChinese: "本地資料庫",
            .japanese: "ライブラリ",
            .german: "Bibliothek",
            .french: "Bibliothèque",
            .spanish: "Biblioteca"
        ],
        "Installed": [
            .english: "Installed",
            .simplifiedChinese: "已安装",
            .traditionalChinese: "已安裝",
            .japanese: "インストール済み",
            .german: "Installiert",
            .french: "Installé",
            .spanish: "Instalado"
        ],
        "Adoption": [
            .english: "App Adoption",
            .simplifiedChinese: "应用接管",
            .traditionalChinese: "應用接管",
            .japanese: "アプリの移行",
            .german: "App-Übernahme",
            .french: "Adoption d'apps",
            .spanish: "Adopción de apps"
        ],
        "Wishlist": [
            .english: "Wishlist",
            .simplifiedChinese: "收藏愿望单",
            .traditionalChinese: "願望清單",
            .japanese: "ウィッシュリスト",
            .german: "Wunschliste",
            .french: "Liste de souhaits",
            .spanish: "Lista de deseos"
        ],
        "Services": [
            .english: "Services",
            .simplifiedChinese: "后台服务",
            .traditionalChinese: "背景服務",
            .japanese: "サービス",
            .german: "Dienste",
            .french: "Services",
            .spanish: "Servicios"
        ],
        "Taps": [
            .english: "Taps",
            .simplifiedChinese: "第三方源",
            .traditionalChinese: "第三方源",
            .japanese: "Taps",
            .german: "Taps",
            .french: "Taps",
            .spanish: "Taps"
        ],
        "System": [
            .english: "System",
            .simplifiedChinese: "系统",
            .traditionalChinese: "系統",
            .japanese: "システム",
            .german: "System",
            .french: "Système",
            .spanish: "Sistema"
        ],
        "Updates": [
            .english: "Updates",
            .simplifiedChinese: "待更新",
            .traditionalChinese: "待更新",
            .japanese: "アップデート",
            .german: "Updates",
            .french: "Mises à jour",
            .spanish: "Actualizaciones"
        ],
        "Backups": [
            .english: "Backups",
            .simplifiedChinese: "快照备份",
            .traditionalChinese: "快照備份",
            .japanese: "バックアップ",
            .german: "Sicherungen",
            .french: "Sauvegardes",
            .spanish: "Copias de seguridad"
        ],
        "Settings": [
            .english: "Settings",
            .simplifiedChinese: "设置中心",
            .traditionalChinese: "設定中心",
            .japanese: "設定",
            .german: "Einstellungen",
            .french: "Réglages",
            .spanish: "Ajustes"
        ],

        // Action Buttons
        "GET": [
            .english: "GET",
            .simplifiedChinese: "获取",
            .traditionalChinese: "取得",
            .japanese: "入手",
            .german: "LADEN",
            .french: "OBTENIR",
            .spanish: "OBTENER"
        ],
        "OPEN": [
            .english: "OPEN",
            .simplifiedChinese: "打开",
            .traditionalChinese: "開啟",
            .japanese: "開く",
            .german: "ÖFFNEN",
            .french: "OUVRIR",
            .spanish: "ABRIR"
        ],
        "UPDATE": [
            .english: "UPDATE",
            .simplifiedChinese: "更新",
            .traditionalChinese: "更新",
            .japanese: "アップデート",
            .german: "AKTUALISIEREN",
            .french: "METTRE À JOUR",
            .spanish: "ACTUALIZAR"
        ],
        "INSTALLED": [
            .english: "INSTALLED",
            .simplifiedChinese: "已就绪",
            .traditionalChinese: "已就緒",
            .japanese: "インストール済み",
            .german: "INSTALLIERT",
            .french: "INSTALLÉ",
            .spanish: "INSTALADO"
        ],

        // Quick Open & Assistant
        "Quick Open": [
            .english: "Quick Open",
            .simplifiedChinese: "快速跳转",
            .traditionalChinese: "快速跳轉",
            .japanese: "クイックオープン",
            .german: "Schnellsuche",
            .french: "Ouverture rapide",
            .spanish: "Apertura rápida"
        ],
        "AI Assistant": [
            .english: "AI Assistant",
            .simplifiedChinese: "AI 助手",
            .traditionalChinese: "AI 助手",
            .japanese: "AIアシスタント",
            .german: "KI-Assistent",
            .french: "Assistant IA",
            .spanish: "Asistente IA"
        ],
        "Shell Setup": [
            .english: "Shell Setup",
            .simplifiedChinese: "Shell 配置",
            .traditionalChinese: "Shell 設定",
            .japanese: "Shell設定",
            .german: "Shell-Konfiguration",
            .french: "Configuration Shell",
            .spanish: "Configuración Shell"
        ],
        "Help Manual": [
            .english: "Help Manual",
            .simplifiedChinese: "帮助手册",
            .traditionalChinese: "說明手冊",
            .japanese: "ヘルプマニュアル",
            .german: "Hilfehandbuch",
            .french: "Manuel d'aide",
            .spanish: "Manual de ayuda"
        ],
        "Health Score": [
            .english: "Health Score",
            .simplifiedChinese: "健康评分",
            .traditionalChinese: "健康評分",
            .japanese: "ヘルススコア",
            .german: "Gesundheitswert",
            .french: "Score de santé",
            .spanish: "Puntuación de salud"
        ],

        // Pro Features & Telemetry
        "LaunchAgent Automation": [
            .english: "LaunchAgent Automation",
            .simplifiedChinese: "后台自动化",
            .traditionalChinese: "背景自動化",
            .japanese: "バックグラウンド自動化",
            .german: "Hintergrund-Automatisierung",
            .french: "Automatisation en arrière-plan",
            .spanish: "Automatización en segundo plano"
        ],
        "Dual Prefix Switcher": [
            .english: "Dual Prefix Switcher",
            .simplifiedChinese: "多根目录切换",
            .traditionalChinese: "多根目錄切換",
            .japanese: "デュアルプレフィックス切替",
            .german: "Dual-Prefix-Umschalter",
            .french: "Sélecteur de préfixe double",
            .spanish: "Selector de prefijo dual"
        ],
        "Snapshot Rollback": [
            .english: "Snapshot Rollback",
            .simplifiedChinese: "时光机快照回滚",
            .traditionalChinese: "時光機快照復原",
            .japanese: "スナップショット復元",
            .german: "Snapshot-Wiederherstellung",
            .french: "Restauration d'instantané",
            .spanish: "Restauración de instantáneas"
        ],
        "Service Watchdog": [
            .english: "Service Watchdog",
            .simplifiedChinese: "服务看门狗",
            .traditionalChinese: "服務守護進程",
            .japanese: "サービス監視",
            .german: "Dienst-Watchdog",
            .french: "Surveillance de services",
            .spanish: "Vigilante de servicios"
        ],
        "Fast Growing": [
            .english: "Fast Growing",
            .simplifiedChinese: "快速增长",
            .traditionalChinese: "快速增長",
            .japanese: "急上昇",
            .german: "Schnell wachsend",
            .french: "Croissance rapide",
            .spanish: "Rápido crecimiento"
        ],
        "Steady Growth": [
            .english: "Steady Growth",
            .simplifiedChinese: "平稳增长",
            .traditionalChinese: "平穩增長",
            .japanese: "安定成長",
            .german: "Stetiges Wachstum",
            .french: "Croissance stable",
            .spanish: "Crecimiento constante"
        ],
        "Declining": [
            .english: "Declining",
            .simplifiedChinese: "下降趋势",
            .traditionalChinese: "下降趨勢",
            .japanese: "減少傾向",
            .german: "Rückläufig",
            .french: "En déclin",
            .spanish: "En descenso"
        ]
    ]

    init() {
        if let saved = UserDefaults.standard.string(forKey: key), let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
                self.currentLanguage = .traditionalChinese
            } else if preferred.hasPrefix("zh") {
                self.currentLanguage = .simplifiedChinese
            } else if preferred.hasPrefix("ja") {
                self.currentLanguage = .japanese
            } else if preferred.hasPrefix("de") {
                self.currentLanguage = .german
            } else if preferred.hasPrefix("fr") {
                self.currentLanguage = .french
            } else if preferred.hasPrefix("es") {
                self.currentLanguage = .spanish
            } else {
                self.currentLanguage = .english
            }
        }
    }

    func localized(_ key: String) -> String {
        Self.translations[key]?[currentLanguage] ?? key
    }

    func reset() {
        currentLanguage = .english
    }
}
