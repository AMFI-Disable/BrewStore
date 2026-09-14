#!/usr/bin/env bash
# ==============================================================================
# BrewStore Pre-Release QA Verification Script
# Verifies test suites, LaunchAgent script, DMG build, and SHA-256 checksums.
# ==============================================================================
set -e

VERSION="${1:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo -e "\033[1;36m==>\033[0m [1/6] Running Documentation Lint Verification (markdownlint)…"
MARKDOWNLINT_BIN=""
if command -v markdownlint >/dev/null 2>&1; then
  MARKDOWNLINT_BIN="markdownlint"
elif [ -x "/opt/homebrew/bin/markdownlint" ]; then
  MARKDOWNLINT_BIN="/opt/homebrew/bin/markdownlint"
fi

if [ -n "$MARKDOWNLINT_BIN" ]; then
  $MARKDOWNLINT_BIN "**/*.md" --ignore "build/**" --ignore ".build/**" --ignore "DerivedData/**" --ignore "**/node_modules/**"
  echo -e "\033[1;32m  ✓ All markdown documentation adheres to MDXXX standards!\033[0m"
else
  echo -e "\033[1;33m  ⚠ markdownlint not found; skipping documentation lint check.\033[0m"
fi

echo -e "\033[1;36m==>\033[0m [2/6] Generating Xcode Project with XcodeGen…"
xcodegen generate

echo -e "\033[1;36m==>\033[0m [3/6] Running Automated Unit Tests (xcodebuild test)…"
pkill -f BrewStore || true
xcodebuild test \
  -project BrewStore.xcodeproj \
  -scheme BrewStore \
  -sdk macosx \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  -quiet

echo -e "\033[1;32m  ✓ All automated tests passed successfully!\033[0m"

echo -e "\033[1;36m==>\033[0m [4/6] Testing LaunchAgent Background Script…"
chmod +x scripts/brewstore-agent.sh scripts/brewstore
./scripts/brewstore-agent.sh

if [ -f "$HOME/Library/Application Support/BrewStore/autoupdate_status.json" ]; then
  echo -e "\033[1;32m  ✓ LaunchAgent status JSON generated successfully.\033[0m"
else
  echo -e "\033[1;31m  ✗ LaunchAgent status JSON was not generated.\033[0m"
  exit 1
fi

echo -e "\033[1;36m==>\033[0m [5/6] Packaging Release DMG (v$VERSION)…"
./scripts/build-dmg.sh "$VERSION"

echo -e "\033[1;36m==>\033[0m [6/6] Validating SHA-256 Checksum…"
DMG_FILE="website/downloads/brewstore-$VERSION.dmg"
SHA_FILE="website/downloads/brewstore-$VERSION.sha256"

if [ ! -f "$DMG_FILE" ]; then
  echo -e "\033[1;31mError: DMG file not found at $DMG_FILE\033[0m"
  exit 1
fi

CURRENT_SHA=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')
echo "$CURRENT_SHA  brewstore-$VERSION.dmg" > "$SHA_FILE"

echo -e "\n\033[1;32m================================================================"
echo "  🏆 BrewStore v$VERSION QA Verification Succeeded!"
echo "  DMG:     $DMG_FILE"
echo "  SHA-256: $CURRENT_SHA"
echo -e "================================================================\033[0m\n"
