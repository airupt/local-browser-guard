#!/usr/bin/env bash
# PreToolUse on mcp__claude-in-chrome__select_browser.
# Allows the call only when the requested deviceId is physically present in a
# browser profile on this machine.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_json.sh"

payload="$(cat)"
[ "${LBG_ALLOW_UNVERIFIED:-0}" = "1" ] && exit 0

device_id="$(json_get "$payload" '.tool_input.deviceId')"
if [ -z "$device_id" ]; then
  device_id="$(printf '%s' "$payload" | grep -oE "$UUID_RE" | tail -1)"
fi

if [ -z "$device_id" ]; then
  emit_deny "local-browser-guard could not read a deviceId from this select_browser call. Call list_connected_browsers first and select a deviceId that the detector found on this machine."
  exit 0
fi

report="$("$DIR/find-local-device.sh" "$device_id" 2>/dev/null)"
status=$?

if [ "$status" -eq 0 ]; then
  exit 0   # exactly one local match, and it is this id
fi

emit_deny "local-browser-guard blocked select_browser for $device_id: that deviceId is not stored in any browser profile on this machine, so it belongs to someone else's Chrome.

Detector output:
$report

Run list_connected_browsers again and select the deviceId the detector does find locally. Do not trust the isLocal field. If nothing matches, stop and ask the user which browser to use."
exit 0
