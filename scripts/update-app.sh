#!/usr/bin/env bash
# ==============================================================================
# BrewStore Application Deployment & Update Script
# Builds the specified configuration, gracefully halts existing instances,
# installs to /Applications/BrewStore.app, clears quarantine, and launches it.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Colors & Formatting
# ------------------------------------------------------------------------------
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# Defaults & Arguments
# ------------------------------------------------------------------------------
CONFIGURATION="Release"
SKIP_BUILD=false
LAUNCH_APP=true
CLEAN_BUILD=false
QUIET=false

print_usage() {
  cat <<USAGE_EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

${BOLD}Options:${NC}
  -c, --configuration <Release|Debug>  Build configuration (default: Release)
  -s, --skip-build                     Skip building and deploy existing app
  -n, --no-launch                      Do not launch BrewStore after installing
      --clean                          Clean build artifacts before building
  -q, --quiet                          Quiet output during compilation
  -h, --help                           Show this help message

${BOLD}Examples:${NC}
  $(basename "$0")                     # Standard Release build and update
  $(basename "$0") --skip-build        # Fast deploy from recent build
  $(basename "$0") -c Debug            # Deploy Debug build
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    -s|--skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -n|--no-launch)
      LAUNCH_APP=false
      shift
      ;;
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown argument '$1'${NC}" >&2
      print_usage
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_DEST="/Applications/BrewStore.app"
BUILD_ROOT="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_ROOT/deriveddata"

echo -e "\n${BOLD}================================================================${NC}"
echo -e "  🍺 ${BOLD}BrewStore Deployment to /Applications${NC}"
echo -e "  Configuration: ${CYAN}${CONFIGURATION}${NC}"
echo -e "  Skip Build:    ${CYAN}${SKIP_BUILD}${NC}"
echo -e "  Auto-Launch:   ${CYAN}${LAUNCH_APP}${NC}"
echo -e "${BOLD}================================================================${NC}\n"

# ------------------------------------------------------------------------------
# Step 1: Ensure Xcode Project Is Synchronized
# ------------------------------------------------------------------------------
echo -e "${CYAN}==>${NC} [1/5] Checking Xcode project configuration..."
XCODEGEN_BIN="$(command -v xcodegen 2>/dev/null || echo "/opt/homebrew/bin/xcodegen")"

if [[ -x "$XCODEGEN_BIN" ]]; then
  if [[ ! -d "BrewStore.xcodeproj" || "project.yml" -nt "BrewStore.xcodeproj" ]]; then
    echo -e "  Regenerating Xcode project from project.yml..."
    "$XCODEGEN_BIN" generate --quiet 2>/dev/null || "$XCODEGEN_BIN" generate
  fi
  echo -e "${GREEN}  ✓ Xcode project is up to date.${NC}"
elif [[ ! -d "BrewStore.xcodeproj" ]]; then
  echo -e "${RED}Error: BrewStore.xcodeproj not found and xcodegen not installed.${NC}" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Build Application (unless skipped)
# ------------------------------------------------------------------------------
TARGET_APP=""

if [[ "$SKIP_BUILD" == false ]]; then
  echo -e "${CYAN}==>${NC} [2/5] Building BrewStore (${CONFIGURATION})..."

  if [[ "$CLEAN_BUILD" == true ]]; then
    echo -e "  Cleaning previous build artifacts..."
    rm -rf "$DERIVED_DATA"
  fi

  XCODEBUILD_ARGS=(
    -project "BrewStore.xcodeproj"
    -scheme "BrewStore"
    -configuration "$CONFIGURATION"
    -destination "platform=macOS,arch=arm64"
    -derivedDataPath "$DERIVED_DATA"
    build
  )

  if [[ "$QUIET" == true ]]; then
    xcodebuild "${XCODEBUILD_ARGS[@]}" -quiet
  else
    xcodebuild "${XCODEBUILD_ARGS[@]}"
  fi

  TARGET_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/BrewStore.app"
else
  echo -e "${CYAN}==>${NC} [2/5] Locating existing BrewStore build (skip-build requested)..."

  # Search local derived data first, then system DerivedData
  CANDIDATES=(
    "$DERIVED_DATA/Build/Products/$CONFIGURATION/BrewStore.app"
    "$HOME/Library/Developer/Xcode/DerivedData"/BrewStore-*/Build/Products/"$CONFIGURATION"/BrewStore.app
  )

  for candidate in "${CANDIDATES[@]}"; do
    if [[ -d "$candidate" && -f "$candidate/Contents/MacOS/BrewStore" ]]; then
      TARGET_APP="$candidate"
      break
    fi
  done
fi

if [[ -z "$TARGET_APP" || ! -d "$TARGET_APP" || ! -f "$TARGET_APP/Contents/MacOS/BrewStore" ]]; then
  echo -e "${RED}Error: Could not find compiled BrewStore.app at expected locations.${NC}" >&2
  echo -e "Run without --skip-build to compile a fresh binary." >&2
  exit 1
fi

echo -e "${GREEN}  ✓ Found built app at:${NC} $TARGET_APP"

# ------------------------------------------------------------------------------
# Step 3: Gracefully Stop Existing BrewStore Process
# ------------------------------------------------------------------------------
echo -e "${CYAN}==>${NC} [3/5] Checking for active BrewStore instances..."
EXISTING_PID="$(pgrep -x BrewStore 2>/dev/null || true)"

if [[ -n "$EXISTING_PID" ]]; then
  echo -e "  Gracefully stopping BrewStore (PID: $EXISTING_PID)..."
  pkill -x BrewStore 2>/dev/null || true

  # Wait up to 3 seconds for clean exit
  for _ in {1..30}; do
    if ! pgrep -x BrewStore >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  # Force kill if still holding file locks
  if pgrep -x BrewStore >/dev/null 2>&1; then
    echo -e "  Forcing termination of stubborn process..."
    pkill -9 -x BrewStore 2>/dev/null || true
    sleep 0.2
  fi
  echo -e "${GREEN}  ✓ Existing process stopped.${NC}"
else
  echo -e "${GREEN}  ✓ No running BrewStore instance found.${NC}"
fi

# ------------------------------------------------------------------------------
# Step 4: Install to /Applications/BrewStore.app
# ------------------------------------------------------------------------------
echo -e "${CYAN}==>${NC} [4/5] Installing to $APP_DEST..."

# Remove previous installation cleanly
rm -rf "$APP_DEST"

# Use ditto to accurately preserve permissions, symlinks, and code signature
ditto "$TARGET_APP" "$APP_DEST"

# Clear quarantine flags
xattr -cr "$APP_DEST" 2>/dev/null || true

# Validate signature
if codesign --verify --deep --strict "$APP_DEST" 2>/dev/null; then
  echo -e "${GREEN}  ✓ Code signature verified (strict).${NC}"
else
  # Re-sign ad-hoc with entitlements if needed
  ENTITLEMENTS="sources/resources/brewstore.entitlements"
  if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign - -o runtime --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_DEST" 2>/dev/null || true
  else
    codesign --force --sign - "$APP_DEST" 2>/dev/null || true
  fi
  echo -e "${GREEN}  ✓ Re-signed ad-hoc locally.${NC}"
fi

echo -e "${GREEN}  ✓ Successfully installed to $APP_DEST.${NC}"

# ------------------------------------------------------------------------------
# Step 5: Launch & Verify (unless --no-launch)
# ------------------------------------------------------------------------------
if [[ "$LAUNCH_APP" == true ]]; then
  echo -e "${CYAN}==>${NC} [5/5] Launching BrewStore from /Applications..."
  open "$APP_DEST"

  # Verify process started
  NEW_PID=""
  for _ in {1..30}; do
    NEW_PID="$(pgrep -x BrewStore 2>/dev/null || true)"
    if [[ -n "$NEW_PID" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ -n "$NEW_PID" ]]; then
    echo -e "${GREEN}  ✓ BrewStore launched successfully! (PID: ${NEW_PID})${NC}"
  else
    echo -e "${YELLOW}  ⚠ App was launched via open, but PID could not be immediately detected.${NC}"
  fi
else
  echo -e "${CYAN}==>${NC} [5/5] Skipping application launch (--no-launch specified)."
fi

echo -e "\n${GREEN}================================================================${NC}"
echo -e "  🎉 ${BOLD}BrewStore update complete!${NC}"
echo -e "  Location: ${CYAN}$APP_DEST${NC}"
echo -e "  Binary:   ${CYAN}$APP_DEST/Contents/MacOS/BrewStore${NC}"
echo -e "${GREEN}================================================================${NC}\n"
