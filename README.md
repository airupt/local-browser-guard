# local-browser-guard

A Claude Code plugin that makes Claude drive **your** Chrome, not a colleague's.

## The problem

On a Claude account shared by several people, `list_connected_browsers` returns
every Chrome extension signed into that account, wherever it is running. The
response looks like this:

```json
[
  {"deviceId":"56801eb4-...","name":"Browser 1","osPlatform":"Windows","isLocal":false},
  {"deviceId":"e0769594-...","name":"Browser 2","osPlatform":"macOS","isLocal":true},
  {"deviceId":"94574c11-...","name":"Browser 3","osPlatform":"macOS","isLocal":true},
  {"deviceId":"90bacd86-...","name":"Browser 4","osPlatform":"macOS","isLocal":true},
  {"deviceId":"31ffc5ea-...","name":"Browser 5","osPlatform":"macOS","isLocal":true}
]
```

Four browsers claim `isLocal: true`. On the machine this was captured from,
exactly one of them was actually there. The flag is not trustworthy, the names
are generic, and `osPlatform` cannot separate two colleagues on the same OS.

So Claude guesses, or it calls `switch_browser`, which broadcasts a pairing
prompt to **every** extension on the account and waits for whoever clicks
Connect first. Both failure modes end the same way: your automation runs in
someone else's browser window.

## The fix

The Chrome extension stores its `bridgeDeviceId` inside the browser profile on
the machine it runs on:

```
~/Library/Application Support/BraveSoftware/Brave-Browser/Default/
  Local Extension Settings/fcoeoabgfenejglbffodgkkbkcdhcgfn/000124.ldb
  ...  bridgeDeviceId  90bacd86-4706-459b-9bf0-afc0a1002c6a
```

That trace cannot exist for a browser running on another machine. So the plugin
grabs every deviceId from `list_connected_browsers` and looks for it in the
browser profiles on this disk. The one it finds is the right one. In the list
above the scan returns exactly one hit, `90bacd86` (Brave, Default), and the
other four `isLocal: true` entries are correctly rejected.

## What it does

| Event | Behaviour |
|-------|-----------|
| `list_connected_browsers` returns | A PostToolUse hook scans the local profiles and tells Claude which deviceId is here, with the browser and profile as evidence |
| `select_browser` is called | A PreToolUse hook denies it unless that deviceId is in a profile on this machine |
| `switch_browser` is called | Always denied, no broadcast pairing |
| 0 or 2+ local matches | Claude is told to stop and ask you which browser to use |

The bundled skill teaches the same rule, so Claude follows it even in a session
where a hook does not fire, and `/which-browser` reports the answer on demand.

## Install

```bash
claude plugin marketplace add airupt/local-browser-guard
claude plugin install local-browser-guard@airupt-tools
```

Restart Claude Code. Verify with:

```bash
claude plugin details local-browser-guard
```

## Use

Nothing to do. Ask Claude to do anything in the browser and the browser choice
resolves itself:

```
> take a screenshot of example.com
```

To inspect the situation yourself:

```
> /which-browser
```

Or run the detector directly:

```bash
# which of these ids is on this machine
scripts/find-local-device.sh <id1> <id2> <id3>

# every Claude in Chrome deviceId stored on this machine
scripts/find-local-device.sh

# scan the entire profile root instead of just extension storage
scripts/find-local-device.sh --deep
```

Output is JSON:

```json
{"platform":"macos","scanned_roots":["/Users/you/Library/Application Support"],
 "scan_dir_count":2,"widened_scan":0,"candidates":5,"count":1,
 "matches":[{"deviceId":"90bacd86-4706-459b-9bf0-afc0a1002c6a","browser":"Brave",
             "profile":"Default","evidence":"/Users/you/Library/.../000124.ldb"}]}
```

Exit codes: `0` one match, `3` no match, `4` several matches, `1` no profile
root found.

## Where it looks

| OS | Profile roots |
|----|---------------|
| macOS | `~/Library/Application Support` |
| Windows | `%LOCALAPPDATA%`, `%APPDATA%` |
| Linux | `~/.config`, plus `~/snap` and `~/.var/app` when present |

Under those roots every Chromium profile is scanned, across all installed
browsers (Chrome, Chrome Beta/Dev/Canary, Brave, Edge, Arc, Vivaldi, Opera,
Chromium, Dia, Comet, Yandex and anything else Chromium based) and all profiles
(`Default`, `Profile 1`, and so on).

The fast path only reads each profile's `Local Extension Settings` and
`Sync Extension Settings` directories. If a supplied deviceId is not found
there, the scan widens to the whole profile root before reporting a miss, so a
zero result is a real zero rather than a wrong lookup path.

## Escape hatches

For the rare case where this machine genuinely has to drive a remote browser:

| Variable | Effect |
|----------|--------|
| `LBG_ALLOW_UNVERIFIED=1` | Allow `select_browser` for any deviceId |
| `LBG_ALLOW_SWITCH=1` | Allow `switch_browser` |
| `LBG_MAXDEPTH=<n>` | Directory depth for the profile search (default 8) |

## Requirements

- Claude Code with the `claude-in-chrome` MCP server connected
- `bash`, `grep`, `find`, `sed`, `awk`
- `jq` or `python3` for JSON parsing (both optional, there is a regex fallback)

On Windows the hooks run under Git Bash, which Claude Code uses by default.

## Layout

```
.claude-plugin/plugin.json          plugin manifest
.claude-plugin/marketplace.json     marketplace manifest
hooks/hooks.json                    hook wiring
scripts/find-local-device.sh        the detector
scripts/hook-annotate-list.sh       PostToolUse: list_connected_browsers
scripts/hook-guard-select.sh        PreToolUse: select_browser
scripts/hook-block-switch.sh        PreToolUse: switch_browser
skills/local-browser-guard/SKILL.md the rule, for Claude
commands/which-browser.md           /which-browser
```

## Privacy

Everything runs locally. The scan reads browser profile files to test for a
string match and never reads or transmits browsing data, cookies or
credentials. Only the matching file path is reported, as evidence.

## License

MIT
