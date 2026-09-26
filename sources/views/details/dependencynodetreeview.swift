import SwiftUI

enum DependencyTreeViewMode: String, CaseIterable, Identifiable {
    case interactive = "Interactive Tree"
    case rawTerminal = "Terminal Output"

    var id: String { rawValue }
}

struct DependencyNodeTreeView: View {
    let rootPackage: BrewStorePackage
    let allPackages: [BrewStorePackage]
    var asciiTree: String?
    var onSelectPackage: ((BrewStorePackage) -> Void)?

    @State private var viewMode: DependencyTreeViewMode = .interactive
    @State private var expandedNodeIDs: Set<String> = []
    @State private var searchQuery: String = ""

    private var rootNode: DependencyTreeNode {
        DependencyTreeBuilder.buildRecursiveTree(for: rootPackage, in: allPackages)
    }

    private var packageMap: [String: BrewStorePackage] {
        Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Controls
            HStack(spacing: 8) {
                if asciiTree != nil {
                    Picker("View Mode", selection: $viewMode) {
                        ForEach(DependencyTreeViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 240)
                }

                if viewMode == .interactive && !rootNode.children.isEmpty {
                    Button(allExpanded ? "Collapse All" : "Expand All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if allExpanded {
                                expandedNodeIDs.removeAll()
                            } else {
                                expandAll(node: rootNode)
                            }
                        }
                    }
                    .controlSize(.small)

                    Spacer()

                    BrewStoreSectionSearchBar(text: $searchQuery, placeholder: "Filter tree…")
                        .frame(maxWidth: 180)
                } else {
                    Spacer()
                }
            }

            if viewMode == .rawTerminal, let tree = asciiTree {
                // Raw ASCII view
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(tree)
                        .font(.caption.monospaced())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            } else {
                // Interactive Recursive Tree View
                if rootNode.children.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No dependencies required. This formula operates standalone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rootNode.children) { childNode in
                            DependencyTreeNodeRowView(
                                node: childNode,
                                packageMap: packageMap,
                                searchQuery: searchQuery,
                                expandedNodeIDs: $expandedNodeIDs,
                                onSelectPackage: onSelectPackage
                            )
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
            }
        }
        .onAppear {
            // Default: expand top level children
            for child in rootNode.children {
                expandedNodeIDs.insert(child.id)
            }
        }
    }

    private var allExpanded: Bool {
        !expandedNodeIDs.isEmpty
    }

    private func expandAll(node: DependencyTreeNode) {
        expandedNodeIDs.insert(node.id)
        for child in node.children {
            expandAll(node: child)
        }
    }
}

private struct DependencyTreeNodeRowView: View {
    let node: DependencyTreeNode
    let packageMap: [String: BrewStorePackage]
    let searchQuery: String
    @Binding var expandedNodeIDs: Set<String>
    var onSelectPackage: ((BrewStorePackage) -> Void)?

    private var isExpanded: Bool {
        expandedNodeIDs.contains(node.id)
    }

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    private var isMatch: Bool {
        searchQuery.isEmpty ||
            node.name.localizedCaseInsensitiveContains(searchQuery) ||
            node.packageID.localizedCaseInsensitiveContains(searchQuery)
    }

    var body: some View {
        if isMatch || hasMatchingDescendant(node: node) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Tree Indentation Guide
                    if node.depth > 1 {
                        HStack(spacing: 4) {
                            ForEach(1..<node.depth, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 1.5, height: 16)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }

                    // Hierarchy Connector Glyph
                    Text(hasChildren ? (isExpanded ? "▾" : "▸") : "└─")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                        .onTapGesture {
                            if hasChildren {
                                toggleExpand()
                            }
                        }

                    // Package Type Icon
                    Image(systemName: node.kind == .cask ? "app.fill" : "shippingbox.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(node.isInstalled ? Color.green : Color.accentColor)

                    // Package Name & Click Action
                    Button {
                        if let resolved = packageMap[node.packageID.lowercased()] {
                            onSelectPackage?(resolved)
                        } else {
                            let placeholder = BrewStorePackage(
                                id: node.packageID,
                                name: node.name,
                                description: "",
                                homepage: "",
                                version: node.version,
                                kind: node.kind
                            )
                            onSelectPackage?(placeholder)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(node.name)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(isMatch && !searchQuery.isEmpty ? Color.accentColor : Color.primary)
                                .underline(isMatch && !searchQuery.isEmpty)

                            if !node.version.isEmpty {
                                Text(node.version)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to inspect \(node.name)")

                    // Cycle Warning
                    if node.isCycle {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Circular")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                    }

                    // Build Tool Badge
                    if node.isBuildOnly {
                        HStack(spacing: 2) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                            Text("Build Dep")
                        }
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                    }

                    Spacer()

                    // Installed Status Pill
                    if node.isInstalled {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("Installed")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1), in: Capsule())
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 8))
                            Text("Available")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(isMatch && !searchQuery.isEmpty ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 4))

                // Recursively render children if expanded
                if isExpanded && hasChildren {
                    ForEach(node.children) { child in
                        DependencyTreeNodeRowView(
                            node: child,
                            packageMap: packageMap,
                            searchQuery: searchQuery,
                            expandedNodeIDs: $expandedNodeIDs,
                            onSelectPackage: onSelectPackage
                        )
                    }
                }
            }
        }
    }

    private func toggleExpand() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedNodeIDs.contains(node.id) {
                expandedNodeIDs.remove(node.id)
            } else {
                expandedNodeIDs.insert(node.id)
            }
        }
    }

    private func hasMatchingDescendant(node: DependencyTreeNode) -> Bool {
        guard !searchQuery.isEmpty else { return false }
        for child in node.children {
            if child.name.localizedCaseInsensitiveContains(searchQuery) ||
                child.packageID.localizedCaseInsensitiveContains(searchQuery) ||
                hasMatchingDescendant(node: child) {
                return true
            }
        }
        return false
    }
}
