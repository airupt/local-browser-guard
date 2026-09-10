---
name: local-browser-guard
description: How to choose which connected Chrome browser to drive with the claude-in-chrome tools on a shared Claude account. Use before calling list_connected_browsers, select_browser or switch_browser, or whenever more than one browser is connected, a browser action lands in the wrong window, or you are about to ask the user which browser to pick. Identifies the browser on this machine from its deviceId in the local browser profiles instead of the unreliable isLocal flag.
---

# Choosing the right browser

On a Claude account shared by several people, `list_connected_browsers` returns
every Chrome extension signed into the account, not just the ones on this
computer. Two fields tempt you into a wrong guess:

- **`isLocal`** is not reliable. It routinely reports `true` for browsers on
  other people's machines. Ignore it entirely.
- **`osPlatform`** only tells you the operating system, and colleagues on the
  same OS are indistinguishable by it.

There is one signal that cannot be faked from another machine: the Chrome
extension writes its `bridgeDeviceId` into the browser profile on the computer
it runs on. If a deviceId is present in a browser profile on this disk, that
browser is here. If it is not, it is someone else's.

## Procedure

1. Call `mcp__claude-in-chrome__list_connected_browsers`.
2. Check every returned deviceId against the local browser profiles:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/find-local-device.sh" <id1> <id2> <id3> ...
   ```

   The plugin's PostToolUse hook normally runs this for you and reports the
   answer straight after step 1, so run it by hand only if that context is
   missing. `/which-browser` does the same on demand.
3. Act on the number of matches:

   | Matches | Do |
   |---------|-----|
   | exactly 1 | Call `select_browser` with that deviceId. Do not ask the user, the answer is unambiguous. |
   | 0 | Stop. Tell the user no connected browser was found on this machine and ask which one to use. |
   | 2 or more | Stop. List the matching browsers and profiles and ask the user which one to use. |

4. Never call `switch_browser`. It broadcasts a pairing prompt to every Chrome
   extension on the account, which is how a session ends up driving a
   colleague's browser. The plugin blocks it.

## What the detector looks at

| OS | Profile root |
|----|--------------|
| macOS | `~/Library/Application Support` |
| Windows | `%LOCALAPPDATA%` and `%APPDATA%` |
| Linux | `~/.config`, plus `~/snap` and `~/.var/app` when present |

Under those roots it scans every Chromium profile's `Local Extension Settings`
and `Sync Extension Settings` directory, across all installed browsers (Chrome,
Brave, Edge, Arc, Vivaldi, Opera, Chromium, Dia, Comet and so on) and all
profiles (`Default`, `Profile 1`, ...). If a supplied id is not found there, it
widens to the whole profile root before reporting a miss, so a zero result is a
real zero.

Exit codes: `0` one match, `3` no match, `4` several matches, `1` no profile
root found.

Run it with no arguments to list every Claude in Chrome deviceId stored on this
machine, which is useful when the browser list itself looks wrong.

## Enforcement

Guidance alone is not enough, so the plugin also enforces this:

- `switch_browser` is always denied.
- `select_browser` is denied unless the deviceId is found in a local profile.
- **Every other `claude-in-chrome` tool is denied until this session has done a
  verified `select_browser`.** A selection carried over from an earlier session
  never touches `select_browser` again, so without this gate it would keep
  driving whatever browser it was last pointed at. Expect the first browser
  request in a session to cost one `list_connected_browsers` plus one
  `select_browser`, and nothing after that.
- `list_connected_browsers` results are annotated with the local match.

Escape hatches, for the rare case where the machine genuinely needs to drive a
remote browser:

| Variable | Effect |
|----------|--------|
| `LBG_ALLOW_UNVERIFIED=1` | Allow `select_browser` for any deviceId |
| `LBG_ALLOW_SWITCH=1` | Allow `switch_browser` |
| `LBG_ALLOW_UNSELECTED=1` | Drop the session gate |
