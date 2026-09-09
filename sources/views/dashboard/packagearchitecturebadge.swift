import AppKit
import SwiftUI

struct PackageArchitectureBadge: View {
    let architecture: BinaryArchitectureType?

    var body: some View {
        if let arch = architecture, arch != .unknown {
            Text(label(for: arch))
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(badgeColor(for: arch).opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor(for: arch))
        }
    }

    private func label(for arch: BinaryArchitectureType) -> String {
        switch arch {
        case .appleSilicon:
            "arm64"
        case .universal2:
            "Universal"
        case .intel:
            "Rosetta 2"
        case .unknown:
            ""
        }
    }

    private func badgeColor(for arch: BinaryArchitectureType) -> Color {
        switch arch {
        case .appleSilicon, .universal2:
            .green
        case .intel:
            .orange
        case .unknown:
            .secondary
        }
    }
}
