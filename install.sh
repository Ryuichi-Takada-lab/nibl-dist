#!/bin/bash
# Nibl installer — downloads the ready-made app (no source code) and sets it up.
#   curl -fsSL https://raw.githubusercontent.com/OWNER/nibl/main/install.sh | bash
#   … | bash -s -- --uninstall
# Options (environment): NIBL_REPO=owner/name   NIBL_ZIP=/path/or/url.zip (for testing)
set -euo pipefail

REPO="${NIBL_REPO:-OWNER/nibl}"
APP_NAME="Nibl.app"
say()  { printf '\033[38;2;94;230;223m▌\033[0m %s\n' "$*"; }
fail() { printf '\033[38;2;255;107;139m✖ %s\033[0m\n' "$*" >&2; exit 1; }

target_dir() {
  if [ -n "${NIBL_DEST:-}" ]; then mkdir -p "$NIBL_DEST"; echo "$NIBL_DEST"; return; fi
  if [ -w /Applications ]; then echo /Applications; else mkdir -p "$HOME/Applications"; echo "$HOME/Applications"; fi
}

uninstall() {
  say "Removing Nibl…"
  pkill -x Nibl 2>/dev/null || true
  for d in /Applications "$HOME/Applications"; do rm -rf "$d/$APP_NAME"; done
  # Disconnect the agents: drop Nibl's hook entries, keep everything else
  for f in "$HOME/.claude/settings.json" "$HOME/.claude-personal/settings.json" "$HOME/.codex/hooks.json"; do
    [ -f "$f" ] || continue
    /usr/bin/osascript -l JavaScript - "$f" <<'JS' >/dev/null 2>&1 || true
function run(argv) {
  ObjC.import('Foundation');
  const path = argv[0];
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (text.isNil()) return;
  const j = JSON.parse(text.js);
  const h = j.hooks || {};
  if (!JSON.stringify(h).includes('nibl-hook')) return;   // nothing of Nibl's: leave the file as it is
  for (const ev of Object.keys(h)) {
    h[ev] = h[ev].map(e => ({ ...e, hooks: (e.hooks || []).filter(x => !String(x.command || '').includes('nibl-hook')) }))
                 .filter(e => e.hooks.length);
    if (!h[ev].length) delete h[ev];
  }
  if (Object.keys(h).length) j.hooks = h; else delete j.hooks;
  $(JSON.stringify(j, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}
JS
  done
  rm -rf "$HOME/.nibl/app"
  defaults delete dev.nibl.app >/dev/null 2>&1 || true
  say "Nibl removed. Your notes stay in ~/.nibl/notes.md."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

[ "$(uname)" = Darwin ] || fail "Nibl runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "Nibl needs macOS 15 or newer (you have $(sw_vers -productVersion))."
[ "$(uname -m)" = arm64 ] || fail "Nibl needs an Apple Silicon Mac."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ -n "${NIBL_ZIP:-}" ]; then
  src="$NIBL_ZIP"
else
  say "Looking for the latest Nibl…"
  src=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(http[^"]*\)"/\1/') \
        || fail "Couldn't reach GitHub. Check your internet connection."
  [ -n "$src" ] || fail "No release found in $REPO."
fi
say "Downloading…"
case "$src" in
  http*) curl -fL --progress-bar "$src" -o "$tmp/nibl.zip" ;;
  *) cp "$src" "$tmp/nibl.zip" ;;
esac
ditto -x -k "$tmp/nibl.zip" "$tmp/x"
app=$(find "$tmp/x" -maxdepth 3 -name "$APP_NAME" -type d | head -1)
[ -n "$app" ] || fail "The download doesn't contain $APP_NAME."

dest=$(target_dir)
say "Installing into ${dest}…"
[ -n "${NIBL_DEST:-}" ] || pkill -x Nibl 2>/dev/null || true
rm -rf "$dest/$APP_NAME"
ditto "$app" "$dest/$APP_NAME"
# Installed on purpose from the terminal: no "downloaded from the internet" block
xattr -dr com.apple.quarantine "$dest/$APP_NAME" 2>/dev/null || true

say "Starting Nibl — he'll show you around in the notch."
[ -n "${NIBL_NO_OPEN:-}" ] || open "$dest/$APP_NAME"
say "Done. To remove later: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall"
