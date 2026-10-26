#!/usr/bin/env bash
# Tests for notify.sh with fake sound, popup and voice programs (no audio needed).
#   bash tests/notify.test.sh
# Variables such as rc are read inside the quoted conditions that check() evals.
# shellcheck disable=SC2034
set -u
here="$(cd "$(dirname "$0")" && pwd)"
notify="$here/../notify.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

# A fake program records its arguments and its stdin, one line per call, in $work/log.
fake() { # fake <dir> <name>...
  local dir="$1"; shift; mkdir -p "$dir"
  for name in "$@"; do
    cat > "$dir/$name" <<F
#!/bin/sh
in="\$(cat 2>/dev/null | tr '\n' '/')"
printf '%s|%s|%s\n' "$name" "\$*" "\$in" >> "$work/log"
F
    chmod +x "$dir/$name"
  done
}
# Run notify.sh with only the given fake dir plus a few basic tools on PATH, so real
# players on the test machine are never picked up. NOTIFY_SYNC=1 runs it in the foreground.
jqdir="$work/core"; mkdir -p "$jqdir"
for t in jq cat tr head sed basename dirname sleep date env sh bash; do ln -s "$(command -v "$t")" "$jqdir/$t"; done
run() { local bin="$1"; shift; rm -f "$work/log"; env -i HOME="$HOME" PATH="$bin:$jqdir" NOTIFY_SYNC=1 ${ENVS:-} bash "$notify" "$@"; }
log() { cat "$work/log" 2>/dev/null; }

stop='{"session_id":"s","cwd":"/work/billing-api","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done."}'
perm='{"session_id":"s","cwd":"/work/billing-api","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","title":"Permission needed","notification_type":"permission_prompt"}'
idle='{"session_id":"s","cwd":"/work/web","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}'
auth='{"session_id":"s","cwd":"/work/web","hook_event_name":"Notification","message":"ok","notification_type":"auth_success"}'
codex='{"type":"agent-turn-complete","thread-id":"t","turn-id":"u","cwd":"/work/mobile","input-messages":["fix it"],"last-assistant-message":"Fixed."}'
codexperm='{"session_id":"s","cwd":"/work/mobile","hook_event_name":"PermissionRequest","turn_id":"u","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

echo "notify.sh"

# macOS: afplay + osascript
mac="$work/mac"; fake "$mac" afplay osascript
out="$(printf '%s' "$stop" | run "$mac")"
check "Stop plays the done sound with afplay (Glass)" 'log | grep -q "^afplay|/System/Library/Sounds/Glass.aiff|"' "$(log)"
check "Stop shows a notification with osascript, text passed as arguments" \
  'log | grep -q "^osascript|.*end run Claude Code Claude Code finished in billing-api.|"' "$(log)"
check "prints nothing to stdout" '[ -z "$out" ]' "$out"

printf '%s' "$perm" | run "$mac" >/dev/null
check "permission_prompt plays the input sound (Ping)" 'log | grep -q "^afplay|/System/Library/Sounds/Ping.aiff|"' "$(log)"
check "permission_prompt notification uses Claude Code's message" \
  'log | grep -q "Claude needs your permission to use Bash (billing-api)"' "$(log)"

printf '%s' "$auth" | run "$mac" >/dev/null
check "other notification types are ignored" '[ -z "$(log)" ]' "$(log)"

printf '%s' "$idle" | run "$mac" >/dev/null
check "idle_prompt plays the input sound" 'log | grep -q "Ping.aiff"' "$(log)"

# terminal-notifier preferred over osascript
fake "$mac" terminal-notifier
printf '%s' "$stop" | run "$mac" >/dev/null
check "terminal-notifier is used when installed" \
  'log | grep -q "^terminal-notifier|-title Claude Code -message Claude Code finished in billing-api. -group claude-code-sound-notification|" && ! log | grep -q "^osascript"' "$(log)"
rm "$mac/terminal-notifier"

# options
ENVS="NOTIFY_SOUND_DONE=Hero" run "$mac" <<<"$stop" >/dev/null
check "NOTIFY_SOUND_DONE takes a macOS sound name" 'log | grep -q "^afplay|/System/Library/Sounds/Hero.aiff|"' "$(log)"
touch "$work/custom.aiff"
ENVS="NOTIFY_SOUND_INPUT=$work/custom.aiff" run "$mac" <<<"$perm" >/dev/null
check "NOTIFY_SOUND_INPUT takes a file path" "log | grep -q \"^afplay|$work/custom.aiff|\"" "$(log)"
ENVS="NOTIFY_SOUND_DONE=none" run "$mac" <<<"$stop" >/dev/null
check "NOTIFY_SOUND_DONE=none skips the sound but keeps the popup" '! log | grep -q "^afplay" && log | grep -q "^osascript"' "$(log)"
ENVS="NOTIFY_POPUP=0" run "$mac" <<<"$stop" >/dev/null
check "NOTIFY_POPUP=0 plays the sound only" 'log | grep -q "^afplay" && ! log | grep -q "^osascript"' "$(log)"
ENVS="NOTIFY_MUTE=1" run "$mac" <<<"$stop" >/dev/null
check "NOTIFY_MUTE=1 does nothing" '[ -z "$(log)" ]' "$(log)"

# mute file next to the script
cp "$notify" "$work/notify-copy.sh"; touch "$work/mute"
rm -f "$work/log"; env -i HOME="$HOME" PATH="$mac:$jqdir" NOTIFY_SYNC=1 bash "$work/notify-copy.sh" <<<"$stop"
check "a mute file next to the script silences it" '[ -z "$(log)" ]' "$(log)"
rm -f "$work/mute"

# ~ in a sound path is expanded (settings.json "env" does not expand it)
mkdir -p "$work/home/sounds"; touch "$work/home/sounds/done.aiff"
rm -f "$work/log"; env -i HOME="$work/home" PATH="$mac:$jqdir" NOTIFY_SYNC=1 NOTIFY_SOUND_DONE="~/sounds/done.aiff" bash "$notify" <<<"$stop"
check "a ~/ sound path is expanded" "log | grep -q \"^afplay|$work/home/sounds/done.aiff|\"" "$(log)"

# spoken line
fake "$mac" say
ENVS="NOTIFY_SPEAK=1 NOTIFY_VOICE=Samantha" run "$mac" <<<"$stop" >/dev/null
check "NOTIFY_SPEAK=1 says a short line with say" 'log | grep -q "^say|-v Samantha -f -|Claude Code finished in billing-api.$"' "$(log)"
run "$mac" <<<"$stop" >/dev/null
check "no speech unless NOTIFY_SPEAK=1" '! log | grep -q "^say"' "$(log)"

# Linux: paplay + notify-send, with a freedesktop sound present
lin="$work/linux"; fake "$lin" paplay notify-send espeak-ng
if [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
  run "$lin" <<<"$stop" >/dev/null
  check "Linux plays the freedesktop sound with paplay" 'log | grep -q "^paplay|/usr/share/sounds/freedesktop/stereo/complete.oga|"' "$(log)"
fi
touch "$work/done.oga"
ENVS="NOTIFY_SOUND_DONE=$work/done.oga" run "$lin" <<<"$stop" >/dev/null
check "Linux plays a custom file with paplay" "log | grep -q \"^paplay|$work/done.oga|\"" "$(log)"
check "Linux shows the popup with notify-send" 'log | grep -q "^notify-send|-a Claude Code -- Claude Code Claude Code finished in billing-api.|"' "$(log)"
ENVS="NOTIFY_SPEAK=1" run "$lin" <<<"$perm" >/dev/null
check "Linux speaks with espeak-ng on stdin" 'log | grep -q "^espeak-ng|--stdin|Claude Code needs your permission in billing-api.$"' "$(log)"

# aplay reads WAV only: never hand it an Ogg file
ap="$work/aplay"; fake "$ap" aplay
ENVS="NOTIFY_SOUND_DONE=$work/done.oga NOTIFY_POPUP=0" run "$ap" <<<"$stop" >/dev/null
check "aplay is not given an .oga file" '! log | grep -q "^aplay"' "$(log)"
touch "$work/done.wav"
ENVS="NOTIFY_SOUND_DONE=$work/done.wav NOTIFY_POPUP=0" run "$ap" <<<"$stop" >/dev/null
check "aplay plays a .wav file" "log | grep -q \"^aplay|-q $work/done.wav|\"" "$(log)"

# Linux without sound files: canberra-gtk-play by sound id
can="$work/canberra"; fake "$can" canberra-gtk-play notify-send
ENVS="NOTIFY_SOUND_INPUT=/nonexistent.oga" run "$can" <<<"$perm" >/dev/null
check "canberra-gtk-play falls back to the sound id" 'log | grep -q "^canberra-gtk-play|-i message-new-instant|"' "$(log)"

# Windows / WSL: powershell.exe
win="$work/win"; fake "$win" powershell.exe
run "$win" <<<"$stop" >/dev/null
check "Windows plays a .wav through PowerShell, file name on stdin" \
  'log | grep -q "^powershell.exe|.*SoundPlayer.*|Windows Notify System Generic.wav/$"' "$(log)"
check "Windows shows a balloon notification through PowerShell" \
  'log | grep -q "^powershell.exe|.*ShowBalloonTip.*|Claude Code/Claude Code finished in billing-api./$"' "$(log)"

# Codex notify (JSON as an argument) and Codex PermissionRequest hook (--codex, stdin)
run "$mac" "$codex" </dev/null >/dev/null
check "Codex notify: agent-turn-complete plays the done sound" 'log | grep -q "Glass.aiff"' "$(log)"
check "Codex notify: the popup says Codex and the project" 'log | grep -q "end run Codex Codex finished in mobile.|"' "$(log)"
run "$mac" --codex <<<"$codexperm" >/dev/null
check "Codex PermissionRequest hook plays the input sound" 'log | grep -q "Ping.aiff" && log | grep -q "Codex needs your approval in mobile."' "$(log)"

# without jq the event is still read
ENVS="NOTIFY_TEST_NO_JQ=1" run "$mac" <<<"$perm" >/dev/null
check "without jq: permission_prompt still plays the input sound" 'log | grep -q "Ping.aiff" && log | grep -q "(billing-api)"' "$(log)"
ENVS="NOTIFY_TEST_NO_JQ=1" run "$mac" <<<"$stop" >/dev/null
check "without jq: Stop still plays the done sound" 'log | grep -q "Glass.aiff"' "$(log)"
ENVS="NOTIFY_TEST_NO_JQ=1" run "$mac" "$codex" </dev/null >/dev/null
check "without jq: Codex notify still works" 'log | grep -q "Codex finished in mobile."' "$(log)"

# the other input-needed notification types
for t in elicitation_dialog elicitation_url_dialog agent_needs_input; do
  run "$mac" <<<"{\"hook_event_name\":\"Notification\",\"cwd\":\"/w/app\",\"notification_type\":\"$t\"}" >/dev/null
  check "$t plays the input sound" 'log | grep -q "Ping.aiff" && log | grep -q "needs your input in app."' "$(log)"
done

# WSL: a Linux sound path is converted for PowerShell
printf '#!/bin/sh\nprintf "%%s\\n" "C:/converted.wav"\n' > "$win/wslpath"
chmod +x "$win/wslpath"; touch "$work/w.wav"
ENVS="NOTIFY_SOUND_DONE=$work/w.wav NOTIFY_POPUP=0" run "$win" <<<"$stop" >/dev/null
check "WSL: a Linux path goes through wslpath -w" 'log | grep -q "SoundPlayer.*|C:.converted.wav/$"' "$(log)"
rm -f "$win/wslpath"

# unknown or empty input does nothing
run "$mac" <<<'not json' >/dev/null
check "input that is not JSON does nothing" '[ -z "$(log)" ]' "$(log)"
run "$mac" <<<'' >/dev/null; rc=$?
check "empty input exits 0" '[ $rc -eq 0 ] && [ -z "$(log)" ]' "$(log)"

# --test plays both sounds
run "$mac" --test </dev/null >/dev/null
check "--test plays the done and the input sound" 'log | grep -q Glass.aiff && log | grep -q Ping.aiff' "$(log)"

# returns at once even when the sound is slow (real background mode)
slow="$work/slow"; mkdir -p "$slow"
printf '#!/bin/sh\nsleep 3\necho afplay >> %s/log\n' "$work" > "$slow/afplay"; chmod +x "$slow/afplay"
start=$(date +%s)
env -i HOME="$HOME" PATH="$slow:$jqdir" NOTIFY_POPUP=0 bash "$notify" <<<"$stop"
took=$(( $(date +%s) - start ))
check "returns at once while the sound plays in the background" '[ "$took" -le 1 ]' "took ${took}s"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
