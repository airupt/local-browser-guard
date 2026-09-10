# Sourced by the hook scripts. Reads a value out of the hook's stdin JSON
# without assuming jq is installed.
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

json_get() {  # json_get <payload> <dotted.path>
  local payload="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$path // empty" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json,sys
path=sys.argv[1].lstrip(".").split(".")
try: cur=json.load(sys.stdin)
except Exception: sys.exit(0)
for k in path:
    if isinstance(cur,dict) and k in cur: cur=cur[k]
    else: sys.exit(0)
print(cur if isinstance(cur,str) else json.dumps(cur))
' "$path" 2>/dev/null && return 0
  fi
  return 0
}

emit_deny() {  # emit_deny <reason>
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
      "$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')"
  fi
}

emit_context() {  # emit_context <text>
  local text="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$text" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
      "$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')"
  fi
}

# ---- session state -------------------------------------------------------
# A marker file records that this session verified its browser choice, so the
# other claude-in-chrome tools can be gated until that has happened.
lbg_marker_path() {  # lbg_marker_path <payload>
  local sid
  sid="$(json_get "$1" '.session_id')"
  [ -z "$sid" ] && return 1
  case "$sid" in *[!A-Za-z0-9_-]*) sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')" ;; esac
  local dir="${TMPDIR:-/tmp}/local-browser-guard"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s/%s.selected' "$dir" "$sid"
}
