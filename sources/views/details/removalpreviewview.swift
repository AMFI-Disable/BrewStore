import AppKit
import SwiftUI

struct RemovalPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    let plan: BrewStoreRemovalPlan

    @State private var selectedCandidateIDs: Set<URL> = []
    @State private var isExecuting = false

    init(manager: HomebrewManager, package: BrewStorePackage, plan: BrewStoreRemovalPlan) {
        self.manager = manager
        self.package = package
        self.plan = plan
        _selectedCandidateIDs = State(initialValue: Set(plan.candidates.filter(\.isSelected).map(\.url)))
    }

    private var totalBytes: Int64 {
        plan.candidates.filter { selectedCandidateIDs.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean & Uninstall \(package.name)")
                        .font(.title2.bold())
                    Text("\(selectedCandidateIDs.count) residual items selected · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Divider()

            List(plan.candidates) { candidate in
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { selectedCandidateIDs.contains(candidate.url) },
                        set: { isSelected in
                            if isSelected {
                                selectedCandidateIDs.insert(candidate.url)
                            } else {
                                selectedCandidateIDs.remove(candidate.url)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.url.lastPathComponent).font(.body.bold())
                            Text(candidate.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(candidate.formattedSize)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Button("Select All") {
                    selectedCandidateIDs = Set(plan.candidates.map(\.url))
                }
                Button("Deselect All") {
                    selectedCandidateIDs.removeAll()
                }
                Spacer()

                Button("Move Selected to Trash & Uninstall", role: .destructive) {
                    executeTrashAndUninstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting || manager.isOperating)
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
    }

    private func executeTrashAndUninstall() {
        isExecuting = true
        let selected = plan.candidates.map { candidate in
            var updated = candidate
            updated.isSelected = selectedCandidateIDs.contains(candidate.url)
            return updated
        }
        let subPlan = BrewStoreRemovalPlan(
            id: plan.id,
            application: plan.application,
            createdAt: plan.createdAt,
            candidates: selected
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/Preferences"),
            home.appendingPathComponent("Library/Logs")
        ]
        let executor = BrewStoreTrashExecutor(validator: BrewStorePathSafetyValidator(allowedRoots: roots))
        _ = executor.execute(plan: subPlan)
        isExecuting = false
        dismiss()
        DispatchQueue.main.async {
            BrewStoreUninstallCoordinator.shared.requestUninstall(package: package, manager: manager)
        }
    }
}
