#!/usr/bin/env bash
# ==============================================================================
# BrewStore Background LaunchAgent Runner Script
# Runs quietly in background while BrewStore is closed.
# Strictly checks for updates (Upgrades are OFF by default).
# ==============================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1

BREW_BIN=$(command -v brew || echo "/opt/homebrew/bin/brew")
if [ ! -x "$BREW_BIN" ]; then
  if [ -x "/usr/local/bin/brew" ]; then
    BREW_BIN="/usr/local/bin/brew"
  fi
fi

APP_SUPPORT="$HOME/Library/Application Support/BrewStore"
mkdir -p "$APP_SUPPORT"
STATUS_FILE="$APP_SUPPORT/autoupdate_status.json"
LOG_DIR="$HOME/Library/Logs/BrewStore"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/autoupdate.log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[$(date)] Starting BrewStore background update check with $BREW_BIN…" >> "$LOG_FILE"

if [ ! -x "$BREW_BIN" ]; then
  echo "[$(date)] Error: Homebrew binary not found." >> "$LOG_FILE"
  cat <<EOF > "$STATUS_FILE"
{
  "timestamp": "$TIMESTAMP",
  "status": "error",
  "errorMessage": "Homebrew binary not found at /opt/homebrew or /usr/local",
  "totalOutdated": 0,
  "outdatedFormulae": [],
  "outdatedCasks": []
}
EOF
  exit 0
fi

# Run brew outdated in JSON format
OUTDATED_JSON=$("$BREW_BIN" outdated --json=v2 2>> "$LOG_FILE" || echo "{}")

# Parse JSON using native macOS JavaScriptCore (zero external python dependencies)
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
echo "[$(date)] Background check completed. Status recorded to $STATUS_FILE." >> "$LOG_FILE"

# Dispatch notification if outdated packages found
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
  echo "[$(date)] Found $TOTAL_COUNT outdated packages. Posting user notification…" >> "$LOG_FILE"
  osascript -e "display notification \"$TOTAL_COUNT package(s) have available updates. Click to review in BrewStore.\" with title \"BrewStore Updates Available\"" 2>> "$LOG_FILE" || true
fi
