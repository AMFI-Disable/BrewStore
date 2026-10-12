cask "brewstore" do
  version "1.0.0"
  sha256 "4420b61a0aab4414272e45c582d2bcfba59b72b335ed56682de379abe2620ddf"

  url "https://github.com/AMFI-Disable/BrewStore/releases/download/v#{version}/brewstore-#{version}.dmg"
  name "BrewStore"
  desc "Modern, lightning-fast GUI and CLI package manager for Homebrew"
  homepage "https://github.com/AMFI-Disable/BrewStore"

  auto_updates true
  depends_on macos: :sonoma

  app "BrewStore.app"
  binary "#{appdir}/BrewStore.app/Contents/Resources/scripts/brewstore", target: "brewstore"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-cr", "/Applications/BrewStore.app"]
  end

  zap trash: [
    "~/Library/Application Support/BrewStore",
    "~/Library/Caches/com.amfi-disable.BrewStore",
    "~/Library/LaunchAgents/com.amfi-disable.brewstore.autoupdate.plist",
    "~/Library/Logs/BrewStore",
    "~/Library/Preferences/com.amfi-disable.BrewStore.plist",
  ]

  caveats <<~EOS
    BrewStore is an unnotarized open-source build.
    If macOS Gatekeeper prevents opening on launch:
      sudo xattr -r -c /Applications/BrewStore.app
    Or allow it via System Settings > Privacy & Security > Open Anyway.
  EOS
end
