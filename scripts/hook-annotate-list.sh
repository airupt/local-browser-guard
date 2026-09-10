#!/usr/bin/env bash
# PostToolUse on mcp__claude-in-chrome__list_connected_browsers.
# Runs the local-profile check on whatever ids came back and hands Claude the
# answer, so the choice is made from disk evidence rather than from isLocal.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_json.sh"

payload="$(cat)"

# Scan the tool response only; the hook envelope carries a session_id and a
# tool_use_id that are not browser deviceIds.
response="$(json_get "$payload" '.tool_response')"
[ -z "$response" ] && response="$payload"

ids="$(printf '%s' "$response" | grep -oE "$UUID_RE" | sort -u)"
[ -z "$ids" ] && exit 0

# shellcheck disable=SC2086
report="$("$DIR/find-local-device.sh" $ids 2>/dev/null)"
status=$?

case "$status" in
  0)
    match_id="$(printf '%s' "$report" | grep -oE '"deviceId":"'"$UUID_RE" | head -1 | grep -oE "$UUID_RE")"
    detail="$(printf '%s' "$report" | sed 's/.*"matches":\[//; s/\]}$//')"
    emit_context "local-browser-guard: exactly one of the connected deviceIds is stored in a browser profile on this machine.

Use it: select_browser with deviceId $match_id
Evidence: $detail

Do not call switch_browser, it is blocked. Do not use the isLocal field to decide, it is unreliable. No need to ask the user which browser to use, the match is unambiguous."
    ;;
  3)
    emit_context "local-browser-guard: NONE of the connected deviceIds were found in any browser profile on this machine, so every listed browser appears to belong to another machine on this account.

Detector output: $report

Stop here and ask the user which browser to use. Do not guess from isLocal and do not call switch_browser."
    ;;
  4)
    emit_context "local-browser-guard: MORE THAN ONE connected deviceId was found in a browser profile on this machine.

Detector output: $report

Stop here and ask the user which of these browsers to use, listing the browser and profile of each match. Do not guess and do not call switch_browser."
    ;;
  *)
    emit_context "local-browser-guard: the local profile scan could not run ($report). Ask the user which browser to use rather than guessing from isLocal."
    ;;
esac
exit 0
