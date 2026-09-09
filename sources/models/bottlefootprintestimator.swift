import Foundation

struct BottleFootprintInfo: Hashable, Codable {
    let packageID: String
    let estimatedDownloadMB: Double
    let estimatedCellarFootprintMB: Double

    var formattedDownloadSize: String {
        if estimatedDownloadMB >= 1000 {
            String(format: "%.1f GB", estimatedDownloadMB / 1024.0)
        } else {
            String(format: "%.1f MB", estimatedDownloadMB)
        }
    }

    var formattedFootprintSize: String {
        if estimatedCellarFootprintMB >= 1000 {
            String(format: "%.1f GB", estimatedCellarFootprintMB / 1024.0)
        } else {
            String(format: "%.1f MB", estimatedCellarFootprintMB)
        }
    }
}

enum BrewStoreBottleFootprintEstimator {
    /// Known sizes for heavy packages (Download MB, Installed MB)
    private static let knownSizes: [String: (download: Double, installed: Double)] = [
        "llvm": (420.0, 3200.0),
        "rust": (180.0, 1200.0),
        "gcc": (130.0, 950.0),
        "openjdk": (195.0, 480.0),
        "python@3.12": (42.0, 210.0),
        "python@3.11": (39.0, 195.0),
        "node": (36.0, 175.0),
        "node@20": (34.0, 165.0),
        "go": (140.0, 620.0),
        "ffmpeg": (65.0, 280.0),
        "imagemagick": (38.0, 160.0),
        "neovim": (18.0, 75.0),
        "ripgrep": (5.2, 19.5),
        "fd": (3.8, 14.2),
        "bat": (4.5, 16.0),
        "fzf": (2.8, 8.5),
        "git": (19.0, 85.0),
        "zstd": (2.1, 7.8),
        "openssl@3": (8.5, 34.0),
        "ca-certificates": (0.3, 0.9),
        "visual-studio-code": (120.0, 380.0),
        "docker": (600.0, 2100.0),
        "google-chrome": (160.0, 490.0),
        "iterm2": (28.0, 92.0)
    ]

    static func estimateFootprint(for package: BrewStorePackage) -> BottleFootprintInfo {
        let lower = package.id.lowercased()
        if let (dl, inst) = knownSizes[lower] {
            return BottleFootprintInfo(
                packageID: package.id,
                estimatedDownloadMB: dl,
                estimatedCellarFootprintMB: inst
            )
        }

        // Heuristic based on kind and dependencies
        if package.kind == .cask {
            let estDL = 85.0
            let estInst = 240.0
            return BottleFootprintInfo(packageID: package.id, estimatedDownloadMB: estDL, estimatedCellarFootprintMB: estInst)
        } else {
            let depCount = Double(package.dependencies.count)
            let baseDL = 4.5 + depCount * 2.8
            let baseInst = baseDL * 3.8
            return BottleFootprintInfo(
                packageID: package.id,
                estimatedDownloadMB: (baseDL * 10).rounded() / 10,
                estimatedCellarFootprintMB: (baseInst * 10).rounded() / 10
            )
        }
    }
}
