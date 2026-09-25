import AppKit
import Combine
import Foundation

final class BrewStoreCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

enum HomebrewCatalogRefreshError: Error, LocalizedError, Equatable, Sendable {
    case listCasksFailed(reason: String)
    case listFormulaeFailed(reason: String)
    case outdatedFailed(reason: String)
    case caskCatalogFailed(reason: String)
    case formulaCatalogFailed(reason: String)
    case truncatedOutput(command: String)
    case malformedJSON(catalog: String)

    var errorDescription: String? {
        switch self {
        case let .listCasksFailed(reason):
            "Failed to query installed casks: \(reason)"
        case let .listFormulaeFailed(reason):
            "Failed to query installed formulae: \(reason)"
        case let .outdatedFailed(reason):
            "Failed to check outdated packages: \(reason)"
        case let .caskCatalogFailed(reason):
            "Failed to load cask catalog: \(reason)"
        case let .formulaCatalogFailed(reason):
            "Failed to load formula catalog: \(reason)"
        case let .truncatedOutput(command):
            "Homebrew \(command) output exceeded buffer limit or was truncated."
        case let .malformedJSON(catalog):
            "Homebrew \(catalog) catalog returned invalid or malformed JSON."
        }
    }

    var recoverySuggestion: String {
        "Tap Refresh to retry."
    }

    var displayMessage: String {
        "\(errorDescription ?? "Catalog refresh failed.") \(recoverySuggestion)"
    }
}

@MainActor
final class HomebrewManager: ObservableObject {
    @Published var brewPath: String?
    @Published private(set) var brewPrefix: String?
    @Published var packages: [BrewStorePackage] = []
    @Published var services: [BrewStoreService] = []
    @Published var taps: [BrewStoreTap] = []
    @Published private(set) var storageUsage = BrewStoreStorageUsage()
    @Published private(set) var isAnalyticsEnabled: Bool?
    @Published private(set) var isLoading = false
    @Published private(set) var isBackgroundSyncing = false
    @Published private(set) var isOperating = false
    @Published private(set) var isBootstrapping = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var catalogRefreshError: HomebrewCatalogRefreshError?
    @Published var lastOperationRequiresElevation = false
    @Published var activeLockMessage: String?
    @Published var activeLockState: HomebrewLockState = .free
    @Published var isHomebrewLocked = false
    @Published var outputLog = ""
    private static let maxLogCharacters = 150_000

    func appendLogChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        outputLog.append(chunk)
        if outputLog.count > Self.maxLogCharacters {
            let overflow = outputLog.count - Self.maxLogCharacters
            outputLog = String(outputLog.dropFirst(overflow))
        }
    }

    @Published private(set) var operationHistory: [BrewStoreOperationRecord] = [] {
        didSet { saveOperationHistory() }
    }

    private let executor: BrewStoreCommandExecutor
    private let operationHistoryKey = "BrewStore.operationHistory"

    @Published private(set) var activeOperationTitle: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var updateSessionStartTime: Date?
    @Published private(set) var updateSessionInitialCount: Int = 0
    private var isCancelled = false
    private let cancellationState = BrewStoreCancellationState()
    private var refreshGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTimerTask: Task<Void, Never>?
    private var directoryWatcher: BrewStoreDirectoryWatcher?
    private var cancellables = Set<AnyCancellable>()

    init(executor: BrewStoreCommandExecutor = .shared) {
        self.executor = executor
        if let data = UserDefaults.standard.data(forKey: operationHistoryKey),
           let records = try? JSONDecoder().decode([BrewStoreOperationRecord].self, from: data) {
            operationHistory = Array(records.prefix(50))
        }
        if !executor.hasCustomHandler {
            if let cached = BrewStoreFastCacheEngine.loadCacheSynchronously() {
                var localPackages = cached.packages
                self.taps = cached.taps
                self.services = cached.services
                detectHomebrew()

                // Instant local filesystem reconciliation using CellarScanner (<5ms startup)
                if let prefix = brewPrefix {
                    let (formulae, casks) = CellarScanner.scanAllInstalled(prefix: prefix)
                    let authCasks = CellarScanner.toAuthoritativeMap(casks)
                    let authFormulae = CellarScanner.toAuthoritativeMap(formulae)
                    for i in 0 ..< localPackages.count {
                        let id = localPackages[i].id.lowercased()
                        if localPackages[i].kind == .cask, let ver = authCasks[id] {
                            localPackages[i].isInstalled = true
                            localPackages[i].installedVersion = ver
                        } else if localPackages[i].kind == .formula, let ver = authFormulae[id] {
                            localPackages[i].isInstalled = true
                            localPackages[i].installedVersion = ver
                        }
                    }
                }
                self.packages = localPackages
            } else {
                detectHomebrew()
            }
        } else {
            detectHomebrew()
        }

        setupAutoRefresh()
    }

    func setupAutoRefresh() {
        restartAutoRefreshTimer()
        setupDirectoryWatcher()

        NotificationCenter.default.publisher(for: .brewStoreAutoRefreshPreferencesDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartAutoRefreshTimer()
                self?.setupDirectoryWatcher()
            }
            .store(in: &cancellables)
    }

    @Published private(set) var consecutiveRefreshFailures = 0

    func restartAutoRefreshTimer() {
        autoRefreshTimerTask?.cancel()
        guard BrewStorePreferences.shared.isAutoRefreshEnabled else { return }

        let baseInterval = max(15, BrewStorePreferences.shared.autoRefreshIntervalSeconds)
        autoRefreshTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                let failures = await MainActor.run { self?.consecutiveRefreshFailures ?? 0 }
                let backoffMultiplier = min(4, 1 + failures)
                let interval = UInt64(baseInterval * backoffMultiplier)

                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if !self.isLoading, !self.isOperating {
                        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                        if !isTesting, !NSApp.isActive {
                            if let last = self.lastRefreshedAt, Date().timeIntervalSince(last) < 300 {
                                return
                            }
                        }
                        self.refresh()
                    }
                }
            }
        }
    }

    func setupDirectoryWatcher() {
        directoryWatcher?.stop()
        directoryWatcher = nil
        CellarFileSystemSentry.shared.stopMonitoring()

        guard BrewStorePreferences.shared.autoRefreshOnExternalBrewCommands, let prefix = brewPrefix else { return }

        let cellar = (prefix as NSString).appendingPathComponent("Cellar")
        let caskroom = (prefix as NSString).appendingPathComponent("Caskroom")

        directoryWatcher = BrewStoreDirectoryWatcher(paths: [cellar, caskroom]) { [weak self] in
            guard let self else { return }
            if !self.isLoading, !self.isOperating {
                self.refresh()
            }
        }

        CellarFileSystemSentry.shared.onDriftDetected = { [weak self] _ in
            guard let self else { return }
            if !self.isLoading, !self.isOperating {
                self.refresh()
            }
        }
        CellarFileSystemSentry.shared.startMonitoring()
    }

    var isAvailable: Bool {
        brewPath != nil
    }

    func clearOperationHistory() {
        operationHistory = []
    }

    func resetState() {
        clearOperationHistory()
        outputLog = ""
        errorMessage = nil
        statusMessage = "Ready"
        isOperating = false
        activeOperationTitle = nil
        updateSessionStartTime = nil
        updateSessionInitialCount = 0
    }

    func cancelCurrentOperation() {
        isCancelled = true
        cancellationState.cancel()
        updateSessionStartTime = nil
        updateSessionInitialCount = 0
        statusMessage = "Cancelling operation…"
    }

    nonisolated static func detectBrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".linuxbrew/bin/brew").path
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated static func detectBrewPrefix() -> String? {
        guard let path = detectBrewPath() else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
    }

    func detectHomebrew() {
        brewPath = Self.detectBrewPath()
        if let path = brewPath {
            brewPrefix = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
        } else {
            brewPrefix = nil
        }
    }

    func setActiveBrewPath(_ path: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        brewPath = path
        brewPrefix = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
        refresh()
    }

    func refresh() {
        refresh(force: false)
    }

    func retryRefresh() {
        refresh(force: true)
    }

    func clearCacheAndRefresh() {
        guard !isLoading, !isOperating else { return }
        BrewStoreFastCacheEngine.clearCache()
        refresh(force: true)
    }

    func refresh(force: Bool) {
        guard !isLoading, !isOperating else { return }

        detectHomebrew()
        guard let brewPath else {
            errorMessage = nil
            catalogRefreshError = nil
            statusMessage = "Homebrew is not installed."
            return
        }

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let isInitialColdStart = packages.isEmpty
        isLoading = true
        isBackgroundSyncing = !isInitialColdStart
        errorMessage = nil
        catalogRefreshError = nil
        statusMessage = isInitialColdStart ? "Refreshing Homebrew data…" : "Syncing Homebrew data in background…"

        refreshTask = Task.detached(priority: .userInitiated) { [self, executor, brewPath, brewPrefix = self.brewPrefix] in
            let isCacheFresh = await MainActor.run {
                !force && !executor.hasCustomHandler && BrewStoreFastCacheEngine.isCatalogCacheFresh(prefix: brewPrefix) && !self.packages.isEmpty
            }

            let catalogOutputLimit = 40_000_000

            let listCaskResult: BrewStoreCommandResult
            let listFormulaResult: BrewStoreCommandResult
            let pinnedResult: BrewStoreCommandResult
            let outdatedResult: BrewStoreCommandResult
            let casks: BrewStoreCommandResult
            let formulae: BrewStoreCommandResult
            let serviceResult: BrewStoreCommandResult
            let tapResult: BrewStoreCommandResult

            if executor.hasCustomHandler {
                listCaskResult = executor.run(executablePath: brewPath, arguments: ["list", "--cask", "--versions"], timeout: 10)
                listFormulaResult = executor.run(executablePath: brewPath, arguments: ["list", "--formula", "--versions"], timeout: 10)
                pinnedResult = executor.run(executablePath: brewPath, arguments: ["list", "--pinned"], timeout: 10)
                outdatedResult = executor.run(executablePath: brewPath, arguments: ["outdated", "--json=v2"], timeout: 15)

                if isCacheFresh {
                    casks = BrewStoreCommandResult(
                        standardOutput: "",
                        standardError: "",
                        terminationStatus: 0,
                        wasTerminated: false,
                        didTimeOut: false,
                        wasCancelled: false,
                        standardOutputWasTruncated: false,
                        standardErrorWasTruncated: false,
                        category: .readOnly,
                        launchErrorDescription: nil
                    )
                    formulae = casks
                } else {
                    casks = executor.run(
                        executablePath: brewPath,
                        arguments: ["info", "--json=v2", "--cask"],
                        timeout: 15,
                        maximumOutputBytes: catalogOutputLimit
                    )
                    formulae = executor.run(
                        executablePath: brewPath,
                        arguments: ["info", "--json=v2", "--formula"],
                        timeout: 15,
                        maximumOutputBytes: catalogOutputLimit
                    )
                }

                serviceResult = executor.run(executablePath: brewPath, arguments: ["services", "list", "--json"], timeout: 10)
                tapResult = executor.run(executablePath: brewPath, arguments: ["tap"], timeout: 10)
            } else {
                async let listCaskTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["list", "--cask", "--versions"], timeout: 10)
                }.value
                async let listFormulaTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["list", "--formula", "--versions"], timeout: 10)
                }.value
                async let pinnedTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["list", "--pinned"], timeout: 10)
                }.value
                async let outdatedTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["outdated", "--json=v2"], timeout: 15)
                }.value
                async let serviceTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["services", "list", "--json"], timeout: 10)
                }.value
                async let tapTask = Task.detached {
                    executor.run(executablePath: brewPath, arguments: ["tap"], timeout: 10)
                }.value

                async let casksTask = Task.detached { () -> BrewStoreCommandResult in
                    if isCacheFresh {
                        BrewStoreCommandResult(
                            standardOutput: "",
                            standardError: "",
                            terminationStatus: 0,
                            wasTerminated: false,
                            didTimeOut: false,
                            wasCancelled: false,
                            standardOutputWasTruncated: false,
                            standardErrorWasTruncated: false,
                            category: .readOnly,
                            launchErrorDescription: nil
                        )
                    } else {
                        executor.run(
                            executablePath: brewPath,
                            arguments: ["info", "--json=v2", "--cask"],
                            timeout: 15,
                            maximumOutputBytes: catalogOutputLimit
                        )
                    }
                }.value

                async let formulaeTask = Task.detached { () -> BrewStoreCommandResult in
                    if isCacheFresh {
                        BrewStoreCommandResult(
                            standardOutput: "",
                            standardError: "",
                            terminationStatus: 0,
                            wasTerminated: false,
                            didTimeOut: false,
                            wasCancelled: false,
                            standardOutputWasTruncated: false,
                            standardErrorWasTruncated: false,
                            category: .readOnly,
                            launchErrorDescription: nil
                        )
                    } else {
                        executor.run(
                            executablePath: brewPath,
                            arguments: ["info", "--json=v2", "--formula"],
                            timeout: 15,
                            maximumOutputBytes: catalogOutputLimit
                        )
                    }
                }.value

                listCaskResult = await listCaskTask
                listFormulaResult = await listFormulaTask
                pinnedResult = await pinnedTask
                outdatedResult = await outdatedTask
                casks = await casksTask
                formulae = await formulaeTask
                serviceResult = await serviceTask
                tapResult = await tapTask
            }

            // Validate list commands (authoritative sources)
            if listCaskResult.standardOutputWasTruncated {
                let err = HomebrewCatalogRefreshError.truncatedOutput(command: "installed casks")
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }
            if !listCaskResult.succeeded {
                let reason = listCaskResult.didTimeOut ? "Command timed out." : (listCaskResult.standardError.isEmpty ? "Process failed with exit code \(listCaskResult.terminationStatus ?? -1)." : listCaskResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                let err = HomebrewCatalogRefreshError.listCasksFailed(reason: reason)
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }

            if listFormulaResult.standardOutputWasTruncated {
                let err = HomebrewCatalogRefreshError.truncatedOutput(command: "installed formulae")
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }
            if !listFormulaResult.succeeded {
                let reason = listFormulaResult.didTimeOut ? "Command timed out." : (listFormulaResult.standardError.isEmpty ? "Process failed with exit code \(listFormulaResult.terminationStatus ?? -1)." : listFormulaResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                let err = HomebrewCatalogRefreshError.listFormulaeFailed(reason: reason)
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }

            // Validate outdated command
            if outdatedResult.standardOutputWasTruncated {
                let err = HomebrewCatalogRefreshError.truncatedOutput(command: "outdated packages")
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }
            if !outdatedResult.succeeded {
                let reason = outdatedResult.didTimeOut ? "Command timed out." : (outdatedResult.standardError.isEmpty ? "Process failed with exit code \(outdatedResult.terminationStatus ?? -1)." : outdatedResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                let err = HomebrewCatalogRefreshError.outdatedFailed(reason: reason)
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(err, generation: generation)
                }
                return
            }

            // Validate catalog results
            if !isCacheFresh {
                if casks.standardOutputWasTruncated {
                    let err = HomebrewCatalogRefreshError.truncatedOutput(command: "cask catalog")
                    await MainActor.run { [weak self] in
                        self?.handleRefreshFailure(err, generation: generation)
                    }
                    return
                }
                if !casks.succeeded {
                    let reason = casks.didTimeOut ? "Command timed out." : (casks.standardError.isEmpty ? "Process failed with exit code \(casks.terminationStatus ?? -1)." : casks.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                    let err = HomebrewCatalogRefreshError.caskCatalogFailed(reason: reason)
                    await MainActor.run { [weak self] in
                        self?.handleRefreshFailure(err, generation: generation)
                    }
                    return
                }
                let caskData = Data(casks.standardOutput.utf8)
                if !casks.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if (try? JSONSerialization.jsonObject(with: caskData)) == nil {
                        let err = HomebrewCatalogRefreshError.malformedJSON(catalog: "cask")
                        await MainActor.run { [weak self] in
                            self?.handleRefreshFailure(err, generation: generation)
                        }
                        return
                    }
                }

                if formulae.standardOutputWasTruncated {
                    let err = HomebrewCatalogRefreshError.truncatedOutput(command: "formula catalog")
                    await MainActor.run { [weak self] in
                        self?.handleRefreshFailure(err, generation: generation)
                    }
                    return
                }
                if !formulae.succeeded {
                    let reason = formulae.didTimeOut ? "Command timed out." : (formulae.standardError.isEmpty ? "Process failed with exit code \(formulae.terminationStatus ?? -1)." : formulae.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                    let err = HomebrewCatalogRefreshError.formulaCatalogFailed(reason: reason)
                    await MainActor.run { [weak self] in
                        self?.handleRefreshFailure(err, generation: generation)
                    }
                    return
                }
                let formulaData = Data(formulae.standardOutput.utf8)
                if !formulae.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if (try? JSONSerialization.jsonObject(with: formulaData)) == nil {
                        let err = HomebrewCatalogRefreshError.malformedJSON(catalog: "formula")
                        await MainActor.run { [weak self] in
                            self?.handleRefreshFailure(err, generation: generation)
                        }
                        return
                    }
                }
            }

            // Parse authoritative installed records
            let authoritativeCasks = Self.parseAuthoritativeInstalled(listCaskResult.standardOutput)
            let authoritativeFormulae = Self.parseAuthoritativeInstalled(listFormulaResult.standardOutput)
            let installedCaskIDs = Set(authoritativeCasks.keys)
            let installedFormulaIDs = Set(authoritativeFormulae.keys)
            let pinnedFormulae = HomebrewJSONParser.pinnedIdentifiers(from: pinnedResult.standardOutput)
            let outdatedData = Data(outdatedResult.standardOutput.utf8)
            let caskOutdated = HomebrewJSONParser.identifiers(fromOutdated: outdatedData, kind: .cask)
            let formulaOutdated = HomebrewJSONParser.identifiers(fromOutdated: outdatedData, kind: .formula)

            var parsedCasks: [BrewStorePackage]
            var parsedFormulae: [BrewStorePackage]

            if isCacheFresh {
                let existing = await MainActor.run { self.packages }
                parsedCasks = existing.filter { $0.kind == .cask }
                parsedFormulae = existing.filter { $0.kind == .formula }
            } else {
                let caskData = Data(casks.standardOutput.utf8)
                let formulaData = Data(formulae.standardOutput.utf8)
                parsedCasks = HomebrewJSONParser.packages(from: caskData, kind: .cask, installedIDs: installedCaskIDs, outdatedIDs: caskOutdated)
                parsedFormulae = HomebrewJSONParser.packages(from: formulaData, kind: .formula, installedIDs: installedFormulaIDs, outdatedIDs: formulaOutdated, pinnedIDs: pinnedFormulae)
            }

            // Reconcile outdated flags
            for i in 0 ..< parsedCasks.count {
                parsedCasks[i].isOutdated = caskOutdated.contains(parsedCasks[i].id.lowercased())
            }
            for i in 0 ..< parsedFormulae.count {
                parsedFormulae[i].isOutdated = formulaOutdated.contains(parsedFormulae[i].id.lowercased())
                parsedFormulae[i].isPinned = pinnedFormulae.contains(parsedFormulae[i].id.lowercased())
            }

            // Reconcile and set authoritative versions
            for i in 0 ..< parsedCasks.count {
                let id = parsedCasks[i].id.lowercased()
                let baseID = id.components(separatedBy: "/").last ?? id
                if let version = authoritativeCasks[id] ?? authoritativeCasks[baseID] {
                    parsedCasks[i].isInstalled = true
                    parsedCasks[i].installedVersion = version
                } else {
                    parsedCasks[i].isInstalled = false
                }
            }

            for i in 0 ..< parsedFormulae.count {
                let id = parsedFormulae[i].id.lowercased()
                let baseID = id.components(separatedBy: "/").last ?? id
                if let version = authoritativeFormulae[id] ?? authoritativeFormulae[baseID] {
                    parsedFormulae[i].isInstalled = true
                    parsedFormulae[i].installedVersion = version
                } else {
                    parsedFormulae[i].isInstalled = false
                }
            }

            // Synthesize fallback records for any authoritative installed package omitted by JSON API
            let parsedCaskIDSet = Set(parsedCasks.flatMap { [$0.id.lowercased(), $0.id.lowercased().components(separatedBy: "/").last ?? ""] })
            for (id, version) in authoritativeCasks where !parsedCaskIDSet.contains(id) {
                parsedCasks.append(BrewStorePackage(
                    id: id,
                    name: id,
                    description: "",
                    homepage: "",
                    version: version,
                    kind: .cask,
                    isInstalled: true,
                    isOutdated: caskOutdated.contains(id),
                    installedVersion: version
                ))
            }

            let parsedFormulaIDSet = Set(parsedFormulae.flatMap { [$0.id.lowercased(), $0.id.lowercased().components(separatedBy: "/").last ?? ""] })
            for (id, version) in authoritativeFormulae where !parsedFormulaIDSet.contains(id) {
                parsedFormulae.append(BrewStorePackage(
                    id: id,
                    name: id,
                    description: "",
                    homepage: "",
                    version: version,
                    kind: .formula,
                    isInstalled: true,
                    isOutdated: formulaOutdated.contains(id),
                    isPinned: pinnedFormulae.contains(id),
                    installedVersion: version
                ))
            }

            // Deduplicate across (id, kind)
            var seenKeys = Set<String>()
            var uniquePackages: [BrewStorePackage] = []
            for pkg in parsedCasks + parsedFormulae {
                let key = "\(pkg.kind.rawValue):\(pkg.id.lowercased())"
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    uniquePackages.append(pkg)
                }
            }

            let finalPackages = uniquePackages
            let totalInstalled = finalPackages.filter(\.isInstalled).count
            let totalOutdated = finalPackages.filter(\.isOutdated).count

            await MainActor.run { [weak self, finalPackages] in
                guard let self else { return }
                guard self.refreshGeneration == generation else { return }
                self.refreshTask = nil
                self.isLoading = false
                self.isBackgroundSyncing = false
                self.consecutiveRefreshFailures = 0
                self.catalogRefreshError = nil
                self.errorMessage = nil
                self.packages = finalPackages
                self.services = HomebrewJSONParser.services(from: Data(serviceResult.standardOutput.utf8))
                self.taps = HomebrewJSONParser.taps(from: tapResult.standardOutput)
                self.lastRefreshedAt = Date()
                if totalOutdated > 0 {
                    self.statusMessage = "Synced \(totalInstalled) installed packages (\(totalOutdated) updates available)."
                } else {
                    self.statusMessage = "All \(totalInstalled) packages are up to date."
                }
                BrewStoreFastCacheEngine.saveCache(packages: self.packages, taps: self.taps, services: self.services)
                BrewStorePackagePinningManager.shared.reconcileWithHomebrew(manager: self)
                BrewStoreDotfilesAutoSyncManager.shared.onPackageOperationCompleted(manager: self)
                BrewStoreSpotlightIndexer.shared.indexInstalledPackages(self.packages)
            }
        }
    }

    private func handleRefreshFailure(_ error: HomebrewCatalogRefreshError, generation: UInt64) {
        guard refreshGeneration == generation else { return }
        refreshTask = nil
        self.isLoading = false
        self.isBackgroundSyncing = false
        self.consecutiveRefreshFailures += 1
        self.catalogRefreshError = error
        self.errorMessage = error.displayMessage
        self.statusMessage = "Refresh failed (tap to retry)."
    }

    func perform(package: BrewStorePackage, action: PackageAction, completion: ((Bool) -> Void)? = nil) {
        guard let brewPath, !isOperating else {
            completion?(false)
            return
        }
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = "\(action.title) \(package.name)"
        errorMessage = nil
        outputLog = ""
        statusMessage = "Running \(action.title.lowercased()) for \(package.name)…"

        if action == .upgrade {
            updateSessionStartTime = Date()
            updateSessionInitialCount = 1
        }

        if action == .uninstall, BrewStorePreferences.shared.enableAutoSnapshotBeforeMutations {
            BrewStoreSnapshotManager().createSnapshot(name: "Pre-uninstall \(package.name)", manager: self)
        }

        let arguments = action.arguments(for: package)
        let isDestructive = (action == .uninstall)

        Task.detached(priority: .userInitiated) { [self, executor, brewPath, brewPrefix = self.brewPrefix, arguments, action, packageName = package.name, packageID = package.id, cancellationState] in
            // 1. Proactive Lock Coordination
            if let prefix = brewPrefix, !BrewStoreFixtureMode.isEnabled {
                let lockState = BrewStoreLockManager.shared.checkLockState(prefix: prefix, targetPackage: packageID)
                if case let .locked(lockFile, pid, _) = lockState {
                    await MainActor.run {
                        self.activeLockState = lockState
                        self.isHomebrewLocked = true
                        self.activeLockMessage = "Waiting for Homebrew process (PID \(pid.map(String.init) ?? "active")) to release \(lockFile)…"
                        self.statusMessage = "Waiting for Homebrew lock to be released…"
                    }
                    let freed = await BrewStoreLockManager.shared.waitForLockRelease(
                        prefix: prefix,
                        targetPackage: packageID,
                        timeout: 15,
                        cancellationCheck: { cancellationState.isCancelled }
                    )
                    await MainActor.run {
                        self.activeLockMessage = nil
                    }
                    if !freed, !cancellationState.isCancelled {
                        await MainActor.run {
                            self.isOperating = false
                            self.activeOperationTitle = nil
                            self.activeLockState = lockState
                            self.isHomebrewLocked = true
                            self.errorMessage = "Operation blocked: Homebrew is locked by \(lockFile). Click 'Clear Locks' to resolve."
                            self.statusMessage = "Operation blocked by lock."
                            self.recordOperation(title: "\(action.title) \(packageName)", succeeded: false, detail: self.errorMessage ?? "")
                            completion?(false)
                        }
                        return
                    } else {
                        await MainActor.run {
                            self.isHomebrewLocked = false
                            self.activeLockState = .free
                        }
                    }
                }
            }

            let result = executor.run(
                executablePath: brewPath,
                arguments: arguments,
                timeout: 900,
                category: isDestructive ? .destructiveMutation : .reversibleMutation,
                maximumOutputBytes: 2_000_000,
                cancellationCheck: { cancellationState.isCancelled },
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.appendLogChunk(chunk)
                    }
                }
            )

            let isPrivError = !result.succeeded && BrewStorePrivilegeElevationManager.shared.isPrivilegeError(
                errorMessage: result.standardError,
                outputLog: result.standardOutput
            )

            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.updateSessionStartTime = nil
                self.updateSessionInitialCount = 0
                self.lastOperationRequiresElevation = isPrivError

                if result.succeeded {
                    self.statusMessage = "Completed \(action.title.lowercased()) for \(packageName)."
                    self.recordOperation(title: "\(action.title) \(packageName)", succeeded: true, detail: self.outputLog.isEmpty ? result.standardOutput : self.outputLog)
                    BrewStoreNotificationManager.shared.notifyOperationCompleted(action: action.title, packageName: packageName, success: true)
                    self.refresh()
                } else {
                    var failureDetail = self.failureMessage(for: result)
                    if isPrivError {
                        failureDetail += "\nAdministrator privileges required. You can retry with elevated authorization."
                    }
                    self.errorMessage = failureDetail
                    self.statusMessage = "Operation failed."
                    self.recordOperation(title: "\(action.title) \(packageName)", succeeded: false, detail: self.errorMessage ?? "")
                }
                completion?(result.succeeded)
            }
        }
    }

    func performElevated(package: BrewStorePackage, action: PackageAction, completion: ((Bool) -> Void)? = nil) {
        guard let brewPath, !isOperating else {
            completion?(false)
            return
        }
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = "\(action.title) (Elevated) \(package.name)"
        errorMessage = nil
        outputLog = ""
        lastOperationRequiresElevation = false
        statusMessage = "Authenticating administrator privileges for \(package.name)…"

        let arguments = action.arguments(for: package)
        let packageName = package.name

        Task.detached(priority: .userInitiated) { [self, brewPath, arguments, action, packageName] in
            let res = BrewStorePrivilegeElevationManager.shared.runElevated(brewPath: brewPath, arguments: arguments)
            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.outputLog = res.output
                if res.succeeded {
                    self.statusMessage = "Completed \(action.title.lowercased()) for \(packageName) with elevated privileges."
                    self.recordOperation(title: "\(action.title) (Elevated) \(packageName)", succeeded: true, detail: res.output)
                    self.refresh()
                } else {
                    self.errorMessage = res.error ?? "Administrator authorization cancelled."
                    self.statusMessage = "Elevated operation failed."
                    self.recordOperation(title: "\(action.title) (Elevated) \(packageName)", succeeded: false, detail: self.errorMessage ?? "")
                }
                completion?(res.succeeded)
            }
        }
    }

    // MARK: - Automated Homebrew Lock Management & Auto-Fixes

    /// Scans the locks directory and updates published lock state.
    func refreshLockState() {
        guard let prefix = brewPrefix else { return }
        let state = BrewStoreLockManager.shared.checkLockState(prefix: prefix)
        let hasLocks = BrewStoreLockManager.shared.hasActiveOrStaleLocks(prefix: prefix)
        self.activeLockState = state
        self.isHomebrewLocked = (state != .free) || hasLocks
    }

    /// Auto-fix: Safely clears active or stale lock files and terminates hanging brew processes.
    @discardableResult
    func clearLocks(terminateProcesses: Bool = true) -> (removedFiles: [String], terminatedPIDs: [Int32]) {
        guard let prefix = brewPrefix else { return ([], []) }
        let result = BrewStoreLockManager.shared.forceUnlock(prefix: prefix, terminateHoldingProcesses: terminateProcesses)
        self.activeLockMessage = nil
        self.activeLockState = .free
        self.isHomebrewLocked = false

        if errorMessage?.contains("lock") == true || errorMessage?.contains("Lock") == true {
            self.errorMessage = nil
        }

        let filesCount = result.removedFiles.count
        let pidsCount = result.terminatedPIDs.count
        if filesCount > 0 || pidsCount > 0 {
            var msg = "Removed \(filesCount) Homebrew lock file\(filesCount == 1 ? "" : "s")"
            if pidsCount > 0 {
                msg += " and terminated \(pidsCount) hanging brew process\(pidsCount == 1 ? "" : "es")"
            }
            self.statusMessage = "\(msg). Homebrew locks cleared successfully."
            self.recordOperation(title: "Clear Homebrew Locks", succeeded: true, detail: msg)
        } else {
            self.statusMessage = "Homebrew locks directory is clean."
        }

        return result
    }

    func setPackagePinned(packageID: String, isPinned: Bool) {
        let lower = packageID.lowercased()
        if let idx = packages.firstIndex(where: { $0.id.lowercased() == lower }) {
            packages[idx].isPinned = isPinned
        }
    }

    func pin(package: BrewStorePackage) {
        guard package.kind == .formula else { return }
        BrewStorePackagePinningManager.shared.pin(packageID: package.id, kind: package.kind, manager: self)
    }

    func unpin(package: BrewStorePackage) {
        guard package.kind == .formula else { return }
        BrewStorePackagePinningManager.shared.unpin(packageID: package.id, kind: package.kind, manager: self)
    }

    func link(package: BrewStorePackage) {
        guard package.kind == .formula else { return }
        runPackageControlCommand(title: "Link \(package.name)", arguments: ["link", "--overwrite", package.id])
    }

    func unlink(package: BrewStorePackage) {
        guard package.kind == .formula else { return }
        runPackageControlCommand(title: "Unlink \(package.name)", arguments: ["unlink", package.id])
    }

    private func runPackageControlCommand(title: String, arguments: [String]) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = title
        statusMessage = "Running \(title)…"
        errorMessage = nil
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments, title, cancellationState] in
            let result = executor.run(
                executablePath: brewPath,
                arguments: arguments,
                timeout: 60,
                category: .reversibleMutation,
                cancellationCheck: { cancellationState.isCancelled }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.activeOperationTitle = nil
                self.errorMessage = result.succeeded ? nil : self.failureMessage(for: result)
                self.statusMessage = result.succeeded ? "\(title) completed." : "\(title) failed."
                self.recordOperation(title: title, succeeded: result.succeeded, detail: result.succeeded ? result.standardOutput : (self.errorMessage ?? ""))
                BrewStoreNotificationManager.shared.notifyOperationCompleted(action: "Command", packageName: title, success: result.succeeded)
                if result.succeeded {
                    self.refresh()
                }
            }
        }
    }

    func batchPerform(packages: [BrewStorePackage], action: PackageAction, completion: (([String: Bool]) -> Void)? = nil) {
        guard let brewPath, !isOperating, !packages.isEmpty else {
            completion?([:])
            return
        }
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = "\(action.title) \(packages.count) packages"
        errorMessage = nil
        outputLog = ""

        Task.detached(priority: .userInitiated) { [self, executor, brewPath, packages, action, cancellationState] in
            var results: [String: Bool] = [:]
            for package in packages {
                if cancellationState.isCancelled {
                    break
                }
                let completedCount = results.count + 1
                await MainActor.run { [weak self] in
                    self?.statusMessage = "\(action.title) (\(completedCount)/\(packages.count)): \(package.name)…"
                }
                let arguments = action.arguments(for: package)
                let result = executor.run(
                    executablePath: brewPath,
                    arguments: arguments,
                    timeout: 900,
                    category: action == .uninstall ? .destructiveMutation : .reversibleMutation,
                    cancellationCheck: { cancellationState.isCancelled },
                    onOutput: { [weak self] chunk in
                        Task { @MainActor [weak self] in self?.appendLogChunk(chunk) }
                    }
                )
                results[package.id] = result.succeeded
                await MainActor.run {
                    self.recordOperation(title: "\(action.title) \(package.name)", succeeded: result.succeeded, detail: result.standardOutput)
                }
                if cancellationState.isCancelled {
                    break
                }
            }

            let finalResults = results
            let succeededCount = finalResults.values.filter { $0 }.count
            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = "\(action.title) completed for \(succeededCount) of \(packages.count) packages."
                self.refresh()
                completion?(finalResults)
            }
        }
    }

    func perform(service: BrewStoreService, action: ServiceAction) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        isCancelled = false
        let title = "\(action.rawValue.capitalized) service \(service.name)"
        activeOperationTitle = title
        let arguments = ["services", action.rawValue, service.name]
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments, title] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 120, category: .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = result.succeeded ? "Service operation completed." : "Service operation failed."
                self.errorMessage = result.succeeded ? nil : self.failureMessage(for: result)
                self.recordOperation(title: title, succeeded: result.succeeded, detail: result.succeeded ? result.standardOutput : (self.errorMessage ?? ""))
                if result.succeeded {
                    self.refresh()
                }
            }
        }
    }

    func batchPerform(services: [BrewStoreService], action: ServiceAction) {
        guard let brewPath, !isOperating, !services.isEmpty else { return }
        isOperating = true
        isCancelled = false
        let title = "\(action.rawValue.capitalized) \(services.count) services"
        activeOperationTitle = title
        statusMessage = "Starting batch service operation…"
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [executor, brewPath, services, action, title] in
            var allSucceeded = true
            var outputLogs: [String] = []
            for (index, service) in services.enumerated() {
                await MainActor.run { [weak self] in
                    self?.statusMessage = "\(action.rawValue.capitalized) service (\(index + 1)/\(services.count)): \(service.name)…"
                }
                let arguments = ["services", action.rawValue, service.name]
                let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 60, category: .reversibleMutation)
                if !result.succeeded {
                    allSucceeded = false
                }
                if !result.standardOutput.isEmpty {
                    outputLogs.append("[\(service.name)] \(result.standardOutput)")
                }
                if !result.standardError.isEmpty {
                    outputLogs.append("[\(service.name) err] \(result.standardError)")
                }
            }
            let finalSucceeded = allSucceeded
            let finalLogs = outputLogs
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = finalSucceeded ? "All service operations completed." : "Some service operations failed."
                self.recordOperation(title: title, succeeded: finalSucceeded, detail: finalLogs.joined(separator: "\n"))
                self.refresh()
            }
        }
    }

    func addTap(_ name: String, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        runTapCommand(["tap", name], completion: completion)
    }

    func tap(name: String, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        addTap(name, completion: completion)
    }

    func removeTap(_ tap: BrewStoreTap, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        runTapCommand(["untap", tap.name], completion: completion)
    }

    func untap(name: String, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        runTapCommand(["untap", name], completion: completion)
    }

    func bootstrapHomebrew() {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        activeOperationTitle = "Install Homebrew"
        statusMessage = "Running the official Homebrew installer…"
        errorMessage = nil
        outputLog = ""

        let script = "NONINTERACTIVE=1 /bin/bash -c \"$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        Task.detached(priority: .userInitiated) { [self, executor] in
            let result = executor.run(
                executablePath: "/bin/bash",
                arguments: ["-c", script],
                timeout: 1_800,
                category: .privilegedOrUnsupported,
                maximumOutputBytes: 2_000_000,
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in self?.appendLogChunk(chunk) }
                }
            )
            await MainActor.run {
                self.isBootstrapping = false
                self.activeOperationTitle = nil
                if result.succeeded {
                    self.detectHomebrew()
                    self.statusMessage = self.isAvailable ? "Homebrew is ready." : "Installation finished. Restart BrewStore if Homebrew is not detected yet."
                    self.recordOperation(title: "Install Homebrew", succeeded: true, detail: self.outputLog)
                } else {
                    self.errorMessage = self.failureMessage(for: result, fallback: "Homebrew installation did not complete.")
                    self.statusMessage = "Homebrew installation failed."
                    self.recordOperation(title: "Install Homebrew", succeeded: false, detail: self.errorMessage ?? "")
                }
            }
        }
    }

    func updateHomebrew() {
        runMaintenance(
            title: "Update Homebrew metadata",
            arguments: ["update"],
            category: .reversibleMutation,
            refreshAfterSuccess: true
        )
    }

    func upgradeAllPackages() {
        let count = packages.filter(\.isOutdated).count
        updateSessionStartTime = Date()
        updateSessionInitialCount = max(1, count)
        runMaintenance(
            title: "Upgrade all packages",
            arguments: ["upgrade"],
            category: .reversibleMutation,
            refreshAfterSuccess: true
        )
    }

    func runDoctor() {
        runMaintenance(
            title: "Run Homebrew Doctor",
            arguments: ["doctor"],
            category: .readOnly,
            refreshAfterSuccess: false
        )
    }

    func applyDoctorFixes(diagnostics: [BrewStoreDoctorDiagnostic]) {
        guard let brewPath, !isOperating else { return }
        let fixable = diagnostics.filter { $0.isAutoFixable && $0.autoFixCommand != nil }
        guard !fixable.isEmpty else { return }

        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = "Repairing \(fixable.count) Homebrew issue\(fixable.count == 1 ? "" : "s")"
        statusMessage = "Applying repairs…"
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [executor, brewPath, fixable, cancellationState] in
            var successCount = 0
            for item in fixable {
                if cancellationState.isCancelled {
                    break
                }
                guard let cmd = item.autoFixCommand else { continue }
                // Parse command arguments from "brew <arg1> <arg2>..."
                let parts = cmd.split(separator: " ").map(String.init)
                guard parts.first == "brew" else { continue }
                let args = Array(parts.dropFirst())

                let result = executor.run(
                    executablePath: brewPath,
                    arguments: args,
                    timeout: 120,
                    category: .reversibleMutation,
                    cancellationCheck: { cancellationState.isCancelled }
                )
                if result.succeeded {
                    successCount += 1
                }
                if cancellationState.isCancelled {
                    break
                }
            }

            let repairedCount = successCount
            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = "Repaired \(repairedCount) of \(fixable.count) issue\(fixable.count == 1 ? "" : "s")."
                self.recordOperation(title: "Doctor Auto-Repair", succeeded: repairedCount > 0, detail: self.statusMessage)
                self.runDoctor()
                self.refresh()
            }
        }
    }

    func cleanup(dryRun: Bool = false) {
        let arguments = dryRun ? ["cleanup", "-n", "--prune=all"] : ["cleanup", "--prune=all"]
        runMaintenance(
            title: dryRun ? "Preview Homebrew Cleanup" : "Clean Disk Cache (brew cleanup)",
            arguments: arguments,
            category: .reversibleMutation,
            refreshAfterSuccess: true
        )
    }

    func autoremove() {
        runMaintenance(
            title: "Remove Unused Dependencies (brew autoremove)",
            arguments: ["autoremove"],
            category: .destructiveMutation,
            refreshAfterSuccess: true
        )
    }

    func exportBrewfile(to url: URL) {
        runMaintenance(
            title: "Export Brewfile",
            arguments: ["bundle", "dump", "--file=\(url.path)", "--force"],
            category: .reversibleMutation,
            refreshAfterSuccess: false
        )
    }

    func exportCustomBrewfile(packages: [BrewStorePackage], taps: [BrewStoreTap] = [], to url: URL) {
        let content = BrewStoreBrewfileParser.generate(packages: packages, taps: taps)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            recordOperation(title: "Export custom Brewfile", succeeded: true, detail: "Wrote \(packages.count) packages to \(url.path)")
            statusMessage = "Exported Brewfile to \(url.lastPathComponent)."
        } catch {
            errorMessage = "Could not export Brewfile: \(error.localizedDescription)"
            recordOperation(title: "Export custom Brewfile", succeeded: false, detail: errorMessage ?? "")
        }
    }

    func installBrewfile(from url: URL) {
        runMaintenance(
            title: "Install Brewfile",
            arguments: ["bundle", "install", "--file=\(url.path)", "--no-upgrade"],
            category: .reversibleMutation,
            refreshAfterSuccess: true
        )
    }

    func calculateStorageUsage() {
        guard let prefix = brewPrefix else { return }
        Task.detached(priority: .utility) { [prefix] in
            let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar", isDirectory: true)
            let caskroomURL = URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom", isDirectory: true)
            let cacheURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)

            let cellarBytes = Self.directorySize(at: cellarURL)
            let caskroomBytes = Self.directorySize(at: caskroomURL)
            let cacheBytes = Self.directorySize(at: cacheURL)

            let usage = BrewStoreStorageUsage(
                cellarBytes: cellarBytes,
                caskroomBytes: caskroomBytes,
                downloadCacheBytes: cacheBytes
            )

            await MainActor.run { [weak self] in
                self?.storageUsage = usage
            }
        }
    }

    func checkAnalyticsState() {
        guard let brewPath else { return }
        Task.detached(priority: .utility) { [executor, brewPath] in
            let result = executor.run(executablePath: brewPath, arguments: ["analytics", "state"], timeout: 15, category: .readOnly)
            let enabled = result.standardOutput.lowercased().contains("analytics are enabled") || result.standardOutput.lowercased().contains("influxdb")
            await MainActor.run { [weak self] in
                self?.isAnalyticsEnabled = result.succeeded ? enabled : nil
            }
        }
    }

    func setAnalytics(enabled: Bool) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        isCancelled = false
        let title = enabled ? "Enable Homebrew Analytics" : "Disable Homebrew Analytics"
        activeOperationTitle = title
        let arguments = ["analytics", enabled ? "on" : "off"]
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments, title, enabled] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 30, category: .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.activeOperationTitle = nil
                if result.succeeded {
                    self.isAnalyticsEnabled = enabled
                    self.statusMessage = "\(title) succeeded."
                } else {
                    self.errorMessage = self.failureMessage(for: result)
                    self.statusMessage = "\(title) failed."
                }
                self.recordOperation(title: title, succeeded: result.succeeded, detail: result.standardOutput)
            }
        }
    }

    func liveSearch(query: String) async -> [BrewStorePackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let brewPath, !trimmed.isEmpty else { return [] }
        let executor = self.executor
        return await Task.detached(priority: .userInitiated) {
            let result = executor.run(executablePath: brewPath, arguments: ["search", trimmed], timeout: 25, category: .readOnly)
            guard result.succeeded else { return [] }

            var results: [BrewStorePackage] = []
            var isFormulaSection = true
            for rawLine in result.standardOutput.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.contains("==> Formulae") {
                    isFormulaSection = true; continue
                }
                if line.contains("==> Casks") {
                    isFormulaSection = false; continue
                }
                guard !line.isEmpty, !line.hasPrefix("==>") else { continue }
                for token in line.split(separator: " ") {
                    let name = String(token)
                    guard !name.isEmpty else { continue }
                    results.append(
                        BrewStorePackage(
                            id: name,
                            name: name,
                            description: "",
                            homepage: "",
                            version: "",
                            kind: isFormulaSection ? .formula : .cask,
                            applicationNames: [],
                            isInstalled: false,
                            isOutdated: false
                        )
                    )
                }
            }
            return results
        }.value
    }

    func fetchDependents(for package: BrewStorePackage) async -> [String] {
        guard let brewPath, package.kind == .formula else { return [] }
        let executor = self.executor
        let packageID = package.id
        let outputNames: [String]? = await Task.detached(priority: .userInitiated) {
            let result = executor.run(executablePath: brewPath, arguments: ["uses", "--installed", packageID], timeout: 20, category: .readOnly)
            guard result.succeeded else { return nil }
            return result.standardOutput.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }.value

        if let outputNames {
            return outputNames
        }
        // Fallback to local reverse dependencies scan:
        return packages.filter {
            $0.isInstalled && ($0.dependencies.contains(package.id) || $0.dependencies.contains(package.name))
        }.map(\.name)
    }

    func fetchDependencyTree(for package: BrewStorePackage) async -> String? {
        guard let brewPath, package.kind == .formula else { return nil }
        let executor = self.executor
        let packageID = package.id
        return await Task.detached(priority: .userInitiated) {
            let result = executor.run(executablePath: brewPath, arguments: ["deps", "--tree", packageID], timeout: 20, category: .readOnly)
            guard result.succeeded else { return nil }
            let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.value
    }

    func fetchSiblingVersions(for package: BrewStorePackage) -> [BrewStorePackage] {
        guard package.kind == .formula else { return [] }
        let baseFamily = package.id.components(separatedBy: "@").first ?? package.id
        return packages.filter {
            $0.kind == .formula && $0.isInstalled && (($0.id.components(separatedBy: "@").first ?? $0.id) == baseFamily)
        }
    }

    func fetchFamilyVariants(for package: BrewStorePackage) -> [BrewStorePackage] {
        guard package.kind == .formula else { return [] }
        let baseFamily = package.id.components(separatedBy: "@").first ?? package.id
        return packages.filter {
            $0.kind == .formula && (($0.id.components(separatedBy: "@").first ?? $0.id) == baseFamily)
        }.sorted { $0.id < $1.id }
    }

    func switchLinkedVersion(from current: BrewStorePackage, to target: BrewStorePackage) {
        guard let brewPath, !isOperating, current.id != target.id else { return }
        isOperating = true
        isCancelled = false
        let title = "Switch \(current.name) to \(target.name)"
        activeOperationTitle = title
        statusMessage = "Switching linked version to \(target.name)…"
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [executor, brewPath, currentID = current.id, targetID = target.id, title] in
            // Unlink current version
            _ = executor.run(executablePath: brewPath, arguments: ["unlink", currentID], timeout: 60, category: .reversibleMutation)
            // Link new version with overwrite
            let linkResult = executor.run(executablePath: brewPath, arguments: ["link", "--overwrite", targetID], timeout: 60, category: .reversibleMutation)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isOperating = false
                self.activeOperationTitle = nil
                if linkResult.succeeded {
                    self.statusMessage = "Switched active version to \(targetID)."
                    self.recordOperation(title: title, succeeded: true, detail: linkResult.standardOutput)
                    self.refresh()
                } else {
                    self.errorMessage = self.failureMessage(for: linkResult)
                    self.statusMessage = "Version switch failed."
                    self.recordOperation(title: title, succeeded: false, detail: self.errorMessage ?? "")
                }
            }
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private func runTapCommand(_ arguments: [String], completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        guard let brewPath, !isOperating else {
            completion?(false)
            return
        }
        isOperating = true
        isCancelled = false
        let title = arguments.first == "tap" ? "Add tap \(arguments.dropFirst().joined(separator: " "))" : "Remove tap \(arguments.dropFirst().joined(separator: " "))"
        activeOperationTitle = title
        Task.detached(priority: .userInitiated) { [executor, brewPath, arguments, title] in
            let result = executor.run(executablePath: brewPath, arguments: arguments, timeout: 300, category: .reversibleMutation)
            await MainActor.run { [weak self] in
                guard let self else {
                    completion?(result.succeeded)
                    return
                }
                self.isOperating = false
                self.activeOperationTitle = nil
                self.errorMessage = result.succeeded ? nil : self.failureMessage(for: result)
                self.statusMessage = result.succeeded ? "Tap operation completed." : "Tap operation failed."
                self.recordOperation(title: title, succeeded: result.succeeded, detail: result.succeeded ? result.standardOutput : (self.errorMessage ?? ""))
                if result.succeeded {
                    self.refresh()
                }
                completion?(result.succeeded)
            }
        }
    }

    private func runMaintenance(
        title: String,
        arguments: [String],
        category: BrewStoreCommandCategory,
        refreshAfterSuccess: Bool
    ) {
        guard let brewPath, !isOperating else { return }
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = title
        errorMessage = nil
        outputLog = ""
        statusMessage = "Running \(title)…"

        Task.detached(priority: .userInitiated) { [self, executor, brewPath, arguments, category, title, refreshAfterSuccess, cancellationState] in
            let result = executor.run(
                executablePath: brewPath,
                arguments: arguments,
                timeout: 1_800,
                category: category,
                maximumOutputBytes: 2_000_000,
                cancellationCheck: { cancellationState.isCancelled },
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.appendLogChunk(chunk)
                    }
                }
            )
            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.updateSessionStartTime = nil
                self.updateSessionInitialCount = 0
                if result.succeeded {
                    self.statusMessage = "Completed \(title.lowercased())."
                    self.recordOperation(title: title, succeeded: true, detail: self.outputLog.isEmpty ? result.standardOutput : self.outputLog)
                    if refreshAfterSuccess {
                        self.refresh()
                    }
                } else {
                    self.statusMessage = "\(title) failed."
                    self.errorMessage = self.failureMessage(for: result)
                    self.recordOperation(title: title, succeeded: false, detail: self.errorMessage ?? self.outputLog)
                }
            }
        }
    }

    func clearOutputLog() {
        outputLog = ""
    }

    func runDiagnosticCommand(_ command: String) {
        guard let brewPath, !isOperating else { return }
        outputLog = ""
        isOperating = true
        activeOperationTitle = "Running brew \(command)…"
        statusMessage = "Executing brew \(command)…"

        Task.detached(priority: .userInitiated) { [self, executor, brewPath] in
            let result = executor.run(
                executablePath: brewPath,
                arguments: [command],
                timeout: 60,
                category: .readOnly,
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.appendLogChunk(chunk)
                    }
                }
            )

            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = result.succeeded ? "Completed brew \(command)" : "brew \(command) failed"
                if result.succeeded {
                    self.refresh()
                }
            }
        }
    }

    func runCustomBrewCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let brewPath, !isOperating else { return }

        var cleanInput = trimmed
        if cleanInput.lowercased().hasPrefix("brew ") {
            cleanInput = String(cleanInput.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }

        let args = cleanInput.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !args.isEmpty else { return }

        outputLog = ""
        isOperating = true
        isCancelled = false
        cancellationState.reset()
        activeOperationTitle = "Running brew \(args.joined(separator: " "))…"
        statusMessage = "Executing brew \(args.joined(separator: " "))…"

        Task.detached(priority: .userInitiated) { [self, executor, brewPath, cancellationState] in
            let result = executor.run(
                executablePath: brewPath,
                arguments: args,
                timeout: 120,
                category: .readOnly,
                cancellationCheck: { cancellationState.isCancelled },
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.appendLogChunk(chunk)
                    }
                }
            )

            await MainActor.run {
                self.isOperating = false
                self.activeOperationTitle = nil
                self.statusMessage = result.succeeded ? "Completed brew \(args.joined(separator: " "))" : "brew \(args.joined(separator: " ")) failed"
                if !result.succeeded, let status = result.terminationStatus {
                    self.appendLogChunk("\n[Exit Status: \(status)]\n")
                }
                if result.succeeded {
                    self.refresh()
                }
            }
        }
    }

    private func failureMessage(for result: BrewStoreCommandResult, fallback: String = "Homebrew did not complete the operation.") -> String {
        if result.wasCancelled {
            return "Operation cancelled."
        }
        if result.didTimeOut {
            return "Operation timed out."
        }
        if let launchError = result.launchErrorDescription {
            return launchError
        }
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private func recordOperation(title: String, succeeded: Bool, detail: String) {
        let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        operationHistory.insert(
            BrewStoreOperationRecord(date: Date(), title: title, succeeded: succeeded, detail: cleanedDetail),
            at: 0
        )
        if operationHistory.count > 50 {
            operationHistory.removeLast()
        }
    }

    private func saveOperationHistory() {
        guard let data = try? JSONEncoder().encode(operationHistory) else { return }
        UserDefaults.standard.set(data, forKey: operationHistoryKey)
    }

    nonisolated static func parseAuthoritativeInstalled(_ output: String) -> [String: String] {
        var dict = [String: String]()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ").map(String.init)
            guard let id = parts.first, !id.isEmpty else { continue }
            let version = parts.count > 1 ? parts.dropFirst().joined(separator: ", ") : nil
            dict[id.lowercased()] = version
        }
        return dict
    }

    nonisolated static func parseInstalledIDs(_ output: String) -> Set<String> {
        Set(parseAuthoritativeInstalled(output).keys)
    }
}

enum PackageAction: Equatable {
    case install
    case upgrade
    case uninstall
    case reinstall
    case link
    case linkOverwrite
    case unlink
    case adopt
    case custom(title: String, arguments: [String])

    var title: String {
        switch self {
        case .install: "Install"
        case .upgrade: "Upgrade"
        case .uninstall: "Uninstall"
        case .reinstall: "Reinstall"
        case .link: "Link"
        case .linkOverwrite: "Link (Overwrite)"
        case .unlink: "Unlink"
        case .adopt: "Adopt into Homebrew"
        case let .custom(title, _): title
        }
    }

    func arguments(for package: BrewStorePackage) -> [String] {
        let noQuarantine = package.kind == .cask && UserDefaults.standard.bool(forKey: BrewStorePreferences.Keys.noQuarantineCaskOpts)
        switch self {
        case .install:
            var args = ["install", package.kind.brewFlag]
            if noQuarantine {
                args.append("--no-quarantine")
            }
            args.append(package.id)
            return args
        case .upgrade:
            var args = ["upgrade", package.kind.brewFlag]
            if noQuarantine {
                args.append("--no-quarantine")
            }
            args.append(package.id)
            return args
        case .uninstall:
            return ["uninstall", package.kind.brewFlag, package.id]
        case .reinstall:
            var args = ["reinstall", package.kind.brewFlag]
            if noQuarantine {
                args.append("--no-quarantine")
            }
            args.append(package.id)
            return args
        case .link:
            return ["link", package.id]
        case .linkOverwrite:
            return ["link", "--overwrite", package.id]
        case .unlink:
            return ["unlink", package.id]
        case .adopt:
            return ["install", "--cask", "--adopt", package.id]
        case let .custom(_, args):
            return args
        }
    }
}

struct BrewStoreStorageUsage: Equatable {
    var cellarBytes: Int64 = 0
    var caskroomBytes: Int64 = 0
    var downloadCacheBytes: Int64 = 0
    var totalBytes: Int64 {
        cellarBytes + caskroomBytes + downloadCacheBytes
    }

    var formattedCellar: String {
        ByteCountFormatter.string(fromByteCount: cellarBytes, countStyle: .file)
    }

    var formattedCaskroom: String {
        ByteCountFormatter.string(fromByteCount: caskroomBytes, countStyle: .file)
    }

    var formattedCache: String {
        ByteCountFormatter.string(fromByteCount: downloadCacheBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

enum ServiceAction: String {
    case start
    case stop
    case restart
}
