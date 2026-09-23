import AppKit
import SwiftUI

struct WorkspacesView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var workspaceManager = BrewStoreWorkspaceManager.shared
    @State private var showingCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if workspaceManager.isSwitching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(workspaceManager.statusMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(workspaceManager.profiles) { profile in
                            workspaceCard(profile: profile)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            createWorkspaceSheet
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "briefcase.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace Profiles").font(.title2.bold())
                Text("Switch runtime versions, background services, and toolchains in one click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let active = workspaceManager.activeProfile {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Active: \(active.name)").font(.caption.bold())
                    Button("Deactivate") {
                        workspaceManager.deactivateCurrentWorkspace()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1), in: Capsule())
            }

            Button {
                showingCreateSheet = true
            } label: {
                Label("New Workspace", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private func workspaceCard(profile: BrewStoreWorkspaceProfile) -> some View {
        let isActive = workspaceManager.activeProfileID == profile.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: profile.icon)
                    .font(.title2)
                    .foregroundStyle(profile.color)
                    .frame(width: 36, height: 36)
                    .background(profile.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(profile.name).font(.headline)
                        if isActive {
                            Text("ACTIVE WORKSPACE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(profile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Button("Active") {}
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        .disabled(true)
                } else {
                    Button("Activate Workspace") {
                        workspaceManager.activateWorkspace(profile: profile, manager: manager)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(workspaceManager.isSwitching || manager.isOperating)
                }

                if !profile.isBuiltIn {
                    Button(role: .destructive) {
                        workspaceManager.deleteProfile(id: profile.id)
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            // Runtime Version Links
            if !profile.versionLinks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Linked Runtimes").font(.caption2.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Array(profile.versionLinks.keys.sorted()), id: \.self) { base in
                            if let target = profile.versionLinks[base] {
                                HStack(spacing: 4) {
                                    Text(base).font(.caption2).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.system(size: 8))
                                    Text(target).font(.caption2.bold().monospaced())
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
            }

            // Services
            if !profile.servicesToStart.isEmpty || !profile.servicesToStop.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background Services").font(.caption2.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(profile.servicesToStart, id: \.self) { s in
                            Label("Start \(s)", systemImage: "play.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        }
                        ForEach(profile.servicesToStop, id: \.self) { s in
                            Label("Stop \(s)", systemImage: "stop.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: isActive ? 2 : 1)
        )
    }

    @State private var newName = ""
    @State private var newDesc = ""
    @State private var newIcon = "briefcase.fill"
    @State private var newColor = "blue"

    private var createWorkspaceSheet: some View {
        VStack(spacing: 16) {
            Text("Create Custom Workspace").font(.headline)

            Form {
                TextField("Workspace Name:", text: $newName)
                TextField("Description:", text: $newDesc)
                Picker("Accent Color:", selection: $newColor) {
                    Text("Blue").tag("blue")
                    Text("Purple").tag("purple")
                    Text("Orange").tag("orange")
                    Text("Teal").tag("teal")
                    Text("Green").tag("green")
                }
            }
            .padding()

            HStack {
                Button("Cancel") { showingCreateSheet = false }
                Spacer()
                Button("Create") {
                    let prof = BrewStoreWorkspaceProfile(
                        id: UUID().uuidString,
                        name: newName.isEmpty ? "My Workspace" : newName,
                        description: newDesc.isEmpty ? "Custom environment profile." : newDesc,
                        icon: newIcon,
                        accentColor: newColor,
                        versionLinks: [:],
                        servicesToStart: [],
                        servicesToStop: [],
                        requiredPackages: [],
                        isBuiltIn: false
                    )
                    workspaceManager.addProfile(prof)
                    showingCreateSheet = false
                    newName = ""
                    newDesc = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 440)
        .padding()
    }
}
