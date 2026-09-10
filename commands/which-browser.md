---
description: Show which connected Chrome browser is physically on this machine
---

Work out which connected Chrome browser actually runs on this machine, and report it.

1. Call `mcp__claude-in-chrome__list_connected_browsers`.
2. Run the detector over every deviceId it returned:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/find-local-device.sh" <every deviceId, space separated>
   ```

3. Report a short table of all connected browsers with, for each one, whether
   its deviceId was found in a browser profile on this machine. Name the
   browser and profile for the match (for example "Brave, Default").
4. State the conclusion:
   - exactly one match: name it and say that is the browser that will be used.
   - zero matches: say no connected browser lives on this machine and ask which one to use.
   - several matches: list them and ask which one to use.

Do not call `select_browser` or `switch_browser` as part of this command, and do
not use the `isLocal` field in your reasoning, it is unreliable.
