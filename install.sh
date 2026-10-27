#!/bin/sh
# Builds the floating Turn Runner window into ~/.claude/turn-runner and, unless
# --app-only is given, tells Claude Code to load the mod from this folder.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/turn-runner"
APP="$DEST/TurnRunner.app"

if [ "$(uname)" != "Darwin" ]; then
  echo "The floating window is macOS only; the terminal band still works without it." >&2
  exit 1
fi
command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install' first." >&2; exit 1; }

echo "Building TurnRunner.app..."
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$REPO/overlay/TurnRunner.swift" -o "$APP/Contents/MacOS/TurnRunner"
cp "$REPO/overlay/Info.plist" "$APP/Contents/Info.plist"

echo "Making the water-drop sound..."
python3 -I "$REPO/overlay/make_drop.py" "$DEST/drop.wav" >/dev/null

# a running copy keeps the old build until it restarts
pkill -f "$APP/Contents/MacOS/TurnRunner" 2>/dev/null || true

if [ "$1" != "--app-only" ]; then
  echo "Loading the mod in every Claude Code session..."
  python3 -I - "$REPO" <<'PY'
import json, os, sys
p = os.path.expanduser('~/.claude/settings.json')
s = json.load(open(p)) if os.path.exists(p) else {}
env = s.setdefault('env', {})
dirs = [d for d in env.get('CLAUDE_CODE_PLUGIN_DIRS', '').split(':') if d and not d.rstrip('/').endswith('turn-runner/mod')]
if sys.argv[1] not in dirs:
    dirs.append(sys.argv[1])
env['CLAUDE_CODE_PLUGIN_DIRS'] = ':'.join(dirs)
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, 'w') as f:
    json.dump(s, f, indent=2); f.write('\n')
PY
fi

echo "Done. Start a new Claude Code session and send a prompt."
