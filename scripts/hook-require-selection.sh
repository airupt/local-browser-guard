#!/usr/bin/env bash
# PreToolUse on every other mcp__claude-in-chrome__* tool.
#
# The select_browser guard only fires when a browser is actually being chosen.
# A selection left over from an earlier session would sail straight past it and
# keep driving the wrong window. This gate closes that: no browser tool runs
# until this session has verified its browser against the local profiles.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_json.sh"

payload="$(cat)"
[ "${LBG_ALLOW_UNSELECTED:-0}" = "1" ] && exit 0

tool="$(json_get "$payload" '.tool_name')"
case "$tool" in
  # The tools that do the choosing are guarded by their own hooks.
  *list_connected_browsers|*select_browser|*switch_browser) exit 0 ;;
esac

marker="$(lbg_marker_path "$payload")" || exit 0   # no session id, fail open
[ -f "$marker" ] && exit 0

emit_deny "local-browser-guard blocked ${tool:-this browser tool}: this session has not yet verified which connected browser is the one on this machine, and any selection carried over from an earlier session may point at someone else's Chrome.

Do this first:
  1. mcp__claude-in-chrome__list_connected_browsers
  2. mcp__claude-in-chrome__select_browser with the deviceId the guard reports as locally present

Then retry. Ignore the isLocal field, it is not reliable, and do not call switch_browser. If the guard finds zero or several local matches, stop and ask the user which browser to use."
exit 0
