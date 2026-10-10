cask "brewstore" do
  version "1.0.0"
  sha256 "6feeca33809eb2d8b59945591bbb7f636f63139c576684f3a38de7d7d853a871"

  url "https://github.com/AMFI-Disable/BrewStore/releases/download/v#{version}/brewstore-#{version}.dmg"
  name "BrewStore"
  desc "Modern, lightning-fast GUI and CLI package manager for Homebrew"
  homepage "https://github.com/AMFI-Disable/BrewStore"

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

  caveats <<~EOS
    BrewStore is an unnotarized open-source build.
    If macOS Gatekeeper prevents opening on launch:
      sudo xattr -r -c /Applications/BrewStore.app
    Or allow it via System Settings > Privacy & Security > Open Anyway.
  EOS

  zap trash: [
    "~/Library/Application Support/BrewStore",
    "~/Library/Caches/com.amfi-disable.BrewStore",
    "~/Library/Preferences/com.amfi-disable.BrewStore.plist",
    "~/Library/LaunchAgents/com.amfi-disable.brewstore.autoupdate.plist",
    "~/Library/Logs/BrewStore",
  ]
end
