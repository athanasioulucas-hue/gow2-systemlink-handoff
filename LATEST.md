# LATEST.md — Latest Session Handoff
Last updated: 2026-07-24

---

## Active Branch
`agent/antigravity/hollow-systemlink-harness`

---

## Summary of Completed Work
1. **Live Test Execution**: Ran a live Hollow-to-Hollow LAN discovery test with `UdpPortRelay.ps1` running and configuration overlays deployed (Host on `14001`, Client on `14002`).
2. **Observed Results**:
   - Both game instances got stuck on the "refresh" (updating network settings) pages during search.
   - Host's session was not discovered by the Client.
   - Screen positioning failed to separate the windows onto different monitors (both started on the same monitor).
   - Direct connection via direct IP (`open 127.0.0.1` / `JoinLocal`) remains fully functional.
3. **Log Examination**:
   - Host log reported a Garbage Collection crash on shutdown/error: `Critical: appError called: World GearStart.TheWorld not cleaned up by garbage collection!` due to transient scene references in `SystemLinkConsole`.
   - Client log showed `LAN SEARCH COMPLETE: Success=True Results=0` but did not locate any sessions.

---

## Proven Findings
- Direct IP connection bypasses the search/discovery phase and works correctly.
- Live UDP relay test was unsuccessful in establishing discovery between Host on `14001` and Client on `14002`.

---

## Next Recommended Step
Address the GC memory leak in `SystemLinkConsole.uc` where `HookedPartyScene` prevents garbage collection of the `World` upon map transition/exit. Then inspect if game packet contents are rejected by the `0xF5` byte header.
