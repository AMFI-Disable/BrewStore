import SwiftUI

struct PackageDetailCaveatsCard: View {
    let package: BrewStorePackage
    let manager: HomebrewManager
    let caveats: String

    @StateObject private var shellAssistant = BrewStoreShellConfigAssistant()
    @State private var caveatAppliedSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill").foregroundStyle(.blue).font(.caption)
                Text("Configuration & Shell Setup").font(.headline)
            }

            MarkdownTextView(markdown: caveats, baseFont: .caption, lineSpacing: 3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))

            let exportLines = shellAssistant.extractCaveatExports(from: caveats)
            if !exportLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exportLines.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button {
                            let snippet = exportLines.joined(separator: "\n")
                            if shellAssistant.injectCaveatSnippet(
                                packageName: package.name,
                                snippet: snippet,
                                manager: manager
                            ) {
                                caveatAppliedSuccess = true
                            }
                        } label: {
                            Label(
                                caveatAppliedSuccess ?
                                    "Applied to .\(shellAssistant.detectedShell)rc" :
                                    "1-Click Apply to .\(shellAssistant.detectedShell)rc",
                                systemImage: caveatAppliedSuccess ? "checkmark.circle.fill" : "arrow.down.doc.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(caveatAppliedSuccess ? .green : .blue)
                        .controlSize(.small)
                        .disabled(caveatAppliedSuccess)

                        if let status = shellAssistant.statusMessage {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }
}
