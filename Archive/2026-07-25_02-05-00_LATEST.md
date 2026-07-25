# LATEST.md — Latest Session Handoff
Last updated: 2026-07-25

---

## Active Branch
`agent/claude/fix-notifylevelchange-signature-regression` (private repo; not yet merged to `main`)

---

## Summary of Completed Work
1. **Live test crashed both instances.** After a successful direct-IP join, clicking "Start Match" crashed both Host and Client with a fatal `World not cleaned up by garbage collection` error.
2. **Root cause found**: an earlier commit, despite being labeled as a documentation-only change, had silently changed the signature of an UnrealScript event responsible for clearing stale scene references during level transitions. A signature mismatch means an event override is never actually called by the engine — it compiled without any error, but simply stopped firing. Confirmed by grepping session logs: zero occurrences of that event's log line across roughly ten level transitions.
3. **Fixed**: reverted the signature to match the originally-working version exactly. Compiled clean, deployed and hash-verified to both Host and Client. Not yet tested live.
4. **Also confirmed**: LAN discovery (host/search) still returns zero results on both instances even with the earlier relay fix in place — that part of the project remains unresolved and needs fresh investigation.

---

## Next Recommended Step
Live test: relay running, dual launch, direct-IP join, Host clicks Start Match, confirm no crash on either side and that the level-transition log line now actually appears. If clean, shift focus to LAN discovery, which is now the main remaining blocker for Phase 1C.
