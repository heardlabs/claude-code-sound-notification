# claude-code-sound-notification: play a sound when Claude Code finishes or needs your input

To get a sound and a desktop notification when Claude Code finishes a task or needs your permission, run this one command (needs `jq`):

```bash
curl -fsSL https://raw.githubusercontent.com/heardlabs/claude-code-sound-notification/main/install.sh | bash
```

It adds two [Claude Code hooks](https://code.claude.com/docs/en/hooks) to `~/.claude/settings.json`: a `Stop` hook that plays a "done" sound when Claude finishes responding, and a `Notification` hook that plays a different sound when Claude needs your permission or input. It merges into your settings with `jq`, keeps your other hooks, and backs up the file first. The hook script itself uses `jq` when it can find it and falls back to plain text matching when it cannot. Free, MIT, no API key, no account.

[![test](https://github.com/heardlabs/claude-code-sound-notification/actions/workflows/test.yml/badge.svg)](https://github.com/heardlabs/claude-code-sound-notification/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What you get

| When | Hook | Sound (macOS / Linux) | Notification |
|---|---|---|---|
| Claude finishes responding | `Stop` | Glass / freedesktop `complete` | "Claude Code finished in my-app." |
| Claude needs your permission to use a tool | `Notification`, `permission_prompt` | Ping / freedesktop `message-new-instant` | Claude Code's own text, such as "Claude needs your permission to use Bash" |
| An MCP server asks you for input | `Notification`, `elicitation_dialog`, `elicitation_url_dialog` | same as above | Claude Code's own text |
| A background session waits on you (agent view) | `Notification`, `agent_needs_input` | same as above | Claude Code's own text |

Both hooks use `"async": true`, so Claude Code never waits for the sound. The script prints nothing and always exits 0.

## Install

**One command** (shown above). It copies [`notify.sh`](notify.sh) to `~/.claude/claude-code-sound-notification/` and merges the hooks into `~/.claude/settings.json`. It respects `CLAUDE_CONFIG_DIR` if you set it. Running it again updates the install without adding duplicates.

**From a clone:**

```bash
git clone https://github.com/heardlabs/claude-code-sound-notification
bash claude-code-sound-notification/install.sh
```

**Then try it:**

```bash
bash ~/.claude/claude-code-sound-notification/notify.sh --test
```

Type `/hooks` in Claude Code to see the new hooks under `Stop` and `Notification`. Claude Code picks up settings changes on its own; if the hooks are not listed after a few seconds, restart the session.

**By hand,** if you prefer to edit the file yourself, add this to `~/.claude/settings.json` (merge it into any `hooks` you already have) and put `notify.sh` at that path:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/claude-code-sound-notification/notify.sh", "async": true }] }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/claude-code-sound-notification/notify.sh", "async": true }]
      }
    ]
  }
}
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/heardlabs/claude-code-sound-notification/main/install.sh | bash -s -- --uninstall
```

This removes only the hooks that run `claude-code-sound-notification/notify.sh` (including any you added by hand, since the script folder is deleted), backs up `settings.json` first, and deletes the script folder. Your other hooks and settings stay as they were.

## Supported systems

| System | Sound | Desktop notification | Spoken line (optional) |
|---|---|---|---|
| macOS | `afplay` with a system sound | `terminal-notifier` if installed, else `osascript` | `say` |
| Linux | `paplay`, `pw-play`, `canberra-gtk-play` or `aplay` | `notify-send` | `spd-say`, `espeak-ng` or `espeak` |
| Windows (Git Bash) and WSL | PowerShell `System.Media.SoundPlayer` | PowerShell tray balloon | PowerShell `System.Speech` |

On Linux, `sudo apt install pulseaudio-utils libnotify-bin` covers the sound and the popup on Debian and Ubuntu. The scripts are tested in CI on Ubuntu with fake players and notifiers. They have not been tested with real audio on any system; if a sound does not play for you, please open an issue.

## Options

Set these in your shell profile, or in the `env` block of `~/.claude/settings.json`:

| Variable | What it does | Example |
|---|---|---|
| `NOTIFY_SOUND_DONE` | Sound when Claude finishes: a file path, a macOS sound name, or `none` | `Hero`, `~/sounds/done.wav` |
| `NOTIFY_SOUND_INPUT` | Sound when Claude needs you (same forms) | `Submarine`, `none` |
| `NOTIFY_POPUP` | `0` for sound only, no desktop notification | `0` |
| `NOTIFY_SPEAK` | `1` to also say a short line, such as "Claude Code finished in my-app" | `1` |
| `NOTIFY_VOICE` | Voice for the spoken line (`say -v`, `spd-say -y` or `espeak-ng -v`) | `Samantha` (macOS), `en-us` (espeak-ng) |
| `NOTIFY_MUTE` | `1` turns everything off | `1` |

To mute without restarting anything: `touch ~/.claude/claude-code-sound-notification/mute`. Delete the file to unmute.

macOS sound names are the files in `/System/Library/Sounds` (Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink). On Windows, use a `.wav` path or a file name from `C:\Windows\Media`.

## FAQ

**How do I get a sound when Claude Code finishes?**
Add a `Stop` hook to `~/.claude/settings.json` that plays a sound. The installer above does it for you. `Stop` runs when Claude finishes responding. It does not run if you interrupt Claude, and an API error fires `StopFailure` instead ([hooks docs, Stop](https://code.claude.com/docs/en/hooks#stop)).

**How do I get a notification when Claude Code needs my permission?**
Use a `Notification` hook with the `permission_prompt` matcher, which the installer adds. Note the timing: in the terminal, Claude Code sends `permission_prompt` only after the prompt has waited about six seconds and each keystroke defers it, so you mostly hear it when you have looked away. In the desktop app and the VS Code extension it comes about six seconds after Claude asks, whether or not you are typing ([hooks docs, Notification](https://code.claude.com/docs/en/hooks#notification)). If you want a ping the moment Claude asks, add the same command under a `PermissionRequest` hook and remove `permission_prompt` from the `Notification` matcher, or you will hear two sounds. `PermissionRequest` fires on tool permission prompts even while you are watching, but not for a sandboxed command's network request.

**Can I get pinged when Claude is idle and waiting for my reply?**
Yes: `bash install.sh --with-idle` adds `idle_prompt`, which Claude Code sends about 60 seconds after it finishes responding if you have not typed since. It is off by default because the `Stop` sound already tells you Claude is done.

**Why is there no sound or no banner on macOS?**
If the sound plays but no banner shows, `osascript` notifications go through Script Editor, which may not have notification permission. Run `osascript -e 'display notification "test"'` once, then turn on Script Editor in System Settings > Notifications ([Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)). Installing `terminal-notifier` (`brew install terminal-notifier`) avoids this. If there is no sound either, check that `NOTIFY_MUTE` is not set and that no `mute` file exists.

**Why do I hear nothing on Linux or over SSH?**
The hook runs on the machine where Claude Code runs. Over SSH or in a container there is usually no sound server and no notification daemon, so nothing plays. Run `notify-send test` and `paplay /usr/share/sounds/freedesktop/stereo/complete.oga` there to check.

**Does it work in the Claude desktop app and the VS Code extension?**
Claude Code fires the same hook events wherever it runs, including IDE extensions and the desktop app, so the hooks should run there too. Cloud sessions do not read your local `~/.claude/settings.json`, so this does not run there ([hooks docs](https://code.claude.com/docs/en/hooks)).

**Does it work with Codex?**
Yes, with a few lines of config, since Codex reads its own config, not Claude Code's settings. Install as above to get `notify.sh`, then:

- *Sound when Codex finishes a turn:* add a top-level `notify` line to `~/.codex/config.toml`, above any `[section]`. Codex runs it on `agent-turn-complete` and passes the event as a JSON argument, which `notify.sh` reads ([Codex docs, Notifications](https://developers.openai.com/codex/config-advanced#notifications)). Codex has one `notify` program, so this replaces any you already set. Use your full home path (`/home/you` on Linux), not `~`.

  ```toml
  notify = ["bash", "/Users/you/.claude/claude-code-sound-notification/notify.sh"]
  ```

- *Sound when Codex asks for approval:* add a `PermissionRequest` hook to `~/.codex/hooks.json`, merging it into the file if you already have one, then open `/hooks` in Codex once to review and trust it, since Codex skips new hooks until you do ([Codex docs, Hooks](https://developers.openai.com/codex/hooks)):

  ```json
  {
    "hooks": {
      "PermissionRequest": [
        { "hooks": [{ "type": "command", "command": "bash /Users/you/.claude/claude-code-sound-notification/notify.sh --codex", "async": true }] }
      ]
    }
  }
  ```

- *No script at all:* Codex's built-in terminal notifications can cover both events. Set `notifications = ["agent-turn-complete", "approval-requested"]` under `[tui]` in `config.toml`. They fire when the terminal is unfocused (the default `notification_condition`), as an OSC 9 notification or a terminal bell, depending on your terminal ([Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)).

**Does it send anything over the network?**
No. `notify.sh` only runs local programs (`afplay`, `paplay`, `notify-send`, PowerShell and so on). The one-line installer downloads the script from this repo; after that nothing is fetched.

**How do I change the sounds?**
Set `NOTIFY_SOUND_DONE` and `NOTIFY_SOUND_INPUT` (see [Options](#options)).

## Want it spoken in plain English?

A sound tells you that something happened, not what. [Heard](https://heard.dev/?utm_source=github&utm_medium=organic&utm_campaign=sound-notification) (heard.dev), the voice context layer for agents, is a Mac app (macOS 14 or later) that follows your Claude Code and Codex sessions and tells you in a sentence or two when an agent finishes, fails or needs your approval, and on Heard Power you can talk back. There is a free tier and a 14-day Heard Power trial with no card required.

Two free options from the same team:

- [claude-code-tts](https://github.com/heardlabs/claude-code-tts): a `/say` skill for Claude Code and Codex that speaks a short briefing (what this is, how it went, who moves next) with your computer's built-in voice.
- [heardlabs/heard](https://github.com/heardlabs/heard): the open-source engine (Apache 2.0) you build yourself. It runs fully local with Kokoro text-to-speech and speaks a short summary of what the agent did. It does not speak Claude Code approval prompts; only the Mac app does.

## Tests

- `bash tests/notify.test.sh`: checks on `notify.sh` with fake players, notifiers and voices (macOS, Linux, Windows and WSL paths, each event type it handles, Codex input, options, mute, running without `jq`, and that it returns at once).
- `bash tests/install.test.sh`: checks on the installer (merging into existing settings, backups, no duplicates on a second run, keeping your own hooks on reinstall, uninstall that gives back your settings, refusing invalid JSON, symlinked settings, missing `jq`).

Both run in [GitHub Actions](.github/workflows/test.yml) on Ubuntu, along with `shellcheck`.

## License

[MIT](LICENSE)
