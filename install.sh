#!/usr/bin/env bash
# Voice Dictation — installer
#
#   ./install.sh              # cloud engine only (small, fast, no models)
#   ./install.sh --local      # also build whisper.cpp + base.en for offline use
#   ./install.sh --no-hotkey  # skip creating the GNOME shortcut
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VOICE_HOME="${VOICE_HOME:-$HOME/.local/share/voice-input}"
BIN_DIR="$HOME/.local/bin"
HOTKEY="${HOTKEY:-<Super><Alt>v}"
WITH_LOCAL=0
WITH_HOTKEY=1
LANG_OPT="${VOICE_LANG:-en}"

for arg in "$@"; do
  case "$arg" in
    --local) WITH_LOCAL=1 ;;
    --no-hotkey) WITH_HOTKEY=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- dependencies
say "Checking dependencies"
missing=()
have() { command -v "$1" >/dev/null 2>&1; }

have python3        || missing+=("python3")
have parecord       || missing+=("parecord (pipewire/pulseaudio-utils)")
have notify-send    || missing+=("notify-send (libnotify-bin)")
python3 -c "import gi" 2>/dev/null || missing+=("python3-gi (GNOME backend)")

if [ ${#missing[@]} -gt 0 ]; then
  warn "missing: ${missing[*]}"
  echo "  Debian/Ubuntu: sudo apt install python3-gi gir1.2-glib-2.0 libnotify-bin pulseaudio-utils"
  echo "  Arch:          sudo pacman -S python-gobject libnotify libpulse"
  echo "  Fedora:        sudo dnf install python3-gobject libnotify pulseaudio-utils"
  echo
  echo "Continuing — the tool will tell you what is missing at runtime."
fi

# ---------------------------------------------------------------- install CLI
say "Installing CLI"
mkdir -p "$BIN_DIR"
chmod +x "$HERE/bin/voice" "$HERE/lib/inject.py"
ln -sf "$HERE/bin/voice" "$BIN_DIR/voice"
echo "  $BIN_DIR/voice -> $HERE/bin/voice"

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not in your PATH — add: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ---------------------------------------------------------------- hotkey
if [ "$WITH_HOTKEY" = "1" ] && command -v gsettings >/dev/null 2>&1 && \
   echo "${XDG_CURRENT_DESKTOP:-}" | grep -qi gnome; then
  say "Creating GNOME shortcut ($HOTKEY)"
  python3 - "$BIN_DIR/voice" "$HOTKEY" <<'PY'
import subprocess, sys
exe, key = sys.argv[1], sys.argv[2]
SCHEMA = "org.gnome.settings-daemon.plugins.media-keys"
PATH_ = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voice-input/"
def get(k):
    return subprocess.run(["gsettings", "get", SCHEMA, k],
                          capture_output=True, text=True).stdout.strip()
cur = get("custom-keybindings")
paths = []
if cur and cur != "@as []":
    paths = [p.strip().strip("',\"") for p in cur.strip("[]").split(",") if p.strip()]
if PATH_ not in paths:
    paths.append(PATH_)
    subprocess.run(["gsettings", "set", SCHEMA, "custom-keybindings",
                    "[" + ", ".join(f"'{p}'" for p in paths) + "]"], check=True)
sub = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:" + PATH_
for k, v in (("name", "Voice dictation"), ("command", exe), ("binding", key)):
    subprocess.run(["gsettings", "set", sub, k, v], check=True)
print("  bound", key, "->", exe)
PY
else
  [ "$WITH_HOTKEY" = "1" ] && warn "not a GNOME session — bind a shortcut manually to: $BIN_DIR/voice"
fi

# ---------------------------------------------------------------- local engine
if [ "$WITH_LOCAL" = "1" ]; then
  say "Building offline engine (whisper.cpp) — this takes a few minutes"
  mkdir -p "$VOICE_HOME/models"
  if [ ! -d "$VOICE_HOME/whisper.cpp" ]; then
    git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$VOICE_HOME/whisper.cpp"
  fi
  cmake -S "$VOICE_HOME/whisper.cpp" -B "$VOICE_HOME/whisper.cpp/build" \
        -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF >/dev/null
  cmake --build "$VOICE_HOME/whisper.cpp/build" -j 2 --target whisper-cli >/dev/null
  MODEL="ggml-base.en.bin"
  if [ ! -f "$VOICE_HOME/models/$MODEL" ]; then
    echo "  downloading $MODEL (~142 MB)"
    curl -L --fail -o "$VOICE_HOME/models/$MODEL" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL"
  fi
  echo "  local engine ready in $VOICE_HOME"
fi

# ---------------------------------------------------------------- done
cat <<EOF

$(printf '\033[1mInstalled.\033[0m')

  1. Add a speech engine key (free, no card):
       https://console.groq.com/keys
       voice --set-key

  2. Press ${HOTKEY} in any app, speak, press it again.

  voice status              # listening | idle
  voice --no-type           # transcribe without typing
  voice --engine local      # force offline (needs ./install.sh --local)
EOF
