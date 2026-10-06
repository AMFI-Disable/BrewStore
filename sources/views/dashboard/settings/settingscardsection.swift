import AppKit
import SwiftUI

struct SettingsCardSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(title).font(.headline)
            }
            Divider()
            content()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

func formatRefreshInterval(_ seconds: Int) -> String {
    if seconds < 60 {
        return "\(seconds)s"
    } else if seconds % 60 == 0 {
        let mins = seconds / 60
        return "\(mins) min\(mins == 1 ? "" : "s")"
    } else {
        let mins = seconds / 60
        let rem = seconds % 60
        return "\(mins)m \(rem)s"
    }
}
