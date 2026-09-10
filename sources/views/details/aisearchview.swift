import AppKit
import SwiftUI

struct AISearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var assistant = BrewStoreAIAssistant()

    @State private var queryText = ""
    @State private var selectedKindFilter: AISearchKindFilter = .all
    @State private var selectedPackageForDetail: BrewStorePackage?

    private let quickPrompts = [
        "cask browser",
        "formula python",
        "cask:ghostty",
        "Batch convert HEIC photos to PNG",
        "Convert MKV video to MP4 with subtitles",
        "GPU accelerated terminal emulator",
        "Run local AI and LLMs on Mac",
        "Fastest Docker container engine",
        "Database GUI for PostgreSQL & Redis",
        "Search code recursively like lightning",
        "clean disk cache (mole)",
        "what is a cask?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .padding(8)
                    .background(Color.purple.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Package Assistant").font(.title2.bold())
                    Text("100% Offline natural language and type-filtered Homebrew assistant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Input Bar & Type Selector
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Type Filter", selection: $selectedKindFilter) {
                        ForEach(AISearchKindFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    .onChange(of: selectedKindFilter) {
                        if !queryText.isEmpty {
                            assistant.analyze(query: queryText, manager: manager, manualKindFilter: selectedKindFilter)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("100% Offline & Private")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.08), in: Capsule())
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Type what you need: 'cask browser', 'formula rust', 'convert video', 'what is a cask'…", text: $queryText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onSubmit {
                            assistant.analyze(query: queryText, manager: manager, manualKindFilter: selectedKindFilter)
                        }

                    if !queryText.isEmpty {
                        Button {
                            queryText = ""
                            assistant.recommendations = []
                            assistant.educationalNote = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Ask Assistant") {
                        assistant.analyze(query: queryText, manager: manager, manualKindFilter: selectedKindFilter)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1.5)
                )

                // Quick Prompt Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button {
                                queryText = prompt
                                assistant.analyze(query: prompt, manager: manager, manualKindFilter: selectedKindFilter)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: prompt.hasPrefix("cask") ? "app.fill" : (prompt.hasPrefix("formula") ? "terminal.fill" : "sparkles"))
                                        .font(.caption2)
                                    Text(prompt).font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.08), in: Capsule())
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            .background(Color.secondary.opacity(0.02))

            Divider()

            // Recommendations List & Guidance
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = assistant.educationalNote {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.purple)
                            Text(LocalizedStringKey(note))
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    }

                    if assistant.isAnalyzing {
                        ProgressView("Analyzing intent and searching local catalog…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if assistant.recommendations.isEmpty {
                        if !assistant.analyzedQuery.isEmpty {
                            ContentUnavailableView(
                                "No direct matches found for '\(assistant.analyzedQuery)'",
                                systemImage: "sparkles",
                                description: Text("Try searching by type prefix like 'cask <name>' or 'formula <name>', or choose a quick prompt above.")
                            )
                            .padding(.top, 40)
                        } else {
                            syntaxGuideView
                        }
                    } else {
                        HStack {
                            Text("Recommended Solutions for \"\(assistant.analyzedQuery)\"")
                                .font(.headline)

                            if let filter = assistant.detectedFilter {
                                Text(filter == .cask ? "Casks Only" : "Formulae Only")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.purple)
                            }

                            Spacer()
                            Text("\(assistant.recommendations.count) results")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        ForEach(assistant.recommendations) { rec in
                            let installed = manager.packages.first { $0.id == rec.packageID }
                            let pkg = installed ?? BrewStorePackage(
                                id: rec.packageID,
                                name: rec.name,
                                description: rec.headline,
                                homepage: "",
                                version: "",
                                kind: rec.kind
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: rec.kind == .cask ? "app.fill" : "terminal.fill")
                                        .font(.title2)
                                        .foregroundStyle(rec.kind == .cask ? Color.blue : Color.green)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            (rec.kind == .cask ? Color.blue : Color.green).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(rec.name).font(.headline)
                                            Text(rec.kind == .cask ? "macOS App" : "CLI Tool")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())

                                            HStack(spacing: 3) {
                                                Image(systemName: "sparkles").font(.system(size: 9))
                                                Text("\(Int(rec.confidence * 100))% match")
                                                    .font(.system(size: 10).bold())
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.purple.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.purple)
                                        }

                                        Text(rec.headline)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }

                                    Spacer()

                                    AppStoreActionButton(manager: manager, package: pkg)
                                }

                                // Reason & Use Case Quote
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("Why this tool:").font(.caption.bold()).foregroundStyle(.secondary)
                                        Text(rec.reason).font(.caption).foregroundStyle(.primary)
                                    }
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("Best for:").font(.caption.bold()).foregroundStyle(.secondary)
                                        Text(rec.useCase).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                                // Ready-to-Run Action Recipe
                                if let recipe = rec.commandRecipe, !recipe.isEmpty {
                                    HStack(spacing: 8) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 11).monospaced())
                                            .foregroundStyle(.purple)

                                        Text(recipe)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .textSelection(.enabled)

                                        Spacer()

                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(recipe, forType: .string)
                                        } label: {
                                            Label("Copy Recipe", systemImage: "doc.on.doc")
                                                .font(.caption2.bold())
                                        }
                                        .buttonStyle(.borderless)
                                        .controlSize(.mini)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(nsColor: .textBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                                    )
                                }

                                HStack {
                                    HStack(spacing: 6) {
                                        ForEach(rec.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button("Inspect Details") {
                                        selectedPackageForDetail = pkg
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(16)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .detailModalOverlay(item: $selectedPackageForDetail) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
    }

    private var syntaxGuideView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.purple.opacity(0.8))
                Text("How to Query the AI Assistant")
                    .font(.title3.bold())
                Text("Search by package type, natural workflow intent, or ask general Homebrew questions — 100% offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .padding(.top, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                guideCard(
                    icon: "app.fill",
                    color: .blue,
                    title: "1. Search by Cask (macOS Apps)",
                    subtitle: "Type 'cask' or 'cask:' followed by the app type or name.",
                    examples: ["cask browser", "cask code editor", "cask:ghostty", "cask media player"]
                )

                guideCard(
                    icon: "terminal.fill",
                    color: .green,
                    title: "2. Search by Formula (CLI Tools)",
                    subtitle: "Type 'formula' or 'formula:' followed by the tool or language.",
                    examples: ["formula python", "formula rust", "formula:ripgrep", "formula database"]
                )

                guideCard(
                    icon: "sparkles",
                    color: .purple,
                    title: "3. Describe Workflow Tasks",
                    subtitle: "Type problems or tasks in plain conversational English.",
                    examples: ["batch convert HEIC to PNG", "run local LLM", "clean disk cache (mole)", "fastest docker"]
                )

                guideCard(
                    icon: "questionmark.circle.fill",
                    color: .orange,
                    title: "4. Ask Homebrew Concepts",
                    subtitle: "Ask about package management concepts and best practices.",
                    examples: ["what is a cask?", "how to tap a repo", "how to pin packages", "clean cache"]
                )
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 16)
    }

    private func guideCard(icon: String, color: Color, title: String, subtitle: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(examples, id: \.self) { ex in
                    Button {
                        queryText = ex
                        assistant.analyze(query: ex, manager: manager, manualKindFilter: selectedKindFilter)
                    } label: {
                        HStack(spacing: 4) {
                            Text("▸").foregroundStyle(color).font(.caption2)
                            Text(ex).font(.caption.monospaced()).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
