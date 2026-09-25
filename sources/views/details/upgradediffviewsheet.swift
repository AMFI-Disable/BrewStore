import AppKit
import SwiftUI

struct UpgradeDiffViewSheet: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    @StateObject private var engine = UpgradeDiffEngine.shared
    @Environment(\.dismiss) private var dismiss

    @State private var diffSearchText = ""
    @State private var copiedDiff = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if engine.isLoading {
                loadingView
            } else if let manifest = engine.activeManifest {
                ScrollView {
                    VStack(spacing: 16) {
                        versionSummaryCard(manifest)

                        if manifest.dependencyDelta.hasChanges {
                            dependencyDeltaCard(manifest.dependencyDelta)
                        }

                        if let caveats = manifest.caveatsDelta, !caveats.isEmpty {
                            caveatsCard(caveats)
                        }

                        diffContentCard(manifest)
                    }
                    .padding(16)
                }
            } else {
                emptyOrErrorView
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .onAppear {
            Task {
                let prefix = manager.brewPrefix ?? "/opt/homebrew"
                _ = await engine.generateUpgradeDiff(for: package, prefix: prefix)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: package.kind == .cask ? "macwindow" : "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(package.name)
                        .font(.headline)
                    Text(package.kind.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("Manifest & Version Upgrade Diff Previewer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let manifest = engine.activeManifest {
                Button {
                    manager.perform(package: package, action: .upgrade)
                    dismiss()
                } label: {
                    Label("Upgrade to v\(manifest.upstreamVersion)", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isOperating)
            }

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Version Summary Card

    private func versionSummaryCard(_ manifest: UpgradeDiffManifest) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Installed Version")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("v\(manifest.installedVersion)")
                    .font(.title3.bold().monospaced())
            }

            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Upstream Version")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("v\(manifest.upstreamVersion)")
                    .font(.title3.bold().monospaced())
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(manifest.versionJump.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(badgeColor(for: manifest.versionJump))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor(for: manifest.versionJump).opacity(0.15), in: Capsule())

                HStack(spacing: 8) {
                    Text("+\(manifest.addedLinesCount) lines")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                    Text("-\(manifest.removedLinesCount) lines")
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func badgeColor(for jump: VersionJumpType) -> Color {
        switch jump {
        case .major: .red
        case .minor: .blue
        case .patch: .green
        case .unknown: .secondary
        }
    }

    // MARK: - Dependency Delta Card

    private func dependencyDeltaCard(_ delta: DependencyDelta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(Color.accentColor)
                Text("Dependency Specification Changes")
                    .font(.subheadline.bold())
            }

            if !delta.added.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Added:")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .frame(width: 65, alignment: .leading)
                    FlowLayout(spacing: 6) {
                        ForEach(delta.added, id: \.self) { dep in
                            Text("+ \(dep)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            if !delta.removed.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Removed:")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .frame(width: 65, alignment: .leading)
                    FlowLayout(spacing: 6) {
                        ForEach(delta.removed, id: \.self) { dep in
                            Text("- \(dep)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Caveats Card

    private func caveatsCard(_ caveats: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Formula Caveats & Instructions")
                    .font(.subheadline.bold())
            }

            MarkdownTextView(markdown: caveats, baseFont: .caption, lineSpacing: 3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Diff Content Card

    private func diffContentCard(_ manifest: UpgradeDiffManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manifest Source Diff (.rb)")
                    .font(.subheadline.bold())

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter diff lines…", text: $diffSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 140)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))

                Button {
                    let fullText = manifest.diffLines.map { "\($0.type.prefix) \($0.content)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                    copiedDiff = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedDiff = false
                    }
                } label: {
                    Label(copiedDiff ? "Copied" : "Copy Diff", systemImage: copiedDiff ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)

                if let rubyPath = manifest.rubySourcePath {
                    Button {
                        let githubURL = "https://github.com/Homebrew/homebrew-core/blob/master/\(rubyPath)"
                        if let url = URL(string: githubURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
            }

            // Diff View
            let filteredLines = manifest.diffLines.filter {
                diffSearchText.isEmpty || $0.content.localizedCaseInsensitiveContains(diffSearchText)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredLines) { line in
                    diffLineRow(line)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func diffLineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 8) {
            // Line numbers
            HStack(spacing: 4) {
                Text(line.oldLineNumber.map { "\($0)" } ?? "")
                    .frame(width: 30, alignment: .trailing)
                Text(line.newLineNumber.map { "\($0)" } ?? "")
                    .frame(width: 30, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary.opacity(0.6))

            // Prefix symbol (+, -, or space)
            Text(line.type.prefix)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(lineTextColor(for: line.type))
                .frame(width: 10)

            // Content
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineTextColor(for: line.type))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(lineBackgroundColor(for: line.type))
    }

    private func lineBackgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: Color.green.opacity(0.12)
        case .removed: Color.red.opacity(0.12)
        case .unchanged: Color.clear
        case .header: Color.blue.opacity(0.08)
        }
    }

    private func lineTextColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: .green
        case .removed: .red
        case .unchanged: .primary
        case .header: .blue
        }
    }

    // MARK: - Loading & Empty

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Comparing installed manifest with remote upstream release…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    private var emptyOrErrorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Unable to generate upgrade diff for '\(package.name)'.")
                .font(.subheadline)
            Text("Verify that the package is installed and connected to a valid Homebrew tap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
}

// MARK: - Flow Layout Helper

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
            height = currentY + maxHeightInRow
        }

        return CGSize(width: width, height: max(height, maxHeightInRow))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
    }
}
