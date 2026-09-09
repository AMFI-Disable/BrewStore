import SwiftUI

enum AppAccentTheme: String, CaseIterable, Identifiable, Codable {
    case amberBrew = "Warm Amber"
    case neonCyan = "Cyan Blue"
    case emeraldTerminal = "Emerald Green"
    case cyberViolet = "Royal Violet"
    case sunsetRuby = "Ruby Red"
    case carbonMonochrome = "Graphite Gray"

    var id: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .amberBrew:
            Color(red: 0.96, green: 0.64, blue: 0.12)
        case .neonCyan:
            Color(red: 0.0, green: 0.82, blue: 0.95)
        case .emeraldTerminal:
            Color(red: 0.18, green: 0.80, blue: 0.44)
        case .cyberViolet:
            Color(red: 0.65, green: 0.35, blue: 0.98)
        case .sunsetRuby:
            Color(red: 0.96, green: 0.26, blue: 0.42)
        case .carbonMonochrome:
            Color(red: 0.55, green: 0.58, blue: 0.65)
        }
    }

    var icon: String {
        switch self {
        case .amberBrew: "cup.and.saucer.fill"
        case .neonCyan: "bolt.fill"
        case .emeraldTerminal: "terminal.fill"
        case .cyberViolet: "sparkles"
        case .sunsetRuby: "flame.fill"
        case .carbonMonochrome: "circle.fill"
        }
    }
}

enum WindowVibrancyLevel: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard Material"
    case highTranslucency = "High Translucency Glass"
    case solid = "Solid Opaque"

    var id: String {
        rawValue
    }
}

@MainActor
final class BrewStoreThemeVibrancyManager: ObservableObject {
    static let shared = BrewStoreThemeVibrancyManager()

    private let themeKey = "BrewStore.AppAccentTheme"
    private let vibrancyKey = "BrewStore.WindowVibrancyLevel"

    @Published var currentTheme: AppAccentTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
        }
    }

    @Published var vibrancyLevel: WindowVibrancyLevel {
        didSet {
            UserDefaults.standard.set(vibrancyLevel.rawValue, forKey: vibrancyKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: themeKey),
           let savedTheme = AppAccentTheme(rawValue: raw) {
            self.currentTheme = savedTheme
        } else {
            self.currentTheme = .amberBrew
        }

        if let raw = UserDefaults.standard.string(forKey: vibrancyKey),
           let savedVibrancy = WindowVibrancyLevel(rawValue: raw) {
            self.vibrancyLevel = savedVibrancy
        } else {
            self.vibrancyLevel = .standard
        }
    }

    func reset() {
        currentTheme = .amberBrew
        vibrancyLevel = .standard
    }
}
