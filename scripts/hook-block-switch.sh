#!/usr/bin/env bash
# PreToolUse on mcp__claude-in-chrome__switch_browser.
#
# switch_browser broadcasts a pairing prompt to every Chrome extension signed
# into the account, including other people's. On a shared account that is how
# a session ends up driving a colleague's browser. Always refuse it.
set -uo pipefail
cat >/dev/null
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_json.sh"

if [ "${LBG_ALLOW_SWITCH:-0}" = "1" ]; then exit 0; fi

emit_deny "switch_browser is blocked by local-browser-guard: it broadcasts a pairing request to every Chrome extension on this account, including other people's machines.

Pick the browser deterministically instead:
  1. mcp__claude-in-chrome__list_connected_browsers
  2. run the detector on the returned deviceIds (the PostToolUse hook does this for you, or run /which-browser)
  3. mcp__claude-in-chrome__select_browser with the one deviceId found in a browser profile on this machine

Ignore the isLocal field, it is not reliable. If the detector reports zero or more than one match, stop and ask the user which browser to use."
exit 0
