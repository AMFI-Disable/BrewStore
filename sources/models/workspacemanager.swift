import Foundation
import SwiftUI

struct BrewStoreWorkspaceProfile: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var description: String
    var icon: String
    var accentColor: String
    var versionLinks: [String: String] // Base runtime family (e.g. "node") -> Target package ID ("node@20")
    var servicesToStart: [String]
    var servicesToStop: [String]
    var requiredPackages: [String]
    var isBuiltIn: Bool

    var color: Color {
        switch accentColor {
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "teal": .teal
        case "green": .green
        case "pink": .pink
        default: .blue
        }
    }
}

@MainActor
final class BrewStoreWorkspaceManager: ObservableObject {
    static let shared = BrewStoreWorkspaceManager()

    @Published var profiles: [BrewStoreWorkspaceProfile] = []
    @Published var activeProfileID: String?
    @Published var isSwitching = false
    @Published var statusMessage = ""

    private let fileManager = FileManager.default
    private let storageURL: URL

    init() {
        let appSupport = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
            .appendingPathComponent("BrewStore", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.storageURL = appSupport.appendingPathComponent("workspaces.json")

        self.activeProfileID = UserDefaults.standard.string(forKey: "BrewStore.activeWorkspaceID")
        loadProfiles()
    }

    var activeProfile: BrewStoreWorkspaceProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    func loadProfiles() {
        var loaded: [BrewStoreWorkspaceProfile] = []

        if fileManager.fileExists(atPath: storageURL.path),
           let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([BrewStoreWorkspaceProfile].self, from: data) {
            loaded = decoded
        }

        // Merge with built-in templates if not already present
        for template in Self.builtInTemplates {
            if !loaded.contains(where: { $0.id == template.id }) {
                loaded.append(template)
            }
        }

        self.profiles = loaded
    }

    func saveCustomProfiles() {
        let customOnly = profiles.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customOnly) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    func addProfile(_ profile: BrewStoreWorkspaceProfile) {
        profiles.append(profile)
        saveCustomProfiles()
    }

    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id && !$0.isBuiltIn }
        if activeProfileID == id {
            activeProfileID = nil
            UserDefaults.standard.removeObject(forKey: "BrewStore.activeWorkspaceID")
        }
        saveCustomProfiles()
    }

    /// Activates a workspace profile: switches runtime versions and starts/stops background daemons.
    func activateWorkspace(profile: BrewStoreWorkspaceProfile, manager: HomebrewManager) {
        guard !isSwitching else { return }
        isSwitching = true
        statusMessage = "Activating workspace '\(profile.name)'…"

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Switch version families
            for (_, targetPackageID) in profile.versionLinks {
                if let targetPkg = manager.packages.first(where: { $0.id == targetPackageID && $0.isInstalled }) {
                    let baseFamily = targetPackageID.components(separatedBy: "@").first ?? targetPackageID
                    let siblings = manager.packages.filter {
                        $0.kind == .formula && $0.isInstalled && ($0.id.components(separatedBy: "@").first ?? $0.id) == baseFamily
                    }

                    if let currentActive = siblings.first(where: { $0.id != targetPackageID }) {
                        self.statusMessage = "Switching \(baseFamily) to \(targetPackageID)…"
                        manager.switchLinkedVersion(from: currentActive, to: targetPkg)
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                }
            }

            // 2. Stop unwanted background services to save battery and RAM
            for serviceName in profile.servicesToStop {
                if let service = manager.services.first(where: { $0.id == serviceName && $0.isRunning }) {
                    self.statusMessage = "Stopping service \(serviceName)…"
                    manager.perform(service: service, action: .stop)
                }
            }

            // 3. Start required services
            for serviceName in profile.servicesToStart {
                if let service = manager.services.first(where: { $0.id == serviceName && !$0.isRunning }) {
                    self.statusMessage = "Starting service \(serviceName)…"
                    manager.perform(service: service, action: .start)
                }
            }

            self.activeProfileID = profile.id
            UserDefaults.standard.set(profile.id, forKey: "BrewStore.activeWorkspaceID")
            self.isSwitching = false
            self.statusMessage = "Workspace '\(profile.name)' is now active."
            manager.refresh()
        }
    }

    func deactivateCurrentWorkspace() {
        activeProfileID = nil
        UserDefaults.standard.removeObject(forKey: "BrewStore.activeWorkspaceID")
        statusMessage = "Deactivated workspace context."
    }

    // MARK: - Built-in Templates

    static let builtInTemplates: [BrewStoreWorkspaceProfile] = [
        BrewStoreWorkspaceProfile(
            id: "fullstack_web",
            name: "Fullstack Web",
            description: "Modern Node.js runtime, PostgreSQL relational database, and Redis caching daemon.",
            icon: "globe.americas.fill",
            accentColor: "blue",
            versionLinks: [
                "node": "node@20",
                "postgresql": "postgresql@14"
            ],
            servicesToStart: ["postgresql@14", "redis"],
            servicesToStop: ["mysql"],
            requiredPackages: ["node@20", "postgresql@14", "redis", "pnpm", "yarn"],
            isBuiltIn: true
        ),
        BrewStoreWorkspaceProfile(
            id: "ai_datascience",
            name: "AI & Data Science",
            description: "Python 3.11 ML ecosystem, JupyterLab notebook runtime, and local Ollama model daemon.",
            icon: "brain.head.profile",
            accentColor: "purple",
            versionLinks: [
                "python": "python@3.11",
                "openjdk": "openjdk@17"
            ],
            servicesToStart: ["ollama"],
            servicesToStop: ["redis", "mysql"],
            requiredPackages: ["python@3.11", "jupyterlab", "uv", "ollama"],
            isBuiltIn: true
        ),
        BrewStoreWorkspaceProfile(
            id: "systems_rust",
            name: "Systems & Rust",
            description: "Low-level native systems toolchain with LLVM, GCC, CMake, and debugging tools.",
            icon: "cpu.fill",
            accentColor: "orange",
            versionLinks: [
                "llvm": "llvm",
                "gcc": "gcc"
            ],
            servicesToStart: [],
            servicesToStop: ["postgresql@14", "redis", "mysql"],
            requiredPackages: ["rust", "cmake", "ninja", "llvm"],
            isBuiltIn: true
        ),
        BrewStoreWorkspaceProfile(
            id: "devops_cloud",
            name: "DevOps & Cloud",
            description: "Container infrastructure, Kubernetes management, Terraform, and Go cloud toolchain.",
            icon: "cloud.fill",
            accentColor: "teal",
            versionLinks: [
                "go": "go",
                "python": "python@3.12"
            ],
            servicesToStart: ["docker"],
            servicesToStop: [],
            requiredPackages: ["terraform", "kubectl", "helm", "k9s", "awscli", "go"],
            isBuiltIn: true
        )
    ]
}
