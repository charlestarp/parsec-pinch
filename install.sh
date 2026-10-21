#!/bin/bash
# parsec-pinch installer. Works piped from curl or from a checkout.
#
#   On the Mac you connect TO (the host):
#     curl -fsSL https://raw.githubusercontent.com/charlestarp/parsec-pinch/main/install.sh | bash -s -- host
#
#   On the laptop you connect FROM (the client), using the line the host step prints:
#     curl -fsSL https://raw.githubusercontent.com/charlestarp/parsec-pinch/main/install.sh | bash -s -- client --token <token> --host <address> [--host <address2>]
#
# Safe to re-run. Keeps an existing token on the host. Only appends to ~/.hammerspoon/init.lua if its lines are missing.

set -u

REPO_RAW="https://raw.githubusercontent.com/charlestarp/parsec-pinch/main"
HS_DIR="$HOME/.hammerspoon"
DEST="$HS_DIR/parsec-pinch"
CONFIG="$HS_DIR/parsec-pinch-config.lua"
INIT="$HS_DIR/init.lua"
PORT=47801

say() { printf '%s\n' "$*"; }
die() { say "error: $*"; exit 1; }

ROLE="${1:-}"
[ $# -gt 0 ] && shift
TOKEN=""
HOSTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --token) TOKEN="${2:-}"; shift 2 ;;
    --host)  HOSTS+=("${2:-}"); shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [ "$ROLE" != "host" ] && [ "$ROLE" != "client" ]; then
  say "usage:"
  say "  install.sh host"
  say "  install.sh client --token <token> --host <address> [--host <address2>]"
  exit 1
fi

[ "$(uname)" = "Darwin" ] || die "this only runs on macOS"

# 1. Hammerspoon. Homebrew if present, otherwise the official release zip.
if [ ! -d /Applications/Hammerspoon.app ]; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing Hammerspoon with Homebrew"
    brew install --cask hammerspoon || die "Homebrew could not install Hammerspoon"
  else
    say "Downloading Hammerspoon"
    TMP=$(mktemp -d)
    URL=$(curl -fsSL https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest \
          | grep browser_download_url | grep -E 'Hammerspoon-[0-9.]+\.zip' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')
    [ -n "$URL" ] || die "could not find the Hammerspoon download. Install it from https://www.hammerspoon.org and re-run."
    curl -fsSL "$URL" -o "$TMP/hs.zip" || die "download failed"
    ditto -xk "$TMP/hs.zip" "$TMP/" || die "unzip failed"
    [ -d "$TMP/Hammerspoon.app" ] || die "zip did not contain Hammerspoon.app"
    ditto "$TMP/Hammerspoon.app" /Applications/Hammerspoon.app || die "could not copy to /Applications"
    xattr -dr com.apple.quarantine /Applications/Hammerspoon.app 2>/dev/null || true
    rm -rf "$TMP"
  fi
fi
[ -d /Applications/Hammerspoon.app ] || die "Hammerspoon is not in /Applications"

# 2. The lua files: from a checkout if we are in one, otherwise from GitHub.
mkdir -p "$DEST" || die "cannot create $DEST"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || true)"
for f in init.lua client.lua host.lua; do
  if [ -n "$SRC" ] && [ -f "$SRC/$f" ]; then
    cp "$SRC/$f" "$DEST/$f"
  else
    curl -fsSL "$REPO_RAW/$f" -o "$DEST/$f" || die "could not download $f"
  fi
done

# 3. Config
if [ "$ROLE" = "host" ]; then
  if [ -z "$TOKEN" ] && [ -f "$CONFIG" ]; then
    TOKEN=$(sed -n 's/.*token *= *"\([^"]*\)".*/\1/p' "$CONFIG" | head -1)
  fi
  [ -n "$TOKEN" ] || TOKEN=$(openssl rand -hex 8 2>/dev/null || date +%s%N | shasum | cut -c1-16)
  cat > "$CONFIG" <<EOF
return {
  role = "host",
  token = "$TOKEN",
  port = $PORT,
}
EOF
else
  [ -n "$TOKEN" ] || die "client needs --token <token> (printed by the host install)"
  [ ${#HOSTS[@]} -gt 0 ] || die "client needs at least one --host <address>"
  HOST_LIST=""
  for h in "${HOSTS[@]}"; do [ -n "$h" ] && HOST_LIST="$HOST_LIST\"$h\", "; done
  cat > "$CONFIG" <<EOF
return {
  role = "client",
  hosts = { ${HOST_LIST%, } },
  token = "$TOKEN",
  port = $PORT,
  scale = 1.0,
  apps = { "tv.parsec.www" },
  fallback = true,
  fallback_keys = { zoom_in = "=", zoom_out = "-" },
  toggle_hotkey = { mods = { "ctrl", "alt", "cmd" }, key = "z" },
}
EOF
fi

# 4. Hook into Hammerspoon's init.lua
touch "$INIT" || die "cannot write $INIT"
grep -q 'require("hs.ipc")' "$INIT" || echo 'require("hs.ipc")' >> "$INIT"
grep -q 'parsec-pinch/init.lua' "$INIT" || \
  echo 'parsecPinch = dofile(os.getenv("HOME") .. "/.hammerspoon/parsec-pinch/init.lua")' >> "$INIT"

# 5. Start or reload Hammerspoon
HS=""
for c in /opt/homebrew/bin/hs /usr/local/bin/hs; do [ -x "$c" ] && HS="$c" && break; done
if pgrep -x Hammerspoon >/dev/null; then
  if [ -n "$HS" ] && "$HS" -c 'hs.reload()' >/dev/null 2>&1; then :
  else
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
    sleep 2
    open /Applications/Hammerspoon.app
  fi
else
  open /Applications/Hammerspoon.app
fi

say ""
say "Installed as $ROLE."
say "If macOS asks, allow Hammerspoon under System Settings > Privacy and Security > Accessibility."
say "Nothing works until that is on."

if [ "$ROLE" = "host" ]; then
  TS=""
  if command -v tailscale >/dev/null 2>&1; then TS=$(tailscale ip -4 2>/dev/null | head -1)
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then TS=$(/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4 2>/dev/null | head -1); fi
  LAN=""
  for ifc in en0 en1 en2; do a=$(ipconfig getifaddr "$ifc" 2>/dev/null); [ -n "$a" ] && LAN="$a" && break; done
  ADDRS=""
  [ -n "$TS" ] && ADDRS="$ADDRS --host $TS"
  [ -n "$LAN" ] && ADDRS="$ADDRS --host $LAN"
  say ""
  say "This Mac's addresses:"
  [ -n "$TS" ] && say "  Tailscale: $TS   (best: works from any network)"
  [ -n "$LAN" ] && say "  Local:     $LAN  (only on this Wi-Fi or LAN)"
  [ -z "$TS" ] && say "  No Tailscale found. For use from other networks, install it from https://tailscale.com on both Macs and re-run this."
  say ""
  say "Now run this ONE line on your laptop:"
  say ""
  say "  curl -fsSL $REPO_RAW/install.sh | bash -s -- client --token $TOKEN${ADDRS:- --host <address-of-this-Mac>}"
  say ""
else
  say "Connect with Parsec and pinch. Toggle with Ctrl+Alt+Cmd+Z."
fi
