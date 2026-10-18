# Standalone Repository Handoff

BrewStore is maintained independently from the Juicer bundle. The current repository is the standalone product repository. BrewStore keeps its command execution and removal-safety layer locally in `sources/core` and operates fully self-contained.

Before the first public BrewStore release:

1. Add the real Sparkle public key and appcast signing configuration before signing a release.
2. Add standalone build, test, release, and security checks when a CI host is available.
3. Create the Homebrew cask repository entry only after a signed release artifact is available.
4. Keep the original Juicer repository as the Juicer bundle source and link to BrewStore from its README.
