# Turn Runner for Claude Code

Switch tabs while Claude Code works and still know when it's done. A little runner races across a floating, always-on-top track while Claude works on your prompt, and crosses the finish line, with a water-drop sound, the moment Claude finishes.

```
┌──────────────────────────────────────────┐
│ my-project · working · 0:42 · 12 steps   │
│ ━━━━━━━━━━━━🏃‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧‧ 🏁 │
└──────────────────────────────────────────┘
```

- **Always visible**: the card floats above every app, Space and full-screen window, and never steals focus.
- **Finish line**: 🙌 and green when Claude answers, 🛑 and red when the turn is interrupted or fails. A desktop notification and a sound go off too.
- **Click to jump back**: clicking the card opens the project in VS Code (or Cursor, Zed, Terminal…), bringing its window forward.
- **Customizable**: right-click the card to pick the runner (🏃 🐎 🐕 🐢 🦖…), the finish line, the sound, the volume, the size, how long the finish stays up and which editor to open.
- **Inside Claude Code too**: a matching track runs in a band above the prompt.

Claude Code can't know in advance how long a task takes, so the runner moves with time and with each tool call, slowing down as it nears the flag, and only crosses when the turn has really ended.

## Requirements

- macOS (the floating window is a small native app; on other systems only the in-terminal band works)
- Xcode Command Line Tools for `swiftc`: `xcode-select --install`
- Python 3 (used once, to make the sound)
- Claude Code with plugin hooks modules

## Install

```sh
git clone https://github.com/ayman-boop/claude-completion.git
cd claude-completion
./install.sh
```

`install.sh` builds `TurnRunner.app` into `~/.claude/turn-runner/`, makes the water-drop sound, and adds this folder to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` so every new Claude Code session loads the mod. Start a new session and send a prompt.

Prefer installing the plugin through Claude Code's plugin manager? Build the app only, then install from the marketplace:

```sh
./install.sh --app-only
```

At the prompt of a terminal Claude Code session:

```
/plugin install turn-runner --marketplace ayman-boop/claude-completion
```

## Settings

Right-click the card for the settings menu. Choices are saved to `~/.claude/turn-runner/config.json`, which you can also edit by hand (changes apply at the next task):

```json
{
  "editor": "Visual Studio Code",
  "finish": "🏁",
  "flipRunner": true,
  "hideAfter": 10,
  "runner": "🏃",
  "size": 1,
  "sound": "Water drop",
  "volume": 0.8
}
```

| Key | Meaning |
| --- | --- |
| `runner` | Any emoji. |
| `flipRunner` | Mirror the runner so it faces the flag (most emoji face left). |
| `finish` | The emoji at the end of the track. |
| `sound` | `"Water drop"`, any name from `/System/Library/Sounds` (`"Glass"`, `"Pop"`…), or `"None"`. |
| `volume` | `0` to `1`. |
| `size` | Scale of the card, e.g. `0.8`, `1`, `1.35`. |
| `hideAfter` | Seconds the finished card stays up; `0` keeps it until clicked. |
| `editor` | App name passed to `open -a` when you click the card. |

Drag the card anywhere; it remembers its spot. If no desktop notification appears, set a notification channel in Claude Code's `/config` and allow notifications for your terminal in System Settings.

## How it works

```
Claude Code ──hooks──▶ hooks/register.tsx ──writes──▶ ~/.claude/turn-runner/state.json
                                                              │
                                     TurnRunner.app ◀──reads──┘ (20× a second)
```

- `hooks/register.tsx` is a Claude Code hooks module. On `turn.start` it records the start time, counts `tool.call`s and records the end on `turn.complete`. It draws the in-terminal band, raises the notification, writes the state file with the session's project folder, and opens the app (`open -g`, so focus never moves).
- `overlay/TurnRunner.swift` is the floating window: a borderless, non-activating `NSPanel` on every Space. It animates the runner, plays the sound once per finish, and opens the project on click.
- `overlay/make_drop.py` synthesizes the water-drop sound: a fast upward pitch sweep with a quick decay, plus a softer echo.

If several Claude Code sessions run at once, the card follows whichever started its task most recently.

## Uninstall

```sh
./uninstall.sh
```

This quits the app, deletes `~/.claude/turn-runner/`, and removes this folder from `CLAUDE_CODE_PLUGIN_DIRS`.

## License

MIT
