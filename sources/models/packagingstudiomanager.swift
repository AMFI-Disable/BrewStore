import AppKit
import CryptoKit
import Foundation

struct PackagingAuditResult: Identifiable, Hashable {
    let id = UUID().uuidString
    let isSuccess: Bool
    let issues: [String]
    let rawOutput: String
}

@MainActor
final class BrewStorePackagingStudioManager: ObservableObject {
    static let shared = BrewStorePackagingStudioManager()

    @Published var isCalculatingSHA256 = false
    @Published var isRunningAudit = false
    @Published var auditResult: PackagingAuditResult?
    @Published var statusMessage: String?
    @Published var lastPublishedPath: String?

    init() {}

    // MARK: - SHA256 Hashing

    func computeSHA256(for fileURL: URL) async -> String? {
        isCalculatingSHA256 = true
        statusMessage = "Hashing \(fileURL.lastPathComponent)…"
        defer {
            isCalculatingSHA256 = false
            statusMessage = nil
        }

        return await Task.detached(priority: .userInitiated) {
            guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
            defer { try? fileHandle.close() }

            var hasher = SHA256()
            while let data = try? fileHandle.read(upToCount: 1024 * 1024), !data.isEmpty {
                hasher.update(data: data)
            }
            let digest = hasher.finalize()
            return digest.map { String(format: "%02hhx", $0) }.joined()
        }.value
    }

    func downloadAndComputeSHA256(from url: URL) async -> String? {
        isCalculatingSHA256 = true
        statusMessage = "Downloading and calculating SHA256 for \(url.lastPathComponent)…"
        defer {
            isCalculatingSHA256 = false
            statusMessage = nil
        }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            let hash = await computeSHA256(for: tempURL)
            return hash
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Formula & Cask DSL Generation

    func generateFormulaRecipe(
        name: String,
        version: String,
        url: String,
        sha256: String,
        desc: String,
        homepage: String,
        license: String,
        dependencies: [String],
        buildSystem: String,
        binaryName: String
    ) -> String {
        let clsName = BrewStoreFormulaScaffolder.rubyClassName(from: name.isEmpty ? "MyPackage" : name)
        let bin = binaryName.isEmpty ? (name.isEmpty ? "mybinary" : name.lowercased()) : binaryName
        let cleanDesc = desc.isEmpty ? "Command-line tool packaged with BrewStore" : desc
        let cleanHome = homepage.isEmpty ? "https://example.com" : homepage
        let cleanURL = url.isEmpty ? "https://example.com/download/v#{version}.tar.gz" : url
        let cleanSHA = sha256.isEmpty ? "0000000000000000000000000000000000000000000000000000000000000000" : sha256
        let cleanVer = version.isEmpty ? "1.0.0" : version
        let cleanLic = license.isEmpty ? "MIT" : license

        var depsRuby = ""
        for dep in dependencies where !dep.trimmingCharacters(in: .whitespaces).isEmpty {
            depsRuby += "  depends_on \"\(dep.trimmingCharacters(in: .whitespaces))\"\n"
        }

        var installBody = "    bin.install \"\(bin)\""
        if buildSystem == "CMake" {
            installBody = """
                system "cmake", "-S", ".", "-B", "build", *std_cmake_args
                system "cmake", "--build", "build"
                system "cmake", "--install", "build"
            """
        } else if buildSystem == "Rust / Cargo" {
            installBody = "    system \"cargo\", \"install\", *std_cargo_args"
        } else if buildSystem == "Go" {
            installBody = "    system \"go\", \"build\", *std_go_args(ldflags: \"-s -w\"), \"-o\", bin/\"\(bin)\""
        } else if buildSystem == "Makefile" {
            installBody = """
                system "make", "PREFIX=#{prefix}", "install"
            """
        }

        return """
        class \(clsName) < Formula
          desc "\(cleanDesc)"
          homepage "\(cleanHome)"
          url "\(cleanURL)"
          version "\(cleanVer)"
          sha256 "\(cleanSHA)"
          license "\(cleanLic)"

        \(depsRuby.isEmpty ? "" : depsRuby)
          def install
        \(installBody)
          end

          test do
            system "#{bin}/\(bin)", "--version"
          end
        end
        """
    }

    func generateCaskRecipe(
        name: String,
        version: String,
        url: String,
        sha256: String,
        desc: String,
        homepage: String,
        appName: String,
        bundleID: String
    ) -> String {
        let caskName = name.isEmpty ? "myapp" : name.lowercased().replacingOccurrences(of: " ", with: "-")
        let cleanDesc = desc.isEmpty ? "macOS application packaged with BrewStore" : desc
        let cleanHome = homepage.isEmpty ? "https://example.com" : homepage
        let cleanURL = url.isEmpty ? "https://example.com/download/v#{version}/\(caskName)-#{version}.dmg" : url
        let cleanSHA = sha256.isEmpty ? "0000000000000000000000000000000000000000000000000000000000000000" : sha256
        let cleanVer = version.isEmpty ? "1.0.0" : version
        let app = appName.isEmpty ? "\(BrewStoreFormulaScaffolder.rubyClassName(from: name)).app" : (appName.hasSuffix(".app") ? appName : "\(appName).app")
        let bid = bundleID.isEmpty ? "com.example.\(caskName)" : bundleID

        return """
        cask "\(caskName)" do
          version "\(cleanVer)"
          sha256 "\(cleanSHA)"

          url "\(cleanURL)"
          name "\(BrewStoreFormulaScaffolder.rubyClassName(from: name))"
          desc "\(cleanDesc)"
          homepage "\(cleanHome)"

          app "\(app)"

          zap trash: [
            "~/Library/Application Support/\(caskName)",
            "~/Library/Preferences/\(bid).plist",
            "~/Library/Caches/\(bid)",
          ]
        end
        """
    }

    // MARK: - Sandboxed Audit Runner

    func runSandboxedAudit(recipeCode: String, isCask: Bool, manager: HomebrewManager) async -> PackagingAuditResult {
        guard let brewPath = manager.brewPath else {
            return PackagingAuditResult(isSuccess: false, issues: ["Homebrew path is not resolved."], rawOutput: "")
        }

        isRunningAudit = true
        statusMessage = "Running sandboxed brew audit…"
        defer {
            isRunningAudit = false
            statusMessage = nil
        }

        return await Task.detached(priority: .userInitiated) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BrewStoreStudioAudit", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent("audit_target.rb")

            try? recipeCode.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let args: [String] = isCask
                ? ["audit", "--cask", "--strict", tempFile.path]
                : ["audit", "--formula", "--strict", tempFile.path]

            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: args,
                timeout: 30,
                category: .readOnly
            )

            var issues: [String] = []
            let fullOutput = result.standardOutput + "\n" + result.standardError
            let lines = fullOutput.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            for line in lines {
                if line.contains("* ") || line.contains("Error:") || line.contains("Warning:") {
                    issues.append(line)
                }
            }

            let auditRes = PackagingAuditResult(
                isSuccess: result.succeeded && issues.isEmpty,
                issues: issues.isEmpty && !result.succeeded ? ["Audit process reported issues: \(result.standardError)"] : issues,
                rawOutput: fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await MainActor.run {
                self.auditResult = auditRes
            }

            return auditRes
        }.value
    }

    // MARK: - Tap Publisher

    func publishToLocalTap(
        recipeCode: String,
        name: String,
        isCask: Bool,
        tap: BrewStoreTap,
        manager: HomebrewManager
    ) -> (success: Bool, message: String) {
        let fm = FileManager.default
        let prefix = manager.brewPrefix ?? (fm.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")

        // e.g. /opt/homebrew/Library/Taps/username/homebrew-tapname
        let parts = tap.name.split(separator: "/")
        guard parts.count == 2 else {
            return (false, "Malformed tap name: \(tap.name)")
        }
        let user = String(parts[0])
        let repo = String(parts[1])
        let tapRepoName = repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)"

        let tapDir = URL(fileURLWithPath: prefix)
            .appendingPathComponent("Library/Taps", isDirectory: true)
            .appendingPathComponent(user, isDirectory: true)
            .appendingPathComponent(tapRepoName, isDirectory: true)

        guard fm.fileExists(atPath: tapDir.path) else {
            return (false, "Local tap directory not found at \(tapDir.path). Ensure tap is cloned.")
        }

        let subfolder = isCask ? "Casks" : "Formula"
        let targetDir = tapDir.appendingPathComponent(subfolder, isDirectory: true)
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let filename = isCask ? "\(name.lowercased()).rb" : "\(name.lowercased()).rb"
        let destURL = targetDir.appendingPathComponent(filename)

        do {
            try recipeCode.write(to: destURL, atomically: true, encoding: .utf8)
            lastPublishedPath = destURL.path
            return (true, "Successfully published \(filename) to \(destURL.path)!")
        } catch {
            return (false, "Failed to write file: \(error.localizedDescription)")
        }
    }
}
