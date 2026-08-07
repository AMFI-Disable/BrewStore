# BrewStore

BrewStore is a focused macOS Homebrew package manager. Version 1.0.0 manages casks, formulae, services, taps, updates, and Homebrew-installed application removal with a preview-first cleanup flow.

BrewStore is an independent product. It does not require the Juicer bundle or a Juicer Hub application.

## Build

From this directory:

```bash
xcodegen generate
xcodebuild test -project BrewStore.xcodeproj -scheme BrewStore -sdk macosx -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO
```

Homebrew is optional during build and required for package operations. BrewStore does not silently install it.

## Zero-budget distribution

The repository includes a Vercel-ready static download page in `website` and a reproducible ad-hoc DMG workflow:

```bash
./scripts/build-dmg.sh 1.0.0
```

The script creates `website/downloads/brewstore-1.0.0.dmg` and its SHA-256 checksum. This build is not signed with Apple Developer ID and is not notarized. Users should verify the checksum and use macOS Privacy & Security → Open Anyway when required. The documented `xattr` command only removes the download quarantine attribute; it does not provide notarization.

The Homebrew cask is maintained in the separate `homebrew-brewstore` repository. BrewStore is installed through the user’s existing Homebrew installation; Homebrew itself is not bundled in the DMG.
