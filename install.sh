#!/usr/bin/env bash
# Add (or remove) Claude Code hooks that play a sound when Claude finishes or needs your input.
#
#   bash install.sh                 install, or update an earlier install
#   bash install.sh --with-idle     also ping when Claude has waited about a minute for your reply
#   bash install.sh --uninstall     remove only the hooks this script added
#
# It MERGES into ~/.claude/settings.json with jq and never overwrites your other settings
# or hooks. A timestamped backup of settings.json is written before every change.
# Hook reference: https://code.claude.com/docs/en/hooks
set -euo pipefail

raw="https://raw.githubusercontent.com/heardlabs/claude-code-sound-notification/main"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config_dir/settings.json"
dest="$config_dir/claude-code-sound-notification"
script="$dest/notify.sh"
matcher="permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input"

mode="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) mode="uninstall" ;;
    --with-idle) matcher="$matcher|idle_prompt" ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null || true; exit 0 ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 64 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is needed to edit settings.json safely." >&2
  echo "  macOS: brew install jq    Debian/Ubuntu: sudo apt install jq    Windows: winget install jqlang.jq" >&2
  exit 69
fi

# jq: is this handler one of ours? Our command is always "bash <path>/claude-code-sound-notification/notify.sh",
# optionally quoted and optionally followed by --codex.
ours_def='def ours: ((.command? // "") | tostring | test("^bash +[\"'"'"']?[^\"'"'"']*claude-code-sound-notification/notify\\.sh[\"'"'"']?( +--codex)?$"));'

# jq: remove our handlers from the events listed in $ev (all events when $ev is empty).
# Matcher groups and event lists are deleted only when removing our handler left them empty.
strip="$ours_def"'
  def group_has_ours: ((.hooks? // []) | type == "array") and any((.hooks? // [])[]; ours);
  if (.hooks | type) == "object" then
    .hooks |= with_entries(
      if (($ev | length) == 0 or (.key as $k | $ev | index($k)))
         and (.value | type) == "array" and any(.value[]; group_has_ours) then
        .value |= map(if group_has_ours then (.hooks |= map(select(ours | not))) | select(.hooks | length > 0) else . end)
        | select(.value | length > 0)
      else . end)
    | if .hooks == {} then del(.hooks) else . end
  else . end'

add='
  .hooks = (.hooks // {})
  | .hooks.Stop = ((.hooks.Stop // []) + [{"hooks": [{"type": "command", "command": $cmd, "async": true}]}])
  | .hooks.Notification = ((.hooks.Notification // []) + [{"matcher": $matcher, "hooks": [{"type": "command", "command": $cmd, "async": true}]}])'

has_ours() { [ -s "$settings" ] && jq -e "$ours_def"' [.. | objects | select(has("command")) | select(ours)] | length > 0' "$settings" >/dev/null 2>&1; }

check_settings() {
  [ -s "$settings" ] || return 0   # missing or empty: treated as {}
  if ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$settings" >/dev/null 2>&1; then
    echo "install.sh: $settings is not valid JSON. Fix it first; nothing was changed." >&2; exit 65
  fi
  if ! jq -e '(.hooks == null or (.hooks | type) == "object")
              and ((.hooks.Stop // []) | type) == "array"
              and ((.hooks.Notification // []) | type) == "array"' "$settings" >/dev/null 2>&1; then
    echo "install.sh: the \"hooks\" section of $settings has an unexpected shape. Nothing was changed." >&2; exit 65
  fi
}

backup() {
  [ -f "$settings" ] || return 0
  local b; b="$settings.bak-$(date +%Y%m%d-%H%M%S)"
  [ -e "$b" ] && b="$b-$$"
  cp -p "$settings" "$b"
  echo "Backed up $settings to $b"
}

# write <jq args...>: run jq over settings.json into a temp file, check it, then copy it back
# in place (cat keeps a symlinked settings.json and its permissions intact).
write() {
  local tmp ok=1; tmp="$(mktemp "$config_dir/.settings.json.XXXXXX")"
  if [ -s "$settings" ]; then jq "$@" "$settings" > "$tmp" || ok=0; else echo '{}' | jq "$@" > "$tmp" || ok=0; fi
  if [ "$ok" = 0 ] || ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; echo "install.sh: jq failed; $settings was not changed." >&2; exit 70
  fi
  cat "$tmp" > "$settings"
  rm -f "$tmp"
}

if [ "$mode" = "uninstall" ]; then
  check_settings
  if has_ours; then
    backup
    write --argjson ev '[]' "$strip"
    echo "Removed the sound notification hooks from $settings. Your other hooks are untouched."
  else
    echo "No sound notification hooks found in $settings."
  fi
  rm -rf "$dest"
  exit 0
fi

mkdir -p "$config_dir"
check_settings
case "$dest" in *"'"*|*'"'*) echo "install.sh: the path $dest contains a quote character; set CLAUDE_CONFIG_DIR to a simpler path." >&2; exit 64 ;; esac

# 1. Put notify.sh somewhere stable, so the hooks keep working if this folder is deleted.
mkdir -p "$dest"
src="${BASH_SOURCE[0]:-}"
if [ -n "$src" ] && [ -f "$src" ] && [ -f "$(dirname "$src")/notify.sh" ]; then
  cp "$(dirname "$src")/notify.sh" "$script.new"
else
  curl -fsSL "$raw/notify.sh" -o "$script.new"
fi
mv "$script.new" "$script"
chmod +x "$script"

cmd="bash '$script'"

# 2. Merge the hooks: drop an earlier copy of ours from Stop and Notification, then append a
#    fresh one. Hooks you added yourself elsewhere (say PermissionRequest) are left alone.
backup
write --argjson ev '["Stop","Notification"]' --arg cmd "$cmd" --arg matcher "$matcher" "$strip | $add"

echo "Added a Stop hook (finished) and a Notification hook (needs your input) to $settings."
if jq -e '.disableAllHooks == true' "$settings" >/dev/null 2>&1; then
  echo "Note: \"disableAllHooks\" is true in $settings, so no hooks run until you change it."
fi
cat <<EOF

Try the sounds now:   bash '$script' --test
Mute for a while:     touch '$dest/mute'   (rm it to unmute)
Uninstall:            curl -fsSL $raw/install.sh | bash -s -- --uninstall

Claude Code picks up settings changes on its own. Type /hooks in Claude Code to see them;
if they are not listed after a few seconds, restart the session.
EOF
