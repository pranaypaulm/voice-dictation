# voice-dictation

**Press a hotkey, speak, and the words appear in whatever app you're using.** Linux, system-wide, no cloud account required for the offline engine.

Built for coding agents (opencode, Claude Code, aider) but works anywhere a text field exists — browsers, Slack, VS Code, terminals, notes.

```
Super+Alt+V   🎤 listening…            (speak)
Super+Alt+V   "refactor the auth middleware and add tests"   → typed into the focused field
```

## Features

- **Global hotkey** — toggle recording from any app; text goes to the focused window.
- **Two engines**
  - **Cloud (default):** [Groq](https://console.groq.com/keys) `whisper-large-v3-turbo` — ~0.3–1 s, excellent punctuation, near-zero CPU. Free tier, no card.
  - **Offline:** whisper.cpp + `base.en` — no network, no API key, works on a plane.
  - Automatic fallback: cloud fails/quota/offline → local, without losing the take.
- **Multi-desktop typing** — GNOME Wayland (no root), wlroots/KDE Wayland, X11.
- **No Enter sent** — you always get to edit before submitting.
- **Quiet by default** — one transient toast that is replaced in place, never a stack of
  notifications in the tray. Set `"notify": "off"` for total silence.
- **Tiny codebase** — one CLI, one injector, stdlib + `python3-gi`. No daemon.

## Requirements

| Need | Why |
|---|---|
| Linux, X11 or Wayland | obviously |
| `parecord` (pipewire or pulseaudio-utils) | microphone capture |
| `notify-send` (libnotify) | "listening…" feedback |
| `python3` + `python3-gi` | D-Bus typing on GNOME |
| one typing backend | GNOME Mutter (built in), `wtype`, `ydotool`, or `xdotool` |

```bash
# Debian / Ubuntu
sudo apt install python3-gi gir1.2-glib-2.0 libnotify-bin pulseaudio-utils

# Arch
sudo pacman -S python-gobject libnotify libpulse

# Fedora
sudo dnf install python3-gobject libnotify pulseaudio-utils

# KDE / wlroots Wayland also need:
sudo apt install wtype        # or ydotool
```

## Install

```bash
git clone https://github.com/pranaypaulm/voice-dictation.git
cd voice-dictation
./install.sh              # cloud engine only (recommended)
# ./install.sh --local    # + whisper.cpp and base.en (~200 MB, CPU-heavy)
```

`install.sh` symlinks `bin/voice` into `~/.local/bin` and binds `Super+Alt+V` in GNOME.

Then add a free Groq key:

```bash
voice --set-key          # prompts, stores in ~/.config/voice-input/config.json (chmod 600)
```

Get one at <https://console.groq.com/keys>.

## Usage

```bash
voice                    # toggle (this is what the hotkey runs)
voice start | stop       # explicit control
voice cancel             # throw the take away
voice status             # listening | idle

voice --no-type          # transcribe and print, don't touch the keyboard
voice --file take.wav    # transcribe a file
voice --lang hi          # other languages (cloud engine)
voice --engine local     # force offline
voice --notify off       # no popups at all, not even errors
voice --model small.en   # offline model (after ./install.sh --local)
```

The last transcript is kept at `$XDG_RUNTIME_DIR/voice-input/last.txt`.

## How it works

```
hotkey ─► voice ─► parecord (16 kHz mono WAV)
                     │
                     ├─ cloud: POST multipart → Groq /audio/transcriptions
                     └─ local: nice whisper-cli -t $(cores/2)
                     │
                     ▼
             lib/inject.py ─► focused window
```

`lib/inject.py` picks the first backend that works:

| Backend | Session | Root needed | Notes |
|---|---|---|---|
| `gnome` | GNOME Wayland | no | `org.gnome.Mutter.RemoteDesktop` D-Bus, keysym per char |
| `wtype` | wlroots / KDE Wayland | no | virtual-keyboard protocol |
| `ydotool` | any | usually | needs `ydotoold` + uinput |
| `xdotool` | X11 / XWayland | no | XTEST |

Check what yours will use: `python3 lib/inject.py --list`.

## Configuration

`~/.config/voice-input/config.json`:

```json
{
  "groq_api_key": "gsk_...",
  "language": "en",
  "local_model": "base.en",
  "notify": "minimal"
}
```

Environment overrides: `GROQ_API_KEY`, `VOICE_LANG`, `VOICE_ENGINE`, `VOICE_MODEL`, `VOICE_NOTIFY`, `VOICE_HOME` (where models live), `VOICE_GROQ_URL` (point at any OpenAI-compatible `/audio/transcriptions` server, e.g. your own faster-whisper).

## Notifications

`notify` has three modes:

| Mode | Behaviour |
|---|---|
| `minimal` *(default)* | one **transient** toast (`--transient -r <id>`), replaced in place and auto-dismissed — it never enters the notification center, and there is no transcript preview because you can already see the text |
| `full` | persistent toasts for listening / transcribing / transcript, like a chatty app |
| `errors` | only failures notify |
| `off` | **silent** — nothing is sent to the notification daemon at all |

```bash
voice --notify off        # one-off
```

To make it permanent, set it in `~/.config/voice-input/config.json`:

```json
{ "notify": "off" }
```

If your tray is already full of old entries, clear it once with **Super+N** → *Clear*.

## Privacy

- **Offline engine:** nothing leaves the machine.
- **Cloud engine:** the recorded WAV is uploaded to Groq for transcription. Don't use it for audio you can't share. The key stays local, mode 600.

## Limitations

- GNOME/X11 backends type **ASCII only** (unicode is folded: `café` → `cafe`). `wtype`/`xdotool` handle more.
- It types into the **focused** window — don't switch apps mid-dictation.
- Toggle model, not push-to-talk (compositor shortcuts don't fire on key release).
- Cloud free tier is rate-limited per minute; long monologues may hit it.

## Troubleshooting

| Symptom | Check |
|---|---|
| nothing typed | `voice --no-type` (does it transcribe?) then `python3 lib/inject.py --list` |
| "nothing recorded" | `pactl list short sources`; test `parecord --file-format=wav /tmp/t.wav` |
| no "listening" toast | install `libnotify-bin` |
| shortcut does nothing | Settings → Keyboard → Custom Shortcuts → "Voice dictation" |
| cloud 401/429 | re-run `voice --set-key`; free-tier quota resets per minute/day |

## Contributing

Issues and PRs welcome. Good first issues:

- push-to-talk (evdev/uinput listener)
- streaming transcription with partial results
- unicode paste-mode (clipboard + Ctrl+V)
- Windows/macOS backends
- packaging (AUR, Flatpak)

## License

MIT — see [LICENSE](LICENSE).
