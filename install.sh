#!/bin/bash
# Nibl installer — downloads the ready-made app (no source code) and sets it up.
#   curl -fsSL https://raw.githubusercontent.com/Ryuichi-Takada-lab/nibl-dist/main/install.sh | bash
#   … | bash -s -- --uninstall
# Options (environment): NIBL_REPO=owner/name   NIBL_ZIP=/path/or/url.zip (for testing)
#   NIBL_APP="Nibl Dev.app"  with NIBL_ZIP: install the Nibl Dev test copy instead of Nibl
set -euo pipefail

REPO="${NIBL_REPO:-Ryuichi-Takada-lab/nibl-dist}"
APP_NAME="${NIBL_APP:-Nibl.app}"   # NIBL_APP="Nibl Dev.app" installs the test copy next to Nibl
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
  local term="$HOME/.nibl/term"

  # Shell theme: the rc files go back to how they were, Terminal.app to its old profile
  [ -x "$term/bin/nibl" ] && bash "$term/bin/nibl" uninstall --quiet >/dev/null 2>&1 || true

  # The Claude Code mod, if the app installed it (a copy from anywhere else stays)
  for d in "$HOME/.claude" "$HOME/.claude-personal"; do
    [ -f "$d/settings.json" ] && grep -q "\"$term\"" "$d/settings.json" || continue
    if command -v claude >/dev/null; then
      CLAUDE_CONFIG_DIR="$d" claude plugin uninstall nibl@nibl >/dev/null 2>&1 || true
      CLAUDE_CONFIG_DIR="$d" claude plugin marketplace remove nibl >/dev/null 2>&1 || true
    fi
  done

  # Settings files: drop Nibl's agent hooks, the mod's entries, and put back the
  # status line and Claude Code theme Nibl replaced; keep everything else
  for f in "$HOME/.claude/settings.json" "$HOME/.claude-personal/settings.json" "$HOME/.codex/hooks.json"; do
    [ -f "$f" ] || continue
    /usr/bin/osascript -l JavaScript - "$f" "$term" <<'JS' >/dev/null 2>&1 || true
function run(argv) {
  ObjC.import('Foundation');
  const [path, term] = argv;
  const read = p => { const t = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null); return t.isNil() ? null : t.js; };
  const text = read(path);
  if (text === null) return;
  const j = JSON.parse(text);
  let changed = false;

  const h = j.hooks || {};
  if (JSON.stringify(h).includes('nibl-hook')) {
    for (const ev of Object.keys(h)) {
      h[ev] = h[ev].map(e => ({ ...e, hooks: (e.hooks || []).filter(x => !String(x.command || '').includes('nibl-hook')) }))
                   .filter(e => e.hooks.length);
      if (!h[ev].length) delete h[ev];
    }
    if (Object.keys(h).length) j.hooks = h; else delete j.hooks;
    changed = true;
  }

  const m = j.extraKnownMarketplaces && j.extraKnownMarketplaces.nibl;
  if (m && m.source && m.source.path === term) {
    delete j.extraKnownMarketplaces.nibl;
    if (!Object.keys(j.extraKnownMarketplaces).length) delete j.extraKnownMarketplaces;
    if (j.enabledPlugins) delete j.enabledPlugins['nibl@nibl'];
    changed = true;
  }

  if (j.statusLine && String(j.statusLine.command || '').includes('/.nibl/term/statusline.sh')) {
    const prev = read(term + '/state/prev-statusline.json');
    if (prev) j.statusLine = JSON.parse(prev); else delete j.statusLine;
    changed = true;
  }

  if (j.theme === 'custom:nibl') {
    const prev = read(term + '/state/prev-theme');
    if (prev) j.theme = prev; else delete j.theme;
    changed = true;
  }

  if (!changed) return;   // nothing of Nibl's: leave the file as it is
  $(JSON.stringify(j, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}
JS
  done
  for d in "$HOME/.claude" "$HOME/.claude-personal"; do rm -f "$d/themes/nibl.json"; done

  rm -rf "$HOME/.nibl/app" "$term" "$HOME/.nibl/bin/nibl-term"
  rmdir "$HOME/.nibl/bin" 2>/dev/null || true
  defaults delete dev.nibl.app >/dev/null 2>&1 || true
  say "Nibl removed. Your notes stay in ~/.nibl/notes.md, the bar settings in ~/.config/nibl."
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
