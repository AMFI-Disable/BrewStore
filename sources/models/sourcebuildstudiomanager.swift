import AppKit
import Combine
import Foundation
import SwiftUI

struct CompilerToolchainInfo: Equatable, Codable {
    let hasCommandLineTools: Bool
    let commandLineToolsPath: String?
    let clangVersion: String?
    let clangTarget: String?
    let cmakeVersion: String?
    let makeVersion: String?
    let ninjaVersion: String?
    let availableGCCs: [String]
    let detectedDate: Date

    var isReadyForCompilation: Bool {
        hasCommandLineTools && clangVersion != nil
    }

    var defaultCompilerDisplayName: String {
        if let clang = clangVersion {
            return "Apple Clang (\(clang))"
        }
        return "System Default"
    }
}

struct SourceBuildConfig: Equatable, Codable {
    var buildFromSource: Bool = true
    var head: Bool = false
    var fetchHead: Bool = false
    var verbose: Bool = true
    var selectedCompiler: String? = nil
    var parallelJobs: Int? = nil
    var customArgs: String = ""

    func generateArguments(for package: BrewStorePackage) -> [String] {
        var args = [package.isInstalled ? "reinstall" : "install"]
        if buildFromSource {
            args.append("--build-from-source")
        }
        if head {
            args.append("--HEAD")
        }
        if fetchHead {
            args.append("--fetch-HEAD")
        }
        if let cc = selectedCompiler, !cc.isEmpty {
            args.append("--cc=\(cc)")
        }
        if verbose {
            args.append("--verbose")
        }
        let extras = customArgs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        args.append(contentsOf: extras)
        args.append(package.id)
        return args
    }

    var commandPreview: String {
        let dummy = BrewStorePackage(
            id: "<formula>",
            name: "<formula>",
            description: "",
            homepage: "",
            version: "1.0",
            kind: .formula
        )
        let args = generateArguments(for: dummy)
        return "brew \(args.joined(separator: " "))"
    }
}

struct BuildLogFile: Identifiable, Hashable {
    var id: String { "\(formulaName):\(name)" }
    let name: String
    let formulaName: String
    let url: URL
    let modificationDate: Date
    let sizeInBytes: Int64
    let hasErrors: Bool
    let errorLines: [String]
    let contentPreview: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

struct FormulaBuildHistoryItem: Identifiable, Hashable {
    var id: String { formulaName }
    let formulaName: String
    let logFiles: [BuildLogFile]
    let lastBuildDate: Date
    let hasErrors: Bool

    var errorFileCount: Int {
        logFiles.filter(\.hasErrors).count
    }
}

@MainActor
final class BrewStoreSourceBuildManager: ObservableObject {
    static let shared = BrewStoreSourceBuildManager()

    @Published var toolchainInfo: CompilerToolchainInfo?
    @Published var buildHistory: [FormulaBuildHistoryItem] = []
    @Published var isDetectingToolchain: Bool = false
    @Published var isExecutingBuild: Bool = false
    @Published var buildStatusMessage: String? = nil

    private init() {}

    // MARK: - Toolchain Detection

    func detectToolchain(prefix: String? = nil) async -> CompilerToolchainInfo {
        isDetectingToolchain = true
        let effectivePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")

        let info = await Task.detached(priority: .userInitiated) {
            let cltPath = Self.runSimpleCommand("/usr/bin/xcode-select", arguments: ["-p"])
            let hasCLT = cltPath?.isEmpty == false

            let clangRaw = Self.runSimpleCommand("/usr/bin/clang", arguments: ["--version"]) ?? ""
            let parsedClang = Self.parseClangVersion(clangRaw)

            let cmakeRaw = Self.runSimpleCommand("\(effectivePrefix)/bin/cmake", arguments: ["--version"]) ??
                           Self.runSimpleCommand("/usr/bin/cmake", arguments: ["--version"])
            let cmakeVer = cmakeRaw?.components(separatedBy: .newlines).first

            let makeRaw = Self.runSimpleCommand("/usr/bin/make", arguments: ["--version"])
            let makeVer = makeRaw?.components(separatedBy: .newlines).first

            let ninjaRaw = Self.runSimpleCommand("\(effectivePrefix)/bin/ninja", arguments: ["--version"]) ??
                            Self.runSimpleCommand("/usr/bin/ninja", arguments: ["--version"])
            let ninjaVer = ninjaRaw?.components(separatedBy: .newlines).first

            let gccSearchDirs = ["\(effectivePrefix)/bin", "/usr/local/bin"]
            let gccs = Self.findGCCCompilers(in: gccSearchDirs)

            return CompilerToolchainInfo(
                hasCommandLineTools: hasCLT,
                commandLineToolsPath: cltPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                clangVersion: parsedClang.version,
                clangTarget: parsedClang.target,
                cmakeVersion: cmakeVer?.trimmingCharacters(in: .whitespacesAndNewlines),
                makeVersion: makeVer?.trimmingCharacters(in: .whitespacesAndNewlines),
                ninjaVersion: ninjaVer?.trimmingCharacters(in: .whitespacesAndNewlines),
                availableGCCs: gccs,
                detectedDate: Date()
            )
        }.value

        toolchainInfo = info
        isDetectingToolchain = false
        return info
    }

    // MARK: - Build Logs Scanner

    func scanAllBuildLogs() async -> [FormulaBuildHistoryItem] {
        let logsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Homebrew", isDirectory: true)

        let items = await Task.detached(priority: .utility) {
            guard let formulaDirs = try? FileManager.default.contentsOfDirectory(
                at: logsRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [FormulaBuildHistoryItem]()
            }

            var historyItems: [FormulaBuildHistoryItem] = []

            for dir in formulaDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let formulaName = dir.lastPathComponent
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                var logFiles: [BuildLogFile] = []
                var newestDate = Date.distantPast
                var formulaHasErrors = false

                for fileURL in files {
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { continue }
                    let size = (attrs[.size] as? Int64) ?? 0
                    let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                    if modDate > newestDate {
                        newestDate = modDate
                    }

                    // Only read files under 2MB for error checking
                    var content = ""
                    if size < 2 * 1024 * 1024, let str = try? String(contentsOf: fileURL, encoding: .utf8) {
                        content = str
                    }

                    let (hasErr, errLines) = Self.detectErrors(in: content)
                    if hasErr {
                        formulaHasErrors = true
                    }

                    let preview = String(content.prefix(500))
                    let logFile = BuildLogFile(
                        name: fileURL.lastPathComponent,
                        formulaName: formulaName,
                        url: fileURL,
                        modificationDate: modDate,
                        sizeInBytes: size,
                        hasErrors: hasErr,
                        errorLines: errLines,
                        contentPreview: preview
                    )
                    logFiles.append(logFile)
                }

                logFiles.sort { $0.name < $1.name }

                if !logFiles.isEmpty {
                    let item = FormulaBuildHistoryItem(
                        formulaName: formulaName,
                        logFiles: logFiles,
                        lastBuildDate: newestDate == Date.distantPast ? Date() : newestDate,
                        hasErrors: formulaHasErrors
                    )
                    historyItems.append(item)
                }
            }

            historyItems.sort { $0.lastBuildDate > $1.lastBuildDate }
            return historyItems
        }.value

        buildHistory = items
        return items
    }

    func fetchLogs(for formulaName: String) async -> [BuildLogFile] {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Homebrew", isDirectory: true)
            .appendingPathComponent(formulaName, isDirectory: true)

        return await Task.detached(priority: .utility) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: logsDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var logFiles: [BuildLogFile] = []
            for fileURL in files {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { continue }
                let size = (attrs[.size] as? Int64) ?? 0
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()

                var content = ""
                if size < 2 * 1024 * 1024, let str = try? String(contentsOf: fileURL, encoding: .utf8) {
                    content = str
                }

                let (hasErr, errLines) = Self.detectErrors(in: content)
                let preview = String(content.prefix(500))
                let log = BuildLogFile(
                    name: fileURL.lastPathComponent,
                    formulaName: formulaName,
                    url: fileURL,
                    modificationDate: modDate,
                    sizeInBytes: size,
                    hasErrors: hasErr,
                    errorLines: errLines,
                    contentPreview: preview
                )
                logFiles.append(log)
            }
            return logFiles.sorted { $0.name < $1.name }
        }.value
    }

    func clearBuildLogs(for formulaName: String) -> Bool {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Homebrew", isDirectory: true)
            .appendingPathComponent(formulaName, isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: logsDir.path) {
                try FileManager.default.removeItem(at: logsDir)
                buildHistory.removeAll { $0.formulaName == formulaName }
                return true
            }
        } catch {
            return false
        }
        return false
    }

    func clearAllBuildLogs() -> Int {
        let logsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Homebrew", isDirectory: true)

        var count = 0
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: logsRoot, includingPropertiesForKeys: nil) else {
            return 0
        }

        for dir in dirs {
            if (try? FileManager.default.removeItem(at: dir)) != nil {
                count += 1
            }
        }

        buildHistory.removeAll()
        return count
    }

    // MARK: - Source Build Execution

    func executeSourceBuild(
        package: BrewStorePackage,
        config: SourceBuildConfig,
        manager: HomebrewManager
    ) async -> Bool {
        isExecutingBuild = true
        buildStatusMessage = "Building \(package.name) from source…"

        let args = config.generateArguments(for: package)
        let success: Bool = await withCheckedContinuation { continuation in
            manager.perform(
                package: package,
                action: .custom(title: "Build \(package.name) from Source", arguments: args)
            ) { success in
                continuation.resume(returning: success)
            }
        }

        isExecutingBuild = false
        buildStatusMessage = nil

        // Automatically scan build logs after build
        _ = await scanAllBuildLogs()

        return success
    }

    // MARK: - Static Parser & Utility Helpers

    nonisolated static func parseClangVersion(_ output: String) -> (version: String?, target: String?) {
        var version: String?
        var target: String?

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("clang version") {
                let parts = trimmed.components(separatedBy: "version")
                if parts.count > 1 {
                    version = parts[1].trimmingCharacters(in: .whitespaces)
                }
            } else if trimmed.hasPrefix("Target:") {
                target = trimmed.replacingOccurrences(of: "Target:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (version, target)
    }

    nonisolated static func findGCCCompilers(in directories: [String]) -> [String] {
        var compilers: Set<String> = []
        let fm = FileManager.default
        for dir in directories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files {
                if file.hasPrefix("gcc-") {
                    let suffix = String(file.dropFirst(4))
                    if Int(suffix) != nil {
                        compilers.insert(file)
                    }
                }
            }
        }
        return compilers.sorted { a, b in
            let numA = Int(a.dropFirst(4)) ?? 0
            let numB = Int(b.dropFirst(4)) ?? 0
            return numA > numB
        }
    }

    nonisolated static func detectErrors(in logContent: String) -> (hasErrors: Bool, errorLines: [String]) {
        var errorLines: [String] = []
        let lines = logContent.components(separatedBy: .newlines)
        let indicators = [
            "error:",
            "fatal error:",
            "clang: error:",
            "error generated",
            "errors generated",
            "make: ***",
            "CMake Error",
            "FAILED:",
            "ld: symbol(s) not found",
            "configure: error:"
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for ind in indicators {
                if trimmed.localizedCaseInsensitiveContains(ind) {
                    errorLines.append(trimmed)
                    break
                }
            }
            if errorLines.count >= 50 { break }
        }

        return (!errorLines.isEmpty, errorLines)
    }

    nonisolated static func runSimpleCommand(_ executable: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
