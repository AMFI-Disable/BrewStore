import AppKit
import Foundation

struct AppReleaseInfo: Identifiable, Hashable {
    var id: String {
        version
    }

    let version: String
    let releaseDate: Date?
    let releaseNotes: String
    let downloadURL: URL?
    let isPrerelease: Bool
}

@MainActor
final class BrewStoreAppUpdateChecker: ObservableObject {
    static let shared = BrewStoreAppUpdateChecker()

    @Published var isChecking: Bool = false
    @Published var isUpdateAvailable: Bool = false
    @Published var latestRelease: AppReleaseInfo?
    @Published var lastCheckDate: Date?
    @Published var statusMessage: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private let releaseAPIURL = URL(string: "https://api.github.com/repos/amfi-disable/BrewStore/releases/latest") ?? URL(fileURLWithPath: "/dev/null")
    private let appcastFallbackURL = URL(string: "https://raw.githubusercontent.com/amfi-disable/BrewStore/main/website/downloads/appcast.xml") ?? URL(fileURLWithPath: "/dev/null")

    init() {
        if let timestamp = UserDefaults.standard.object(forKey: "brewstore.appupdate.lastcheck") as? Double, timestamp > 0 {
            self.lastCheckDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    func checkForAppUpdates() {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = "Checking for BrewStore updates…"

        Task {
            do {
                var request = URLRequest(url: releaseAPIURL)
                request.setValue("BrewStore/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 10

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    await checkFallbackAppcast()
                    return
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let tagName = (json["tag_name"] as? String ?? "").replacingOccurrences(of: "v", with: "")
                    let body = json["body"] as? String ?? "Bug fixes and performance improvements."
                    let isPrerelease = json["prerelease"] as? Bool ?? false

                    var downloadURL: URL?
                    if let assets = json["assets"] as? [[String: Any]] {
                        for asset in assets {
                            if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                               let urlStr = asset["browser_download_url"] as? String {
                                downloadURL = URL(string: urlStr)
                                break
                            }
                        }
                    }

                    if downloadURL == nil {
                        downloadURL = URL(string: "https://github.com/amfi-disable/BrewStore/releases/download/v\(tagName)/brewstore-\(tagName).dmg")
                    }

                    let release = AppReleaseInfo(
                        version: tagName.isEmpty ? currentVersion : tagName,
                        releaseDate: Date(),
                        releaseNotes: body,
                        downloadURL: downloadURL,
                        isPrerelease: isPrerelease
                    )

                    await MainActor.run {
                        self.latestRelease = release
                        self.isUpdateAvailable = Self.isNewerVersion(remote: release.version, local: self.currentVersion)
                        self.isChecking = false
                        self.lastCheckDate = Date()
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "brewstore.appupdate.lastcheck")

                        if self.isUpdateAvailable {
                            self.statusMessage = "New version \(release.version) is available!"
                        } else {
                            self.statusMessage = "You're on the latest version (\(self.currentVersion))."
                        }
                    }
                }
            } catch {
                await checkFallbackAppcast()
            }
        }
    }

    private func checkFallbackAppcast() async {
        do {
            var request = URLRequest(url: appcastFallbackURL)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8),
                  xml.contains("<rss") || xml.contains("<channel")
            else {
                await MainActor.run {
                    self.isChecking = false
                    self.isUpdateAvailable = false
                    self.latestRelease = AppReleaseInfo(
                        version: self.currentVersion,
                        releaseDate: Date(),
                        releaseNotes: "Initial Release.",
                        downloadURL: nil,
                        isPrerelease: false
                    )
                    self.lastCheckDate = Date()
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "brewstore.appupdate.lastcheck")
                    self.statusMessage = "You're on the latest version (\(self.currentVersion)). (No newer public release is available)"
                }
                return
            }

            let release = Self.parseAppcast(xml: xml, currentVersion: currentVersion)
            await MainActor.run {
                self.latestRelease = release
                self.isUpdateAvailable = Self.isNewerVersion(remote: release.version, local: self.currentVersion)
                self.isChecking = false
                self.lastCheckDate = Date()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "brewstore.appupdate.lastcheck")
                self.statusMessage = self.isUpdateAvailable ? "New version \(release.version) is available!" : "You're on the latest version (\(self.currentVersion))."
            }
        } catch {
            await MainActor.run {
                self.isChecking = false
                self.isUpdateAvailable = false
                self.latestRelease = AppReleaseInfo(
                    version: self.currentVersion,
                    releaseDate: Date(),
                    releaseNotes: "Initial Release.",
                    downloadURL: nil,
                    isPrerelease: false
                )
                self.lastCheckDate = Date()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "brewstore.appupdate.lastcheck")
                self.statusMessage = "You're on the latest version (\(self.currentVersion)). (Remote release feed is offline or unpublished)"
            }
        }
    }

    func downloadAndOpenRelease() {
        if isUpdateAvailable, let url = latestRelease?.downloadURL {
            NSWorkspace.shared.open(url)
        } else if let siteURL = URL(string: "https://github.com/amfi-disable/BrewStore") {
            NSWorkspace.shared.open(siteURL)
        }
    }

    nonisolated static func isNewerVersion(remote: String, local: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanLocal = local.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let localParts = cleanLocal.split(separator: ".").compactMap { Int($0) }

        for i in 0 ..< max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l {
                return true
            }
            if r < l {
                return false
            }
        }
        return false
    }

    nonisolated static func parseAppcast(xml: String, currentVersion: String) -> AppReleaseInfo {
        var version = currentVersion
        if let match = xml.range(of: "sparkle:shortVersionString=\"([^\"]+)\"", options: .regularExpression) {
            let sub = xml[match]
            version = sub.replacingOccurrences(of: "sparkle:shortVersionString=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }

        var downloadURL: URL?
        if let match = xml.range(of: "url=\"([^\"]+)\"", options: .regularExpression) {
            let sub = xml[match]
            let urlStr = sub.replacingOccurrences(of: "url=\"", with: "").replacingOccurrences(of: "\"", with: "")
            downloadURL = URL(string: urlStr)
        }

        return AppReleaseInfo(
            version: version,
            releaseDate: Date(),
            releaseNotes: "Latest update package.",
            downloadURL: downloadURL,
            isPrerelease: false
        )
    }
}
