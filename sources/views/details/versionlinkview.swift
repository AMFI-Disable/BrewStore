import AppKit
import SwiftUI

struct VersionLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var linkManager = BrewStoreVersionLinkManager.shared

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if linkManager.isSwitching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(linkManager.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if linkManager.families.isEmpty {
                ContentUnavailableView(
                    "No Multiple Versions Found",
                    systemImage: "arrow.triangle.swap",
                    description: Text("Install multiple versions of tools like Node.js (node, node@20), Python (python@3.11, python@3.12), or OpenJDK to switch between them.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                familiesListView
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            linkManager.refresh(packages: manager.packages)
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "arrow.triangle.swap")
                .font(.title2)
                .foregroundStyle(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Version Switcher").font(.title2.bold())
                Text("Switch the active version of Node, Python, Java, and PostgreSQL.")
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
    }

    private var familiesListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(linkManager.families) { family in
                    familyCard(family: family)
                }
            }
            .padding(20)
        }
    }

    private func familyCard(family: VersionFamily) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(family.name).font(.headline)
                Spacer()
                Text("\(family.installedMembers.count) of \(family.members.count) versions installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(family.members) { member in
                    HStack(spacing: 12) {
                        Image(systemName: member.isActiveLinked ? "checkmark.circle.fill" : (member.isInstalled ? "circle" : "arrow.down.circle"))
                            .foregroundStyle(member.isActiveLinked ? .green : (member.isInstalled ? .blue : .secondary))
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.displayName).font(.subheadline.bold())
                                if member.isActiveLinked {
                                    Text("ACTIVE LINKED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("v\(member.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if member.isActiveLinked {
                            Text("Current").font(.caption.bold()).foregroundStyle(.green)
                        } else if member.isInstalled {
                            Button("Activate") {
                                linkManager.switchVersion(to: member, in: family, manager: manager)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(linkManager.isSwitching || manager.isOperating)
                        } else {
                            if let pkg = manager.packages.first(where: { $0.id == member.packageID }) {
                                Button("Install") {
                                    manager.perform(package: pkg, action: .install)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(manager.isOperating)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
