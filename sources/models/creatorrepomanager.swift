import Foundation

struct GitHubRepo: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let full_name: String
    let description: String?
    let html_url: String
    let stargazers_count: Int
    let forks_count: Int
    let open_issues_count: Int
    let default_branch: String?

    var isTap: Bool {
        name.lowercased().hasPrefix("homebrew-")
    }

    var tapShortName: String {
        if isTap {
            return String(name.dropFirst("homebrew-".count))
        }
        return name
    }

    func tapCommandName(owner: String) -> String {
        "\(owner)/\(tapShortName)"
    }
}

enum ScaffoldKind: String, CaseIterable, Identifiable, Codable {
    case formula = "Formula (CLI)"
    case cask = "Cask (macOS App)"

    var id: String {
        rawValue
    }
}

enum BrewStoreFormulaScaffolder {
    static func rubyClassName(from name: String) -> String {
        name
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map(\.capitalized)
            .joined()
    }

    static func scaffoldFormula(repo: GitHubRepo, owner: String, version: String = "1.0.0", binaryName: String? = nil) -> String {
        let clsName = rubyClassName(from: repo.name)
        let desc = repo.description ?? "A CLI tool built by \(owner)"
        let bin = binaryName ?? repo.name
        let url = "https://github.com/\(repo.full_name)/archive/refs/tags/v#{version}.tar.gz"

        return """
        class \(clsName) < Formula
          desc "\(desc)"
          homepage "\(repo.html_url)"
          url "\(url)"
          version "\(version)"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"
          license "MIT"

          # depends_on "go" => :build # or "rust", "cmake"

          def install
            bin.install "\(bin)"
          end

          test do
            system "#{bin}/\(bin)", "--version"
          end
        end
        """
    }

    static func scaffoldCask(repo: GitHubRepo, owner: String, version: String = "1.0.0", appName: String? = nil) -> String {
        let caskName = repo.name.lowercased()
        let desc = repo.description ?? "macOS application created by \(owner)"
        let app = appName ?? "\(rubyClassName(from: repo.name)).app"

        return """
        cask "\(caskName)" do
          version "\(version)"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"

          url "https://github.com/\(repo.full_name)/releases/download/v#{version}/\(caskName)-#{version}.dmg"
          name "\(rubyClassName(from: repo.name))"
          desc "\(desc)"
          homepage "\(repo.html_url)"

          app "\(app)"

          zap trash: [
            "~/Library/Application Support/\(rubyClassName(from: repo.name))",
            "~/Library/Preferences/com.\(owner.lowercased()).\(caskName).plist",
            "~/Library/Caches/com.\(owner.lowercased()).\(caskName)",
          ]
        end
        """
    }

    static func scaffoldGenericFormula(name: String, desc: String, homepage: String, url: String, version: String, bin: String) -> String {
        let clsName = rubyClassName(from: name.isEmpty ? "MyTool" : name)
        let cleanDesc = desc.isEmpty ? "CLI tool" : desc
        let cleanHomepage = homepage.isEmpty ? "https://example.com" : homepage
        let cleanUrl = url.isEmpty ? "https://example.com/archive/v1.0.0.tar.gz" : url
        let cleanBin = bin.isEmpty ? (name.isEmpty ? "mytool" : name) : bin

        return """
        class \(clsName) < Formula
          desc "\(cleanDesc)"
          homepage "\(cleanHomepage)"
          url "\(cleanUrl)"
          version "\(version.isEmpty ? "1.0.0" : version)"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"
          license "MIT"

          # depends_on "go" => :build # or "rust", "cmake"

          def install
            bin.install "\(cleanBin)"
          end

          test do
            system "#{bin}/\(cleanBin)", "--version"
          end
        end
        """
    }

    static func scaffoldGenericCask(name: String, desc: String, homepage: String, url: String, version: String, appName: String) -> String {
        let cleanToken = (name.isEmpty ? "myapp" : name).lowercased().replacingOccurrences(of: " ", with: "-")
        let clsName = rubyClassName(from: name.isEmpty ? "MyApp" : name)
        let cleanDesc = desc.isEmpty ? "macOS application" : desc
        let cleanHomepage = homepage.isEmpty ? "https://example.com" : homepage
        let cleanUrl = url.isEmpty ? "https://example.com/downloads/#{version}/\(cleanToken)-#{version}.dmg" : url
        let cleanApp = appName.isEmpty ? "\(clsName).app" : appName

        return """
        cask "\(cleanToken)" do
          version "\(version.isEmpty ? "1.0.0" : version)"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"

          url "\(cleanUrl)"
          name "\(clsName)"
          desc "\(cleanDesc)"
          homepage "\(cleanHomepage)"

          app "\(cleanApp)"

          zap trash: [
            "~/Library/Application Support/\(clsName)",
            "~/Library/Preferences/com.example.\(cleanToken).plist",
            "~/Library/Caches/com.example.\(cleanToken)",
          ]
        end
        """
    }
}

@MainActor
final class BrewStoreCreatorRepoManager: ObservableObject {
    static let shared = BrewStoreCreatorRepoManager()

    @Published var repos: [GitHubRepo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastFetched: Date?

    var taps: [GitHubRepo] {
        repos.filter(\.isTap)
    }

    var softwareRepos: [GitHubRepo] {
        repos.filter { !$0.isTap }
    }

    func isTapLocallyInstalled(_ repo: GitHubRepo, owner: String, manager: HomebrewManager) -> Bool {
        let expected = repo.tapCommandName(owner: owner).lowercased()
        return manager.taps.contains { $0.name.lowercased() == expected }
    }

    func fetchRepos(token: String) async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "https://api.github.com/user/repos?type=all&sort=updated&per_page=100") else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("BrewStore-macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isLoading = false
                errorMessage = "Failed to fetch repositories."
                return
            }

            let decoded = try JSONDecoder().decode([GitHubRepo].self, from: data)
            self.repos = decoded
            self.lastFetched = Date()
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
