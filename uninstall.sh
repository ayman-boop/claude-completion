#!/bin/sh
# Removes the floating window, its settings and the mod's entry in ~/.claude/settings.json.
REPO="$(cd "$(dirname "$0")" && pwd)"
pkill -f "TurnRunner.app/Contents/MacOS/TurnRunner" 2>/dev/null || true
rm -rf "$HOME/.claude/turn-runner"
python3 -I - "$REPO" <<'PY'
import json, os, sys
p = os.path.expanduser('~/.claude/settings.json')
if not os.path.exists(p):
    sys.exit()
s = json.load(open(p))
env = s.get('env', {})
dirs = [d for d in env.get('CLAUDE_CODE_PLUGIN_DIRS', '').split(':') if d and d != sys.argv[1]]
if dirs:
    env['CLAUDE_CODE_PLUGIN_DIRS'] = ':'.join(dirs)
else:
    env.pop('CLAUDE_CODE_PLUGIN_DIRS', None)
if not env:
    s.pop('env', None)
with open(p, 'w') as f:
    json.dump(s, f, indent=2); f.write('\n')
PY
echo "Turn Runner removed."
