import SwiftUI

struct PackageDetailSimilarToolsView: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    @Binding var activeSheet: PackageDetailSheet?
    @Binding var selectedPackage: BrewStorePackage?

    var body: some View {
        let alternatives = BrewStoreAlternativeRecommendationManager.findAlternatives(for: package, in: manager.packages)
        if !alternatives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(Color.accentColor)
                    Text("Similar Tools & Alternatives").font(.title3.bold())

                    Text("\(alternatives.count)")
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    Spacer()

                    if let firstAlt = alternatives.first {
                        Button {
                            activeSheet = .showdown(firstAlt)
                        } label: {
                            Label("Compare in Showdown", systemImage: "flame.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                        .help("Launch head-to-head comparison showdown between \(package.name) and \(firstAlt.name)")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(alternatives) { alt in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedPackage = alt
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            PackageIconView(package: alt, size: 34, cornerRadius: 8)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(alt.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(alt.displayKind)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Text(alt.description.isEmpty ? "Alternative tool in the same category." : alt.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .frame(height: 32, alignment: .topLeading)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)

                                HStack {
                                    AppStoreActionButton(manager: manager, package: alt, size: .small)
                                    Spacer()
                                    Button {
                                        activeSheet = .showdown(alt)
                                    } label: {
                                        Image(systemName: "flame.fill")
                                            .font(.caption2)
                                            .foregroundStyle(Color.orange)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(Color.orange.opacity(0.12), in: Circle())
                                    .help("Compare \(package.name) vs \(alt.name) in Showdown")
                                }
                            }
                            .padding(14)
                            .frame(width: 230)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
