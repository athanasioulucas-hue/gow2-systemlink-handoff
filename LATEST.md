# LATEST.md — Latest Session Handoff
Last updated: 2026-07-29

## 2026-07-29 Codex Update — C++ Memory Layout Confirmed & Native Function Hooking Verified

- **Active branch**: `agent/codex/browser-join-and-party-start`.
- Analyzed the memory layout of the real `UObject` array in `GoW2Hollow.exe` at static global address `0x02612E68`.
- Discovered custom field offsets in this build: `InternalIndex` (offset 4), `Outer` (offset 40), and `Name` (offset 44).
- Verified `GNames` is a flat table at static global address `0x02612E94` with name strings at offset 16 (0x10).
- Successfully resolved full object names (e.g. `"Core.Object.LogInternal"`) using custom offsets.
- Implemented and verified a dynamic function scanner that successfully hooks `Core.Object.LogInternal` (at `0x3225aa40`, execution pointer offset 84) and all subclasses/variations of `FindOnlineGames` / `CancelFindOnlineGames` (e.g. `Engine.OnlineGameInterface.FindOnlineGames` and `IpDrv.OnlineGameInterfaceImpl.FindOnlineGames`) at startup by dynamically rewriting their execution pointers at offset 84 in the `UFunction` struct.
- Restored original game files post-test (`restore_original.ps1`).

---

## Active Branch
`agent/codex/browser-join-and-party-start` (private repo; not yet merged to `main`)

---

## 1. Timestamp
2026-07-29 20:50 (EST)

## 2. Active Phase
Phase 2: Hollow-to-Xenia — connection PoC establishes UDP replication via `open 127.0.0.1:1000` but players remain stuck at `CONNECTING` due to native control-channel handshake rejection.

## 3. Exact Bounded Objective
Develop C++ memory hooking logic to scan for GObjects/GNames, hook the LAN subsystem functions, and verify native intercept capabilities.

## 4. Starting State
- GFWL script-level DLLBind has been ruled out due to compiler limitations.
- A proxy DLL setup (`steam_api.dll`) was configured in `C:\GoW2Hollow\SystemLinkProject\ProxyTest`.
- High-priority objective: Verify GObjects/GNames layout and test function pointer hijacking on native game functions (e.g. `LogInternal` and `FindOnlineGames`).

## 5. Commands and Actions Performed
- Developed proxy memory hook code inside `dllmain.cpp`.
- Compiled using `build_proxy.ps1` and deployed via `deploy_test.ps1`.
- Performed multiple live diagnostic runs of `GoW2Hollow.exe` to examine the object memory structure and verify offsets.
- Tightened `VerifyGObjects` validation by checking if the object's self-index matches its array position (`UObject->InternalIndex == i`).
- Hooked `Core.Object.LogInternal` and all variants of `FindOnlineGames` / `CancelFindOnlineGames` inside the game's startup sequence.
- Restored original game files post-test using `restore_original.ps1`.

## 6. Evidence Found
- **Static Global Addresses:** `GNames` is at `0x02612E94` and `GObjects` is at `0x02612E68`.
- **Custom Object Layout:**
  - `InternalIndex`: offset `4` (standard is 8)
  - `Outer`: offset `40` (standard is 12)
  - `Name`: offset `44` (standard is 16)
- **Names Table Structure:** `GNames` is a flat array, and string values reside at offset `16` (0x10) inside `FNameEntry`.
- **UFunction Layout:** The native C++ execution function pointer (`Func`) is located at offset `84` of the `UFunction` object structure.
- **Native Interception Hooking:** Successfully hijacked the execution path of the game's native functions (`LogInternal` at `0x3cdbec0` and `FindOnlineGames` variants at `0x5b6b568` / `0x5b85e50`) on startup by rewriting the `UFunction::Func` pointers.

## 7. Files Changed (this task)
- `C:\GoW2Hollow\SystemLinkProject\ProxyTest\dllmain.cpp`
- `STATUS.md`
- `CHANGELOG.md`
- `handoffs/LATEST.md`

## 8. Backup Paths
- `dllmain.cpp` is backed up implicitly by project version control.
- Original `steam_api.dll` is backed up as `steam_api_original.dll` in the game binaries directory.

## 9. Build Result
C++ proxy compiled successfully (`Success - steam_api.dll created`).

## 10. Deployment Result
Proxy successfully deployed and restored after live testing.

## 11. Test Result
Successfully verified layout offsets, object name resolution, and hooks for `LogInternal` and `FindOnlineGames` variants inside `proxy_test.log`.

## 12. Current Blocker
Hollow's native `IpDrv` network layer rejects the search results received from the discovery bridge over UDP due to validation issues in the packet content.

## 13. Recommended Next Action
Use the working native C++ hook framework to write logic that intercepts `FindOnlineGames` or search results delegates, and manually constructs and feeds local `OnlineGameSearchResult` objects directly into the game's search results list in memory, bypassing the buggy network serialization layer entirely.
