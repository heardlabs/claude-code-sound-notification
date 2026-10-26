#!/usr/bin/env bash
# Tests for install.sh: it must merge into settings.json, never overwrite, back up first,
# be safe to run twice, and remove only its own hooks on --uninstall.
#   bash tests/install.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
install="$here/../install.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

cfg="$work/claude"
s="$cfg/settings.json"
inst() { CLAUDE_CONFIG_DIR="$cfg" bash "$install" "$@" >"$work/out" 2>&1; }
q() { jq -r "$1" "$s"; }

echo "install.sh"

# 1. fresh install with no settings.json
inst; rc=$?
check "installs with no settings.json (exit 0)" '[ $rc -eq 0 ]' "$(cat "$work/out")"
check "creates settings.json with a Stop hook" '[ "$(q ".hooks.Stop | length")" = 1 ]' "$(cat "$s")"
check "Stop hook runs notify.sh with async true" \
  '[ "$(q ".hooks.Stop[0].hooks[0].async")" = true ] && q ".hooks.Stop[0].hooks[0].command" | grep -q "claude-code-sound-notification/notify.sh"' "$(cat "$s")"
check "Notification hook matches permission and input prompts" \
  '[ "$(q ".hooks.Notification[0].matcher")" = "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input" ]' "$(cat "$s")"
check "copies notify.sh into the config dir, executable" '[ -x "$cfg/claude-code-sound-notification/notify.sh" ]'
check "the installed command runs" \
  'cmd="$(q ".hooks.Stop[0].hooks[0].command")"; echo "{}" | NOTIFY_MUTE=1 sh -c "$cmd"'

# 2. merge into existing settings with other hooks
rm -rf "$cfg"; mkdir -p "$cfg"
cat > "$s" <<'J'
{
  "model": "opus",
  "permissions": {"allow": ["Bash(npm test)"]},
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}],
    "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "my-notify"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard.sh"}]}]
  }
}
J
cp "$s" "$work/original.json"
inst
check "keeps unrelated settings" '[ "$(q .model)" = opus ] && [ "$(q ".permissions.allow[0]")" = "Bash(npm test)" ]' "$(cat "$s")"
check "keeps the user's own Stop, Notification and PreToolUse hooks" \
  '[ "$(q ".hooks.Stop[0].hooks[0].command")" = "echo mine" ] && [ "$(q ".hooks.Notification[0].hooks[0].command")" = my-notify ] && [ "$(q ".hooks.PreToolUse[0].hooks[0].command")" = guard.sh ]' "$(cat "$s")"
check "appends its own hooks after the user's" '[ "$(q ".hooks.Stop | length")" = 2 ] && [ "$(q ".hooks.Notification | length")" = 2 ]' "$(cat "$s")"
b="$(ls "$cfg"/settings.json.bak-* 2>/dev/null | head -n 1)"
check "writes a backup identical to the original first" '[ -n "$b" ] && cmp -s "$b" "$work/original.json"'

# 3. running twice does not duplicate
inst
check "second install does not add duplicates" '[ "$(q ".hooks.Stop | length")" = 2 ] && [ "$(q ".hooks.Notification | length")" = 2 ]' "$(cat "$s")"

# 4. --with-idle adds idle_prompt
inst --with-idle
check "--with-idle adds idle_prompt to the matcher" 'q ".hooks.Notification[1].matcher" | grep -q "|idle_prompt$"' "$(cat "$s")"

# 5. our handler inside a user's group: only our handler goes
jq --arg c "bash '$cfg/claude-code-sound-notification/notify.sh'" \
  '.hooks.Stop[0].hooks += [{"type":"command","command":$c}]' "$s" > "$work/t" && cat "$work/t" > "$s"
inst --uninstall
check "uninstall restores the user's hooks exactly" \
  '[ "$(jq -S .hooks "$s")" = "$(jq -S .hooks "$work/original.json")" ]' "$(jq -c .hooks "$s")"
check "uninstall keeps unrelated settings" '[ "$(jq -S . "$s")" = "$(jq -S . "$work/original.json")" ]' "$(cat "$s")"
check "uninstall removes the script folder" '[ ! -e "$cfg/claude-code-sound-notification" ]'

# 6. uninstall on a fresh install leaves no empty hooks object behind
rm -rf "$cfg"; mkdir -p "$cfg"; echo '{"theme":"dark"}' > "$s"
inst; inst --uninstall
check "install then uninstall gives back the same file" '[ "$(jq -cS . "$s")" = "{\"theme\":\"dark\"}" ]' "$(cat "$s")"

# 7. uninstall with nothing installed changes nothing
before="$(cat "$s")"; inst --uninstall; rc=$?
check "uninstall with nothing installed exits 0 and changes nothing" '[ $rc -eq 0 ] && [ "$(cat "$s")" = "$before" ]'

# 8. invalid JSON is never touched
echo '{"theme": "dark",' > "$s"; cp "$s" "$work/broken"
inst; rc=$?
check "refuses invalid settings.json without changing it" '[ $rc -ne 0 ] && cmp -s "$s" "$work/broken"' "$(cat "$work/out")"

# 9. unexpected hooks shape is never touched
echo '{"hooks": {"Stop": "oops"}}' > "$s"; cp "$s" "$work/odd"
inst; rc=$?
check "refuses a hooks section with an unexpected shape" '[ $rc -ne 0 ] && cmp -s "$s" "$work/odd"' "$(cat "$work/out")"

# 10. symlinked settings.json stays a symlink
rm -rf "$cfg"; mkdir -p "$cfg" "$work/dotfiles"; echo '{}' > "$work/dotfiles/settings.json"
ln -s "$work/dotfiles/settings.json" "$s"
inst
check "a symlinked settings.json stays a symlink and the target gets the hooks" \
  '[ -L "$s" ] && [ "$(jq ".hooks.Stop | length" "$work/dotfiles/settings.json")" = 1 ]'

# 11. no jq: clear message, nothing changed
nojq="$work/nojq"; mkdir -p "$nojq"
for t in bash cat sed dirname date cp mkdir; do ln -s "$(command -v "$t")" "$nojq/$t"; done
rm -rf "$cfg"; mkdir -p "$cfg"; echo '{}' > "$s"
CLAUDE_CONFIG_DIR="$cfg" PATH="$nojq" bash "$install" >"$work/out" 2>&1; rc=$?
check "without jq it stops with an install hint" '[ $rc -ne 0 ] && grep -q "jq is needed" "$work/out" && [ "$(cat "$s")" = "{}" ]' "$(cat "$work/out")"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
