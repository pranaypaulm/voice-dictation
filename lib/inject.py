#!/usr/bin/env python3
"""Type text into the focused window on Linux.

Backends (auto-detected, first available wins):
  gnome     org.gnome.Mutter.RemoteDesktop D-Bus  (GNOME Wayland, no root)
  wtype     wlroots virtual-keyboard protocol      (sway/Hyprland/KDE Wayland)
  ydotool   uinput, needs ydotoold                 (any Wayland/X11, often root)
  xdotool   XTEST                                  (X11 / XWayland)

Usage:
  inject.py "text here"
  inject.py --print "text"          # show what would be typed (normalisation)
  inject.py --backend wtype "text"
  inject.py --list                  # show detected backends
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
import unicodedata

# whisper likes to emit typographic punctuation / unicode spaces
REPLACE = {
    "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
    "\u2013": "-", "\u2014": "-", "\u2026": "...", "\u00a0": " ",
    "\u2011": "-", "\u00ad": "", "\u2212": "-", "\u00d7": "x",
}

DBUS_DEST = "org.gnome.Mutter.RemoteDesktop"
DBUS_OBJ = "/org/gnome/Mutter/RemoteDesktop"
DBUS_IFACE = "org.gnome.Mutter.RemoteDesktop.Session"


# --------------------------------------------------------------------------- #
# text helpers
# --------------------------------------------------------------------------- #
def normalize_ascii(text: str) -> str:
    """Fold unicode punctuation/accents down to ASCII (needed by keysym typing)."""
    out = []
    for ch in text:
        if ch in REPLACE:
            out.append(REPLACE[ch])
        elif ch in "\n\r\t":
            out.append(" ")
        elif ord(ch) < 128:
            out.append(ch)
        else:
            decomposed = unicodedata.normalize("NFKD", ch)
            out.append("".join(c for c in decomposed if ord(c) < 128))
    return "".join(out)


def is_ascii(text: str) -> bool:
    return all(ord(c) < 128 for c in text)


# --------------------------------------------------------------------------- #
# backends
# --------------------------------------------------------------------------- #
def _load_gi():
    try:
        import gi  # noqa: F401
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        return Gio, GLib
    except Exception:
        return None, None


def gnome_available() -> bool:
    Gio, GLib = _load_gi()
    if not Gio:
        return False
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus", "NameHasOwner",
                      GLib.Variant("(s)", (DBUS_DEST,)), GLib.VariantType.new("(b)"),
                      Gio.DBusCallFlags.NONE, 2000, None)
        return True
    except Exception:
        return False


def type_gnome(text: str, delay: float = 0.0025) -> int:
    Gio, GLib = _load_gi()
    if not Gio:
        raise RuntimeError("python3-gi is required for the GNOME backend")
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    sess = bus.call_sync(
        DBUS_DEST, DBUS_OBJ, DBUS_DEST, "CreateSession", None,
        GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 5000, None,
    ).unpack()[0]
    bus.call_sync(DBUS_DEST, sess, DBUS_IFACE, "Start", None, None,
                  Gio.DBusCallFlags.NONE, 5000, None)
    special = {"\n": 0xFF0D, "\t": 0xFF09, " ": 0x20}
    sent = 0
    try:
        for ch in text:
            ks = special.get(ch, ord(ch))
            for state in (True, False):
                bus.call_sync(DBUS_DEST, sess, DBUS_IFACE, "NotifyKeyboardKeysym",
                              GLib.Variant("(ub)", (ks, state)), None,
                              Gio.DBusCallFlags.NONE, 5000, None)
                if delay:
                    time.sleep(delay)
            sent += 1
    finally:
        try:
            bus.call_sync(DBUS_DEST, sess, DBUS_IFACE, "Stop", None, None,
                          Gio.DBusCallFlags.NONE, 2000, None)
        except Exception:
            pass
    return sent


def type_wtype(text: str) -> int:
    subprocess.run(["wtype", "--", text], check=True)
    return len(text)


def type_ydotool(text: str) -> int:
    subprocess.run(["ydotool", "type", "--delay", "2", "--", text], check=True)
    return len(text)


def type_xdotool(text: str) -> int:
    subprocess.run(["xdotool", "type", "--clearmodifiers", "--delay", "2", "--", text],
                   check=True)
    return len(text)


BACKENDS = {
    "gnome": (gnome_available, type_gnome),
    "wtype": (lambda: shutil.which("wtype") is not None, type_wtype),
    "ydotool": (lambda: shutil.which("ydotool") is not None, type_ydotool),
    "xdotool": (lambda: shutil.which("xdotool") is not None
                and bool(os.environ.get("DISPLAY")), type_xdotool),
}


def detect() -> list[str]:
    return [name for name, (avail, _) in BACKENDS.items() if _safe(avail)]


def _safe(fn) -> bool:
    try:
        return bool(fn())
    except Exception:
        return False


def type_text(text: str, backend: str | None = None) -> tuple[str, int]:
    available = detect()
    if not available:
        raise RuntimeError(
            "no typing backend found. On GNOME install python3-gi; on KDE/wlroots "
            "install wtype; on X11 install xdotool; or install ydotool."
        )
    if backend:
        if backend not in BACKENDS:
            raise RuntimeError(f"unknown backend '{backend}' (have: {', '.join(BACKENDS)})")
        if backend not in available:
            raise RuntimeError(f"backend '{backend}' is not available on this system")
        name = backend
    else:
        name = available[0]

    fn = BACKENDS[name][1]
    if name == "gnome" and not is_ascii(text):
        # keysym typing is ASCII-only; fold rather than send garbage
        text = normalize_ascii(text)
    return name, fn(text)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv: list[str]) -> int:
    args = list(argv)
    if "--list" in args:
        avail = detect()
        print("available:", ", ".join(avail) if avail else "none")
        for name in BACKENDS:
            print(f"  {'✓' if name in avail else '✗'} {name}")
        return 0
    dry = "--print" in args
    args = [a for a in args if a != "--print"]
    backend = None
    if "--backend" in args:
        i = args.index("--backend")
        try:
            backend = args[i + 1]
            del args[i:i + 2]
        except IndexError:
            raise SystemExit("--backend needs a value")
    text = args[0] if args else sys.stdin.read()
    if dry:
        print(normalize_ascii(text))
        return 0
    if not text.strip():
        return 2
    name, n = type_text(text, backend)
    print(f"typed {n} chars via {name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
