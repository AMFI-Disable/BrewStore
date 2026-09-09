import AppKit
import SwiftUI

struct DependencyGraphNode: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: BrewPackageKind
    let isInstalled: Bool
    let isRoot: Bool
    let depth: Int
    var position: CGPoint = .zero
}

struct DependencyGraphEdge: Identifiable, Hashable {
    let id: String
    let fromID: String
    let toID: String
}

enum DependencyGraphMode: String, CaseIterable, Identifiable {
    case upstream = "Upstream (Requires)"
    case downstream = "Downstream (Used By)"
    case dual = "Full Ecosystem"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .upstream: "arrow.right.circle"
        case .downstream: "arrow.left.circle"
        case .dual: "circle.grid.cross"
        }
    }
}

struct DependencyGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let rootPackage: BrewStorePackage

    @State private var graphMode: DependencyGraphMode = .upstream
    @State private var nodes: [DependencyGraphNode] = []
    @State private var edges: [DependencyGraphEdge] = []
    @State private var selectedNode: DependencyGraphNode?
    @State private var hoveredNodeID: String?
    @State private var graphSearchQuery: String = ""
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero

    private var highlightedNodeIDs: Set<String> {
        guard let activeID = selectedNode?.id ?? hoveredNodeID else { return [] }
        var result: Set<String> = [activeID]

        // Find connected upstream and downstream nodes
        for edge in edges {
            if edge.fromID == activeID {
                result.insert(edge.toID)
            }
            if edge.toID == activeID {
                result.insert(edge.fromID)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar: Row 1 Title & Zoom controls; Row 2 Mode Picker & In-Graph Search
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("\(rootPackage.name) Dependency Graph").font(.title2.bold())
                            Text("\(nodes.count) Nodes")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(.tint)

                            Text("\(edges.count) Edges")
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text("Hierarchical DAG with upstream/downstream bidirectional modes and cycle detection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Zoom controls
                    HStack(spacing: 6) {
                        Button(action: { zoomScale = max(0.4, zoomScale - 0.2) }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        Text("\(Int(zoomScale * 100))%")
                            .font(.caption.monospaced())
                            .frame(width: 42)
                        Button(action: { zoomScale = min(2.5, zoomScale + 0.2) }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        Button("Reset") {
                            withAnimation(.spring) {
                                zoomScale = 1.0
                                panOffset = .zero
                                selectedNode = nil
                            }
                        }
                        .controlSize(.small)

                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 12) {
                    // Mode Picker
                    Picker("Graph Mode", selection: $graphMode) {
                        ForEach(DependencyGraphMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: graphMode) {
                        if canvasSize != .zero {
                            layoutDAG(in: canvasSize)
                        }
                    }

                    // In-Graph Search Bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter nodes…", text: $graphSearchQuery)
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                        if !graphSearchQuery.isEmpty {
                            Button { graphSearchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Graph Canvas
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)

                    // Dot Grid Background
                    Canvas { context, size in
                        let spacing: CGFloat = 28 * zoomScale
                        var x: CGFloat = 0
                        while x < size.width {
                            var y: CGFloat = 0
                            while y < size.height {
                                context.fill(
                                    Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                    with: .color(.secondary.opacity(0.12))
                                )
                                y += spacing
                            }
                            x += spacing
                        }
                    }

                    // Interactive Graph Elements
                    ZStack {
                        // Bézier Connection Edges
                        ForEach(edges) { edge in
                            if let fromNode = nodes.first(where: { $0.id == edge.fromID }),
                               let toNode = nodes.first(where: { $0.id == edge.toID }) {
                                let isHighlighted = highlightedNodeIDs.contains(edge.fromID) && highlightedNodeIDs.contains(edge.toID)
                                let hasSelection = !highlightedNodeIDs.isEmpty

                                EdgeLine(from: fromNode.position, to: toNode.position)
                                    .stroke(
                                        isHighlighted ? Color.accentColor : Color.secondary.opacity(hasSelection ? 0.08 : 0.35),
                                        style: StrokeStyle(lineWidth: isHighlighted ? 3 : 1.5, lineCap: .round, lineJoin: .round)
                                    )
                                    .shadow(color: isHighlighted ? Color.accentColor.opacity(0.6) : Color.clear, radius: 4)
                            }
                        }

                        // Nodes
                        ForEach(nodes) { node in
                            let isHighlighted = highlightedNodeIDs.contains(node.id)
                            let isMatched = graphSearchQuery.isEmpty || node.name.localizedCaseInsensitiveContains(graphSearchQuery)

                            NodeBubble(
                                node: node,
                                isSelected: selectedNode?.id == node.id,
                                isHighlighted: isHighlighted,
                                isDimmed: !isMatched || (!highlightedNodeIDs.isEmpty && !isHighlighted)
                            )
                            .position(node.position)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedNode = (selectedNode?.id == node.id) ? nil : node
                                }
                            }
                            .onHover { isHovered in
                                hoveredNodeID = isHovered ? node.id : nil
                            }
                        }
                    }
                    .scaleEffect(zoomScale)
                    .offset(x: panOffset.width + dragOffset.width, y: panOffset.height + dragOffset.height)
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in dragOffset = value.translation }
                        .onEnded { value in
                            panOffset.width += value.translation.width
                            panOffset.height += value.translation.height
                            dragOffset = .zero
                        }
                )
                .onAppear {
                    layoutDAG(in: geometry.size)
                }
            }

            Divider()

            // Inspector Bottom Tray
            HStack(spacing: 16) {
                if let selected = selectedNode {
                    let pkg = manager.packages.first { $0.id == selected.id }
                    HStack(spacing: 12) {
                        Image(systemName: selected.isRoot ? "star.circle.fill" : (selected.isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill"))
                            .foregroundStyle(selected.isRoot ? .yellow : (selected.isInstalled ? .green : .orange))
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(selected.name).font(.headline)
                                Text(selected.isRoot ? "Root Package" : (selected.depth == 1 ? "Direct Dependency" : "Transitive Dependency"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            let desc = pkg?.description ?? ""
                            Text(!desc.isEmpty ? desc : (selected.isInstalled ? "Installed locally on your Mac." : "Required dependency for \(rootPackage.name)."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if !selected.isInstalled {
                            Button("Install \(selected.name)") {
                                let target = BrewStorePackage(id: selected.id, name: selected.name, description: "", homepage: "", version: "", kind: selected.kind)
                                manager.perform(package: target, action: .install)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        }
                    }
                } else {
                    HStack(spacing: 16) {
                        Label("Root", systemImage: "star.fill").foregroundStyle(.yellow)
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Label("Missing / Required", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("Click or hover over any node to highlight connected dependency paths").font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.04))
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    // MARK: - Cycle-Safe Layered DAG Layout Engine

    private func layoutDAG(in size: CGSize) {
        self.canvasSize = size
        var computedNodes: [DependencyGraphNode] = []
        var computedEdges: [DependencyGraphEdge] = []
        var visited: Set<String> = []

        // Tier buckets: e.g. Tier -1 = Dependents, Tier 0 = Root, Tier 1 = Direct Deps, Tier 2 = Transitive Deps
        var tierMap: [Int: [String]] = [:]

        let rootID = rootPackage.id
        visited.insert(rootID)
        tierMap[0] = [rootID]

        // 1. Upstream Layout (Dependencies)
        if graphMode == .upstream || graphMode == .dual {
            let directDeps = rootPackage.dependencies.filter { !visited.contains($0) }
            for dep in directDeps {
                visited.insert(dep)
                computedEdges.append(DependencyGraphEdge(id: "\(rootID)->\(dep)", fromID: rootID, toID: dep))
            }
            if !directDeps.isEmpty {
                tierMap[1] = directDeps
            }

            var tier2Deps: [String] = []
            for directDep in directDeps {
                if let depPkg = manager.packages.first(where: { $0.id == directDep }) {
                    for subDep in depPkg.dependencies {
                        computedEdges.append(DependencyGraphEdge(id: "\(directDep)->\(subDep)", fromID: directDep, toID: subDep))
                        if !visited.contains(subDep) {
                            visited.insert(subDep)
                            tier2Deps.append(subDep)
                        }
                    }
                }
            }
            if !tier2Deps.isEmpty {
                tierMap[2] = tier2Deps
            }
        }

        // 2. Downstream Layout (Used By Reverse Dependents)
        if graphMode == .downstream || graphMode == .dual {
            let directDependents = manager.packages.filter {
                $0.dependencies.map { $0.lowercased() }.contains(rootID.lowercased()) && !visited.contains($0.id)
            }.map(\.id)

            for dep in directDependents {
                visited.insert(dep)
                computedEdges.append(DependencyGraphEdge(id: "\(dep)->\(rootID)", fromID: dep, toID: rootID))
            }
            if !directDependents.isEmpty {
                let tierKey = (graphMode == .dual) ? -1 : 1
                tierMap[tierKey] = directDependents
            }
        }

        // Compute Grid Coordinates
        let sortedTiers = tierMap.keys.sorted()
        let columnSpacing: CGFloat = 240
        let totalWidth = CGFloat(max(sortedTiers.count - 1, 0)) * columnSpacing
        let startX = (size.width - totalWidth) / 2
        let centerY = size.height / 2

        for (tierIndex, tier) in sortedTiers.enumerated() {
            guard let idsInTier = tierMap[tier] else { continue }
            let x = startX + CGFloat(tierIndex) * columnSpacing
            let rowSpacing: CGFloat = 72
            let totalHeight = CGFloat(max(idsInTier.count - 1, 0)) * rowSpacing
            let startY = centerY - totalHeight / 2

            for (index, id) in idsInTier.enumerated() {
                let y = startY + CGFloat(index) * rowSpacing
                let isRoot = (id == rootID)
                let isInstalled = manager.packages.contains { $0.id == id && $0.isInstalled }
                let kind = manager.packages.first { $0.id == id }?.kind ?? .formula

                let node = DependencyGraphNode(
                    id: id,
                    name: id,
                    kind: kind,
                    isInstalled: isInstalled,
                    isRoot: isRoot,
                    depth: tier,
                    position: CGPoint(x: x, y: y)
                )
                computedNodes.append(node)
            }
        }

        self.nodes = computedNodes
        self.edges = computedEdges
    }
}

private struct EdgeLine: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let midX = (from.x + to.x) / 2
        let control1 = CGPoint(x: midX, y: from.y)
        let control2 = CGPoint(x: midX, y: to.y)
        path.addCurve(to: to, control1: control1, control2: control2)
        return path
    }
}

private struct NodeBubble: View {
    let node: DependencyGraphNode
    let isSelected: Bool
    let isHighlighted: Bool
    let isDimmed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isRoot ? "star.fill" : (node.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 11))
                .foregroundStyle(node.isRoot ? .yellow : (node.isInstalled ? .green : .orange))

            Text(node.name)
                .font(.caption.monospaced().bold())
                .lineLimit(1)

            if node.isInstalled, !node.isRoot {
                Text("Installed")
                    .font(.system(size: 9).bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.5) : (isHighlighted ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1)),
                    radius: isSelected ? 8 : (isHighlighted ? 6 : 3)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    node.isRoot ? Color.yellow : (isSelected ? Color.accentColor : (node.isInstalled ? Color.green.opacity(0.6) : Color.orange.opacity(0.7))),
                    lineWidth: isSelected ? 2.5 : (isHighlighted ? 2 : 1)
                )
        )
        .opacity(isDimmed ? 0.25 : 1.0)
        .scaleEffect(isSelected ? 1.08 : (isHighlighted ? 1.04 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
    }
}
