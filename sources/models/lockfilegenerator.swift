import Foundation

struct BrewStoreLockfileEntry: Codable, Sendable {
    let id: String
    let name: String
    let kind: String
    let version: String
    let tap: String?
    let isPinned: Bool
    let dependencies: [String]
}

struct BrewStoreLockfileDocument: Codable, Sendable {
    let schemaVersion: String
    let generatedAt: String
    let arch: String
    let osVersion: String
    let totalPackages: Int
    let taps: [String]
    let entries: [BrewStoreLockfileEntry]

    init(
        schemaVersion: String = "1.0.0",
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        arch: String = ProcessInfo.processInfo.machineArchitecture,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        totalPackages: Int,
        taps: [String],
        entries: [BrewStoreLockfileEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.arch = arch
        self.osVersion = osVersion
        self.totalPackages = totalPackages
        self.taps = taps
        self.entries = entries
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
            return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
            return "x86_64 (Intel)"
        #else
            return "unknown"
        #endif
    }
}

@MainActor
enum BrewStoreLockfileGenerator {
    static func generateLockfile(
        packages: [BrewStorePackage],
        taps: [BrewStoreTap] = [],
        pinningManager: BrewStorePackagePinningManager? = nil
    ) -> BrewStoreLockfileDocument {
        let resolvedPinningManager = pinningManager ?? BrewStorePackagePinningManager.shared
        let installed = packages.filter(\.isInstalled).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        let entries = installed.map { pkg in
            BrewStoreLockfileEntry(
                id: pkg.id,
                name: pkg.name,
                kind: pkg.kind.rawValue,
                version: pkg.version,
                tap: pkg.tap,
                isPinned: resolvedPinningManager.isPinned(packageID: pkg.id),
                dependencies: pkg.dependencies.sorted()
            )
        }

        let tapNames = taps.map(\.name).sorted()

        return BrewStoreLockfileDocument(
            totalPackages: entries.count,
            taps: tapNames,
            entries: entries
        )
    }

    static func generateJSONString(
        packages: [BrewStorePackage],
        taps: [BrewStoreTap] = [],
        pinningManager: BrewStorePackagePinningManager? = nil
    ) -> String {
        let doc = generateLockfile(packages: packages, taps: taps, pinningManager: pinningManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(doc),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return str
    }

    nonisolated static func generateMermaidGraph(
        packages: [BrewStorePackage],
        maxNodes: Int = 80
    ) -> String {
        let installed = packages.filter(\.isInstalled)
        var lines: [String] = ["graph TD"]

        // Subgraph for packages with dependencies
        var addedEdges = 0
        for pkg in installed {
            let sanitizedFrom = sanitizeMermaidNodeID(pkg.id)
            for dep in pkg.dependencies {
                let sanitizedTo = sanitizeMermaidNodeID(dep)
                lines.append("    \(sanitizedFrom)[\"\(pkg.name)\"] --> \(sanitizedTo)[\"\(dep)\"]")
                addedEdges += 1
                if addedEdges >= maxNodes {
                    break
                }
            }
            if addedEdges >= maxNodes {
                break
            }
        }

        if addedEdges == 0 {
            lines.append("    EmptyGraph[\"No Package Dependencies Mapped\"]")
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func generateGraphvizDot(
        packages: [BrewStorePackage],
        maxNodes: Int = 100
    ) -> String {
        let installed = packages.filter(\.isInstalled)
        var lines: [String] = [
            "digraph BrewStoreDependencies {",
            "    rankdir=LR;",
            "    node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fillcolor=\"#F8F9FA\", color=\"#B0C4DE\", fontsize=10];",
            "    edge [color=\"#6C757D\", arrowhead=\"vee\", arrowsize=0.8];",
            ""
        ]

        var addedEdges = 0
        for pkg in installed {
            let fromName = pkg.name.replacingOccurrences(of: "\"", with: "\\\"")
            for dep in pkg.dependencies {
                let toName = dep.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("    \"\(fromName)\" -> \"\(toName)\";")
                addedEdges += 1
                if addedEdges >= maxNodes {
                    break
                }
            }
            if addedEdges >= maxNodes {
                break
            }
        }

        if addedEdges == 0 {
            lines.append("    \"EmptyGraph\" [label=\"No Package Dependencies Mapped\", shape=note];")
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    nonisolated static func generateMarkdownTree(packages: [BrewStorePackage]) -> String {
        let installed = packages.filter(\.isInstalled).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !installed.isEmpty else {
            return "No installed packages found."
        }

        var lines: [String] = ["# Package Dependency Tree", ""]

        for pkg in installed {
            let pinMark = pkg.isPinned ? " 🔒" : ""
            lines.append("- **\(pkg.name)** (`\(pkg.version)`)\(pinMark) - *\(pkg.kind.rawValue)*")
            if !pkg.dependencies.isEmpty {
                for dep in pkg.dependencies.sorted() {
                    lines.append("  - └── \(dep)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    nonisolated private static func sanitizeMermaidNodeID(_ id: String) -> String {
        id.replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "__")
    }
}
