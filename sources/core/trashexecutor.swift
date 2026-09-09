import Foundation

final class BrewStoreTrashExecutor: @unchecked Sendable {
    private let fileManager: FileManager
    private let validator: BrewStorePathSafetyValidator
    private let moveToTrash: (URL) throws -> Void

    init(fileManager: FileManager = .default, validator: BrewStorePathSafetyValidator, moveToTrash: ((URL) throws -> Void)? = nil) {
        self.fileManager = fileManager
        self.validator = validator
        self.moveToTrash = moveToTrash ?? { url in try fileManager.trashItem(at: url, resultingItemURL: nil) }
    }

    func execute(plan: BrewStoreRemovalPlan, cancellationCheck: (() -> Bool)? = nil) -> BrewStoreRemovalResult {
        var moved: [URL] = []
        var failures: [BrewStoreRemovalFailure] = []
        for candidate in plan.selectedCandidates {
            if cancellationCheck?() == true {
                return .cancelled(manifest: manifest(plan: plan, moved: moved, failures: failures))
            }
            do {
                try validator.validate(candidate.url, fileManager: fileManager)
                try moveToTrash(candidate.url)
                moved.append(candidate.url)
            } catch { failures.append(BrewStoreRemovalFailure(url: candidate.url, reason: error.localizedDescription)) }
        }
        let result = manifest(plan: plan, moved: moved, failures: failures)
        if moved.isEmpty, !failures.isEmpty {
            return .failed(reason: "No selected targets could be moved to the Trash.", manifest: result)
        }
        if failures.isEmpty {
            return .completed(manifest: result)
        }
        return .partiallyCompleted(manifest: result)
    }

    private func manifest(plan: BrewStoreRemovalPlan, moved: [URL], failures: [BrewStoreRemovalFailure]) -> BrewStoreRemovalManifest {
        BrewStoreRemovalManifest(id: UUID(), planID: plan.id, application: plan.application, movedURLs: moved, failures: failures, createdAt: Date())
    }
}
