# LATEST.md — Latest Session Handoff
Last updated: 2026-07-25

---

## Active Branch
`agent/claude/fix-notifylevelchange-signature-regression` (private repo; not yet merged to `main`)

---

## Summary of Completed Work
1. First crash-fix attempt (signature revert) retested live — crash recurred identically, and the event still never fired even with a hash-verified correct deployment. That assumption was wrong.
2. Found the real cause: the Party Lobby's Start Match button was only being redirected to this mod's own handler for parties created through its own LAN flow. A plain direct-IP join never satisfies that condition, so the mod never got a chance to clean up before the native game code traveled to a new map — causing the same fatal crash.
3. Fixed by always intercepting that button click and cleaning up proactively before handing off to native behavior for any party the mod doesn't need to handle itself. Compiled clean, deployed and hash-verified to both instances. Explicitly scoped: this fixes the hosting side of the crash; a second, differently-triggered crash on the joining side (from connection loss rather than a button click) remains open.
4. User redirected priority: the direct-IP testing was a useful diagnostic detour but isn't the actual goal — LAN discovery (the real System Link search/host flow) is, and it's still not working.

---

## Next Recommended Step
Shift focus to LAN discovery. Run a live host/search attempt while actually watching the relay's own console output in real time, to determine whether any traffic reaches the relay at all during a real attempt — this has only been inferred from a standalone (non-game) test so far, never directly observed live.
