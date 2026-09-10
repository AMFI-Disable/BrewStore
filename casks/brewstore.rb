cask "brewstore" do
  version "1.0.0"
  sha256 "2a187fae00dda997c99b9377610e16ab24c067aaf473f3a2ead0ca25eea789d9"

  url "https://github.com/amfi-disable/BrewStore/releases/download/v#{version}/brewstore-#{version}.dmg"
  name "BrewStore"
  desc "Modern, lightning-fast GUI and CLI package manager for Homebrew"
  homepage "https://github.com/amfi-disable/BrewStore"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "BrewStore.app"
  binary "#{appdir}/BrewStore.app/Contents/Resources/scripts/brewstore", target: "brewstore"

  postflight do
    # Remove quarantine attribute for unnotarized ad-hoc builds
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/BrewStore.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/BrewStore",
    "~/Library/Caches/com.amfi-disable.BrewStore",
    "~/Library/Preferences/com.amfi-disable.BrewStore.plist",
    "~/Library/LaunchAgents/com.amfi-disable.brewstore.autoupdate.plist",
    "~/Library/Logs/BrewStore",
  ]
end
