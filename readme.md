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
