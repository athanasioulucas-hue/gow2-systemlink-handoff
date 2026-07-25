# LATEST.md — Latest Session Handoff
Last updated: 2026-07-25

---

## Active Branch
`agent/claude/fix-lan-browser-autosearch-loop` (private repo; not yet merged to `main`)

---

## Summary of Completed Work
1. Live testing surfaced a usability regression: the LAN Browser menu chimed continuously with no stable window to interact with it, and the manual search command appeared to do nothing.
2. Root cause: the automatic search-on-open feature was re-triggering itself every single frame after each search completed, instead of firing once. Fixed — it now fires exactly once per visit to that menu.
3. **Major finding for the core discovery problem**: while that loop was active, watched the relay's live output during an actual game session for the first time (previously only tested standalone) and confirmed real traffic crossing in both directions. This rules out two prior theories about why discovery fails and narrows the problem to somewhere past basic network transport — likely how the receiving instance validates or correlates a reply, not confirmed yet.
4. New build compiled clean, deployed and verified to both instances. Not yet tested live.

---

## Next Recommended Step
Retest LAN discovery now that the menu no longer loops — this should give one clean, isolated search attempt instead of continuous noise, making it much easier to tell what's actually happening. If it still fails with confirmed relay traffic, the next step is likely a raw network packet capture to see exactly what's being sent and rejected.
