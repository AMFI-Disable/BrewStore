import SwiftUI

struct PackageDetailInformationCard: View {
    let package: BrewStorePackage
    let brewPrefix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information").font(.headline)

            VStack(spacing: 6) {
                HStack {
                    Text("Tap / Source").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(package.tap ?? "homebrew/core").font(.caption.monospaced()).lineLimit(1)
                }
                Divider()
                HStack {
                    Text("Kind").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(package.displayKind).font(.caption)
                }
                if let cellar = package.cellarURL(prefix: brewPrefix) {
                    Divider()
                    HStack {
                        Text("Cellar").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(cellar.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                    }
                    .help(cellar.path)
                }
                if let homepage = URL(string: package.homepage), !package.homepage.isEmpty {
                    Divider()
                    HStack {
                        Text("Homepage").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Link(destination: homepage) {
                            HStack(spacing: 3) {
                                Text("Visit Site")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }
}
