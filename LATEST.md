# LATEST.md — Latest Session Handoff
Last updated: 2026-07-24

---

## Active Branch
`agent/claude/fix-udp-relay-marker-corruption` (private repo; not yet merged to `main`)

---

## Summary of Completed Work
1. **Verified prior session's fixes are actually deployed** (not just documented):
   - Both the state-gating fix (Party Lobby hosting now sets up a real LAN session) and the GC/travel-crash fix (`NotifyLevelChange` clears transient scene references) live in one commit and are compiled into the build currently deployed to both Host and Client — confirmed by hashing the live packages directly rather than trusting docs.
2. **Found and fixed a UDP relay bug**:
   - `tools/diagnostics/UdpPortRelay.ps1` was prepending a loop-guard marker byte to every packet it forwarded to the real destination port, and never stripping it before delivery — meaning the game engine's socket received every relayed LAN-beacon packet with one extra corrupting byte on the front.
   - This is a plausible root cause for the client's `Results=0` discovery failure, separate from the (already-fixed) port-binding issue.
   - Fixed: loop prevention now relies only on the pre-existing, non-destructive source-port check. Verified standalone (no game) that packets now relay byte-for-byte unmodified.
   - **Not yet tested against the real game** — that requires a live dual-instance test.

---

## Next Recommended Step
Run a live dual-instance test (Host + Client + fixed relay) and capture Host/Client `Launch.log` plus relay console output to determine whether the client's server browser now lists the host's session. This is the next attempt at passing the Phase 1C gate (Hollow-to-Hollow LAN discovery).
