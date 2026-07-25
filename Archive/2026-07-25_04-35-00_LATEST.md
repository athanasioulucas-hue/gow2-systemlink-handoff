# LATEST.md — Latest Session Handoff
Last updated: 2026-07-25

---

## Active Branch
`agent/claude/fix-createparty-button-disabled-during-search` (private repo; not yet merged to `main`)

---

## Summary of Completed Work
1. Major discovery: found that this build actually ships with real exported source code for the base game engine and full game (not just the mod), left over from earlier work and never noticed before. Recorded its location permanently for all future sessions.
2. Used it to definitively confirm one earlier fix was chasing something that was never real in the first place (not a bug introduced this session — it never worked, ever).
3. Used it to find and fix the actual cause of "have to spam the confirm button to host a lobby" — a UI element was being disabled during an unrelated background process, silently swallowing input.
4. The core mystery — why hosted games still aren't found by search — remains unresolved. Real engine source only goes so far; the actual native code logic isn't included, only its outward interface. Raw network packet inspection is still the most promising next step.

---

## Next Recommended Step
Live retest to confirm the button fix works (should respond immediately now, no repeated presses needed), then run the discovery test with the enhanced packet-logging relay actually watched, to see real network bytes instead of relying on inference from game logs.
