**Backlit 0.2.7**

### New

- Optional local MCP control lets compatible AI assistants check status and control power, brightness and mode.
- Configurable brightness-up/down shortcuts.
- Experimental Shift + hardware brightness keys, off by default and pending physical keyboard validation.

### Improvements

- Improved brightness-limit override application and restoration.
- Incomplete closed-lid recovery now blocks light control until resolved.
- Turning the light off or quitting during recovery prevents automatic restart.

### What to know

- Closed-lid lighting is capped at 30 minutes and may keep the built-in display lit. Independent closed-lid brightness is still being evaluated.
- macOS may ask you to re-enable Backlit under Input Monitoring after updating.

This build is ad-hoc signed with the hardened runtime, not Developer ID signed or notarized. See [validation](https://github.com/t0nyz0/Backlit/blob/v0.2.7/docs/VALIDATION.md) for completed checks and remaining hardware acceptance.
