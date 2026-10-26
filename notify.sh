#!/usr/bin/env bash
# Play a sound and show a desktop notification when Claude Code (or Codex) finishes
# or needs your input. Runs as a hook and returns at once; the sound plays in the background.
#
#   Claude Code hook:  event JSON on stdin (Stop, Notification, PermissionRequest)
#   Codex notify:      event JSON as the first argument (agent-turn-complete)
#   Codex hook:        notify.sh --codex, event JSON on stdin
#   Try it:            notify.sh --test
#
# macOS: afplay + terminal-notifier or osascript. Linux: paplay, pw-play, canberra-gtk-play
# or aplay + notify-send. Windows (Git Bash) and WSL: powershell.exe.
#
# Options (environment variables):
#   NOTIFY_MUTE=1          no sound, no popup, no speech
#   NOTIFY_POPUP=0         sound only, no desktop notification
#   NOTIFY_SOUND_DONE      sound when the agent finishes: a file path, a macOS sound name
#                          (Glass, Ping, Hero...), or "none"
#   NOTIFY_SOUND_INPUT     sound when it needs you (same forms)
#   NOTIFY_SPEAK=1         also say a short line ("Claude Code finished in my-app")
#   NOTIFY_VOICE           voice for NOTIFY_SPEAK
# Or create a file named "mute" next to this script to silence it without a restart.
set -u

here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
has() { command -v "$1" >/dev/null 2>&1; }

app="Claude Code"
input=""
test_mode=0
case "${1:-}" in
  --test) test_mode=1 ;;
  --codex) app="Codex"; [ -t 0 ] || input="$(cat)" ;;
  \{*) input="$1" ;;                      # Codex notify passes the JSON as an argument
  *) [ -t 0 ] || input="$(cat)" ;;        # Claude Code hooks pass it on stdin
esac

[ "${NOTIFY_MUTE:-0}" = "1" ] && exit 0
[ -n "$here" ] && [ -e "$here/mute" ] && exit 0

field() { # field <jq path>; empty when jq is missing or the field is absent
  has jq || return 0
  printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null | head -n 1
}

kind=""; reason=""
if [ "$test_mode" = 1 ]; then
  kind="test"
else
  event="$(field .hook_event_name)"
  [ -n "$event" ] || event="$(field .type)"
  [ "$event" = "agent-turn-complete" ] && app="Codex"
  case "$event" in
    Stop|agent-turn-complete) kind="done" ;;
    PermissionRequest) kind="input"; reason="needs your approval" ;;
    Notification)
      case "$(field .notification_type)" in
        permission_prompt) kind="input"; reason="needs your permission" ;;
        idle_prompt) kind="input"; reason="is waiting for you" ;;
        elicitation_dialog|elicitation_url_dialog|agent_needs_input) kind="input"; reason="needs your input" ;;
        *) exit 0 ;;
      esac ;;
    *) exit 0 ;;
  esac
fi

cwd="$(field .cwd)"
project="$(basename "${cwd:-$PWD}")"
detail="$(field .message)"   # Claude Code's own notification text, when there is one

line() { # line <kind> <reason>: the popup body and the spoken sentence
  if [ "$1" = "done" ]; then echo "$app finished in $project."
  else echo "$app $2 in $project."; fi
}

play() { # play <done|input>
  local custom name id f
  if [ "$1" = "done" ]; then custom="${NOTIFY_SOUND_DONE:-}"; name="Glass"; id="complete"
  else custom="${NOTIFY_SOUND_INPUT:-}"; name="Ping"; id="message-new-instant"; fi
  [ "$custom" = "none" ] && return 0
  if has afplay; then
    f="${custom:-$name}"
    [ -f "$f" ] || f="/System/Library/Sounds/$f.aiff"
    afplay "$f"
  elif has paplay || has pw-play || has canberra-gtk-play || has aplay; then
    f="${custom:-/usr/share/sounds/freedesktop/stereo/$id.oga}"
    if [ -f "$f" ] && has paplay; then paplay "$f"
    elif [ -f "$f" ] && has pw-play; then pw-play "$f"
    elif has canberra-gtk-play; then
      if [ -f "$f" ]; then canberra-gtk-play -f "$f"; else canberra-gtk-play -i "$id"; fi
    elif [ -f "$f" ] && has aplay; then aplay -q "$f"
    fi
  elif has powershell.exe; then
    if [ "$1" = "done" ]; then f="${custom:-Windows Notify System Generic.wav}"; else f="${custom:-Windows Ding.wav}"; fi
    # The file name goes in on stdin, so no quoting is needed across the WSL boundary.
    printf '%s\n' "$f" | powershell.exe -NoProfile -NonInteractive -Command \
      '$f = [Console]::In.ReadLine(); if (-not (Test-Path $f)) { $f = Join-Path $env:WINDIR ("Media\" + $f) }; if (Test-Path $f) { (New-Object System.Media.SoundPlayer $f).PlaySync() } else { [System.Media.SystemSounds]::Asterisk.Play(); Start-Sleep -Seconds 1 }'
  fi
}

popup() { # popup <title> <body>
  [ "${NOTIFY_POPUP:-1}" = "0" ] && return 0
  if has terminal-notifier; then
    terminal-notifier -title "$1" -message "$2" -group claude-code-sound-notification
  elif has osascript; then
    # Text goes in as arguments, never pasted into the AppleScript source.
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$1" "$2"
  elif has notify-send; then
    notify-send -a "$app" "$1" "$2"
  elif has powershell.exe; then
    printf '%s\n%s\n' "$1" "$2" | powershell.exe -NoProfile -NonInteractive -Command \
      'Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $t = [Console]::In.ReadLine(); $m = [Console]::In.ReadLine(); $n = New-Object System.Windows.Forms.NotifyIcon; $n.Icon = [System.Drawing.SystemIcons]::Information; $n.Visible = $true; $n.ShowBalloonTip(5000, $t, $m, "Info"); Start-Sleep -Seconds 6; $n.Dispose()'
  fi
}

speak() { # speak <text>
  [ "${NOTIFY_SPEAK:-0}" = "1" ] || return 0
  local voice="${NOTIFY_VOICE:-}"
  if has say; then
    if [ -n "$voice" ]; then printf '%s' "$1" | say -v "$voice" -f -; else printf '%s' "$1" | say -f -; fi
  elif has spd-say; then
    if [ -n "$voice" ]; then printf '%s' "$1" | spd-say -w -e -y "$voice"; else printf '%s' "$1" | spd-say -w -e; fi
  elif has espeak-ng || has espeak; then
    local bin; bin="$(command -v espeak-ng || command -v espeak)"
    if [ -n "$voice" ]; then printf '%s' "$1" | "$bin" --stdin -v "$voice"; else printf '%s' "$1" | "$bin" --stdin; fi
  elif has powershell.exe; then
    printf '%s' "$1" | powershell.exe -NoProfile -NonInteractive -Command \
      'Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak([Console]::In.ReadToEnd())'
  fi
}

run() {
  if [ "$kind" = "test" ]; then
    popup "$app" "Test: this is the sound when $app finishes."
    play done; speak "$app finished."
    sleep 1
    popup "$app" "Test: this is the sound when $app needs you."
    play input; speak "$app needs your input."
    return
  fi
  local text; text="$(line "$kind" "$reason")"
  local body="$text"
  [ -n "$detail" ] && body="$detail ($project)"
  popup "$app" "$body" &
  play "$kind"
  speak "$text"
  wait
}

# Never block the agent and never print to stdout: the hook returns at once.
if [ "${NOTIFY_SYNC:-0}" = "1" ]; then
  run </dev/null >/dev/null 2>&1
else
  run </dev/null >/dev/null 2>&1 &
fi
exit 0
