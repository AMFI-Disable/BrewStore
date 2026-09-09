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

# Parse JSON using python3 or osascript
STATUS_OUTPUT=$(python3 -c '
import json, sys

try:
    data = json.loads(sys.argv[1])
    formulae = [f.get("name", "") for f in data.get("formulae", [])]
    casks = [c.get("name", "") for c in data.get("casks", [])]
    total = len(formulae) + len(casks)
    result = {
        "timestamp": sys.argv[2],
        "status": "success",
        "totalOutdated": total,
        "outdatedFormulae": formulae,
        "outdatedCasks": casks,
        "summary": f"{total} update(s) available" if total > 0 else "All packages up to date"
    }
    print(json.dumps(result, indent=2))
except Exception as e:
    result = {
        "timestamp": sys.argv[2],
        "status": "error",
        "errorMessage": str(e),
        "totalOutdated": 0,
        "outdatedFormulae": [],
        "outdatedCasks": []
    }
    print(json.dumps(result, indent=2))
' "$OUTDATED_JSON" "$TIMESTAMP" 2>> "$LOG_FILE")

echo "$STATUS_OUTPUT" > "$STATUS_FILE"
echo "[$(date)] Background check completed. Status recorded to $STATUS_FILE." >> "$LOG_FILE"

# Dispatch notification if outdated packages found
TOTAL_COUNT=$(python3 -c 'import json, sys; d=json.loads(sys.argv[1]); print(d.get("totalOutdated", 0))' "$STATUS_OUTPUT" 2>/dev/null || echo "0")

if [ "$TOTAL_COUNT" -gt 0 ]; then
  echo "[$(date)] Found $TOTAL_COUNT outdated packages. Posting user notification…" >> "$LOG_FILE"
  osascript -e "display notification \"$TOTAL_COUNT package(s) have available updates. Click to review in BrewStore.\" with title \"BrewStore Updates Available\"" 2>> "$LOG_FILE" || true
fi
