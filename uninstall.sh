#!/usr/bin/env bash
# Remove the CLI, the GNOME shortcut and (optionally) downloaded models.
set -euo pipefail

VOICE_HOME="${VOICE_HOME:-$HOME/.local/share/voice-input}"
BIN="$HOME/.local/bin/voice"

echo "Removing CLI: $BIN"
rm -f "$BIN"

if command -v gsettings >/dev/null 2>&1; then
  SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
  KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voice-input/"
  SCHEMA_KEY="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH"
  gsettings reset-recursively "$SCHEMA_KEY" 2>/dev/null || true
  current="$(gsettings get "$SCHEMA" custom-keybindings 2>/dev/null || echo '@as []')"
  python3 - "$current" "$KEY_PATH" <<'PY' || true
import subprocess, sys
cur, drop = sys.argv[1], sys.argv[2]
paths = []
if cur and cur != "@as []":
    paths = [p.strip().strip("',\"") for p in cur.strip("[]").split(",") if p.strip()]
paths = [p for p in paths if p != drop]
subprocess.run(["gsettings", "set",
                "org.gnome.settings-daemon.plugins.media-keys", "custom-keybindings",
                "[" + ", ".join(f"'{p}'" for p in paths) + "]"], check=True)
print("removed shortcut")
PY
fi

echo "Removing config (API key):"
rm -rf "$HOME/.config/voice-input"

if [ -d "$VOICE_HOME" ]; then
  read -r -p "Also delete models/build in $VOICE_HOME? [y/N] " ans
  case "$ans" in
    [yY]*) rm -rf "$VOICE_HOME"; echo "deleted $VOICE_HOME" ;;
    *) echo "kept $VOICE_HOME" ;;
  esac
fi

echo "Done."
