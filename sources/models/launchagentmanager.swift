import Foundation

struct LaunchAgentRunStatus: Identifiable, Hashable, Codable {
    var id: String {
        timestamp.ISO8601Format()
    }

    let timestamp: Date
    let status: String
    let totalOutdated: Int
    let outdatedFormulae: [String]
    let outdatedCasks: [String]
    let errorMessage: String?
    let summary: String?

    var isSuccess: Bool {
        status == "success"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

@MainActor
final class BrewStoreLaunchAgentManager: ObservableObject {
    static let shared = BrewStoreLaunchAgentManager()

    static let label = "com.amfi-disable.brewstore.autoupdate"

    @Published var isEnabled: Bool = false
    @Published var intervalHours: Int = 6
    @Published var lastStatus: LaunchAgentRunStatus?
    @Published var isRunningCheckNow: Bool = false
    @Published var statusMessage: String?

    private let fileManager = FileManager.default

    var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    var appSupportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BrewStore", isDirectory: true)
    }

    var scriptURL: URL {
        appSupportDirectory.appendingPathComponent("scripts/autoupdate.sh")
    }

    var statusFileURL: URL {
        appSupportDirectory.appendingPathComponent("autoupdate_status.json")
    }

    var logFileURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BrewStore/autoupdate.log")
    }

    init() {
        self.intervalHours = UserDefaults.standard.object(forKey: "brewstore.launchagent.interval") as? Int ?? 1
        checkInstallationState()
        reloadStatus()
    }

    func checkInstallationState() {
        self.isEnabled = fileManager.fileExists(atPath: plistURL.path)
    }

    func reloadStatus() {
        guard fileManager.fileExists(atPath: statusFileURL.path),
              let data = try? Data(contentsOf: statusFileURL)
        else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(LaunchAgentRunStatus.self, from: data) {
            self.lastStatus = decoded
        }
    }

    func toggleLaunchAgent(enabled: Bool) {
        if enabled {
            installLaunchAgent()
        } else {
            uninstallLaunchAgent()
        }
    }

    func installLaunchAgent() {
        do {
            // 1. Create directories
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let scriptsDir = appSupportDirectory.appendingPathComponent("scripts", isDirectory: true)
            try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
            let logsDir = logFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)

            // 2. Deploy script
            let scriptContent = Self.defaultScriptContent()
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            var scriptAttrs = (try? fileManager.attributesOfItem(atPath: scriptURL.path)) ?? [:]
            scriptAttrs[.posixPermissions] = 0o755
            try fileManager.setAttributes(scriptAttrs, ofItemAtPath: scriptURL.path)

            // 3. Generate & Write Plist
            let intervalSeconds = max(intervalHours, 1) * 3600
            let plistContent = Self.generatePlist(
                label: Self.label,
                scriptPath: scriptURL.path,
                intervalSeconds: intervalSeconds,
                logPath: logFileURL.path
            )
            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

            // 4. Load into launchctl
            let plistPath = plistURL.path
            Task.detached(priority: .userInitiated) {
                _ = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/bin/launchctl",
                    arguments: ["load", "-w", plistPath],
                    timeout: 15,
                    category: .reversibleMutation
                )
            }

            self.isEnabled = true
            UserDefaults.standard.set(intervalHours, forKey: "brewstore.launchagent.interval")
            self.statusMessage = "LaunchAgent successfully registered for background checks every \(intervalHours)h."
        } catch {
            self.statusMessage = "Failed to install LaunchAgent: \(error.localizedDescription)"
        }
    }

    func uninstallLaunchAgent() {
        let plistPath = plistURL.path
        if fileManager.fileExists(atPath: plistPath) {
            Task.detached(priority: .userInitiated) {
                _ = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/bin/launchctl",
                    arguments: ["unload", plistPath],
                    timeout: 15,
                    category: .reversibleMutation
                )
            }

            try? fileManager.removeItem(at: plistURL)
        }

        self.isEnabled = false
        self.statusMessage = "LaunchAgent background checking disabled."
    }

    func runCheckNow() {
        guard !isRunningCheckNow else { return }
        isRunningCheckNow = true
        statusMessage = "Running background LaunchAgent check now…"

        let scriptURL = self.scriptURL
        Task.detached(priority: .userInitiated) { [self, scriptURL] in
            if !FileManager.default.fileExists(atPath: scriptURL.path) {
                await MainActor.run {
                    self.installLaunchAgent()
                }
            }

            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: "/bin/bash",
                arguments: [scriptURL.path],
                timeout: 120,
                category: .readOnly
            )

            await MainActor.run {
                self.isRunningCheckNow = false
                self.reloadStatus()
                self.statusMessage = "Background check complete."
            }
        }
    }

    nonisolated static func generatePlist(label: String, scriptPath: String, intervalSeconds: Int, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptPath)</string>
            </array>
            <key>StartInterval</key>
            <integer>\(intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    nonisolated static func defaultScriptContent() -> String {
        """
        #!/usr/bin/env bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        BREW_BIN=$(command -v brew || echo "/opt/homebrew/bin/brew")
        [ -x "/usr/local/bin/brew" ] && [ ! -x "/opt/homebrew/bin/brew" ] && BREW_BIN="/usr/local/bin/brew"

        APP_SUPPORT="$HOME/Library/Application Support/BrewStore"
        mkdir -p "$APP_SUPPORT"
        STATUS_FILE="$APP_SUPPORT/autoupdate_status.json"
        LOG_FILE="$HOME/Library/Logs/BrewStore/autoupdate.log"
        mkdir -p "$HOME/Library/Logs/BrewStore"

        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        if [ ! -x "$BREW_BIN" ]; then
          echo "[$(date)] Homebrew not found." >> "$LOG_FILE"
          cat <<EOF > "$STATUS_FILE"
        {"timestamp": "$TIMESTAMP", "status": "error", "errorMessage": "Homebrew binary not found", "totalOutdated": 0, "outdatedFormulae": [], "outdatedCasks": []}
        EOF
          exit 0
        fi

        OUTDATED_JSON=$("$BREW_BIN" outdated --json=v2 2>> "$LOG_FILE" || echo "{}")

        STATUS_OUTPUT=$(/usr/bin/osascript -l JavaScript -e '
        function run(argv) {
          try {
            const data = JSON.parse(argv[0] || "{}");
            const formulae = (data.formulae || []).map(f => f.name || "").filter(Boolean);
            const casks = (data.casks || []).map(c => c.name || "").filter(Boolean);
            const total = formulae.length + casks.length;
            return JSON.stringify({
              timestamp: argv[1],
              status: "success",
              totalOutdated: total,
              outdatedFormulae: formulae,
              outdatedCasks: casks,
              summary: total > 0 ? (total + " update(s) available") : "All packages up to date"
            }, null, 2);
          } catch (e) {
            return JSON.stringify({
              timestamp: argv[1],
              status: "error",
              errorMessage: String(e),
              totalOutdated: 0,
              outdatedFormulae: [],
              outdatedCasks: []
            }, null, 2);
          }
        }
        ' "$OUTDATED_JSON" "$TIMESTAMP" 2>> "$LOG_FILE")

        echo "$STATUS_OUTPUT" > "$STATUS_FILE"

        TOTAL_COUNT=$(/usr/bin/osascript -l JavaScript -e '
        function run(argv) {
          try {
            return String(JSON.parse(argv[0] || "{}").totalOutdated || 0);
          } catch (e) {
            return "0";
          }
        }
        ' "$STATUS_OUTPUT" 2>/dev/null || echo "0")

        if [ "$TOTAL_COUNT" -gt 0 ]; then
          osascript -e "display notification \\"$TOTAL_COUNT package(s) have available updates. Click to review in BrewStore.\\" with title \\"BrewStore Updates Available\\"" 2>> "$LOG_FILE" || true
        fi
        """
    }
}
