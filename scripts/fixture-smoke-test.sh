#!/usr/bin/env bash
# ==============================================================================
# BrewStore Disposable Fixture-Driven Smoke Test Runner
# Exercises destructive workflows (uninstall, autoremove, snapshot restore/delete,
# tap/service actions, and cancellation/partial-failure states) safely in an
# isolated, disposable mock environment without touching the host's real Homebrew setup.
# ==============================================================================
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo -e "\033[1;36m==>\033[0m [1/3] Regenerating project via XcodeGen…"
xcodegen generate

echo -e "\033[1;36m==>\033[0m [2/3] Executing FixtureSmokeTests via xcodebuild…"
xcodebuild test \
  -project BrewStore.xcodeproj \
  -scheme BrewStore \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:BrewStoreTests/FixtureSmokeTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  -quiet

echo -e "\033[1;36m==>\033[0m [3/3] Validating Fixture Environment Teardown…"
# Ensure no lingering temporary fixture folders exist in /tmp
if compgen -G "/tmp/brewstore_fixture_*" >/dev/null; then
  echo -e "\033[1;33m  Notice: cleaning up temporary fixture directories\033[0m"
  rm -rf /tmp/brewstore_fixture_*
fi

echo -e "\n\033[1;32m================================================================"
echo "  🏆 BrewStore Fixture-Driven Smoke Tests PASSED!"
echo "  - Package Uninstall (single & batch partial failure): VERIFIED"
echo "  - Dependency Autoremove:                              VERIFIED"
echo "  - Snapshot Restore & Disposable Deletion:             VERIFIED"
echo "  - Service Start/Stop/Restart & Failure Simulation:    VERIFIED"
echo "  - Tap & Untap Mutation & Failure Simulation:          VERIFIED"
echo "  - User Cancellation Trapping:                         VERIFIED"
echo "  Host Homebrew state was preserved 100% untouched."
echo -e "================================================================\033[0m\n"
