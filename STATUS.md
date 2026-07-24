# STATUS.md — Current Proven Project State
Last updated: 2026-07-23

---

## Active Phase
**Phase 1: Hollow-to-Hollow**

---

## Proven Facts (as of 2026-07-23)

### Infrastructure
- ✅ Two separate Hollow installations exist on this machine:
  - Host: `C:\GoW2Hollow\Gears of War 2 - Hollow`
  - Client: `C:\GoW2Hollow\Gears of War 2 - Hollow - Client2`
  - Client2 uses directory junctions for 11 GB CookedPC assets (zero additional disk use).
- ✅ Both instances launch independently from separate `GoW2Hollow_Launcher.exe` executables.
- ✅ Each instance writes to its own separate log file:
  - Host log: `Gears of War 2 - Hollow\GearGame\Logs\Launch.log`
  - Client log: `Gears of War 2 - Hollow - Client2\GearGame\Logs\Launch.log`
- ✅ `LaunchDualSystemLink.ps1` positions Instance 1 on Monitor 2 (Top Screen: X=-1074, Y=-1080)
  and Instance 2 on Monitor 1 (Main Screen: X=0, Y=0).
- ✅ Both instances reach the main menu independently without crash.

### Current Build
- ✅ Package SHA-256 (Experimental Build): `8305DDDF7632F46410346A83FA61247771B0945B8FDEE4E783F604B834E350E1`
- ✅ Compiled using safe compiler command (`GoW2Hollow.exe make`) in Build Sandbox.
- ✅ Package deployed and verified to both Host and Client live directories.
- ✅ Baseline SHA-256: `166BDDF5275044D6357CE0AD60A550EAE2064BDB58C77276E1172BEAA96992E8`

### Test Harness Implemented
- ✅ `exec function HostParty()` implemented in `src\SystemLinkMod\Classes\SystemLinkConsole.uc`.
- ✅ `exec function SearchLAN()` implemented in `src\SystemLinkMod\Classes\SystemLinkConsole.uc`.
- ✅ `exec function JoinLocal()` implemented in `src\SystemLinkMod\Classes\SystemLinkConsole.uc`.
- ✅ `exec function ConnectIP(string TargetIP)` implemented in `src\SystemLinkMod\Classes\SystemLinkConsole.uc`.

### Direct Connection
- ✅ Direct IP connection (Hollow-to-Hollow) is fully functional. The client successfully loaded into the host's map and synchronized gameplay via `open 127.0.0.1` (or via `JoinLocal`).



---

## Historical Evidence (not retested — treat as historical until confirmed)
- Client instance previously logged `LANB_NotUsingLanBeacon` for created session.
- Client previously dispatched UDP broadcast on port 14001 (`Results=0`).
- No host reply was observed in any packet capture or log session.
- Hollow-to-Hollow discovery and party joining are NOT yet working.

---

## Outstanding Blockers
- Hollow-to-Hollow LAN discovery (Server Browser) has not yet been achieved.

### Diagnostics Note: Same-Machine UDP Loopback Test (2026-07-24)
- **Observed Evidence**: Standalone PowerShell scripts binding to port 14001 successfully looped back and received all payloads:
  - ✅ Local Loopback (`127.0.0.1` -> `TEST_LOCAL_LOOPBACK`)
  - ✅ LAN Subnet Broadcast (`10.0.0.255` -> `TEST_LAN_BROADCAST`)
  - ✅ Generic Broadcast (`255.255.255.255` -> `TEST_GENERIC_BROADCAST`)
- **Conclusion**: The Windows network stack and Firewall successfully support local loopback of both generic and subnet directed UDP broadcasts on port 14001. Therefore, the failure of Hollow-to-Hollow discovery is not an OS-level networking limitation, but rather an engine/IpDrv-specific issue (likely socket port sharing / `SO_REUSEADDR` or port binding conflicts when multiple instances run simultaneously).

---

## Port Binding Hypothesis
- **Configuration Exposure**: The UDP beacon port is exposed via the `LanAnnouncePort` key under the `[SystemLinkMod.SystemLinkLANGameInterface]` section in `GearEngine.ini` (inheriting from `OnlineGameInterfaceImpl`).
- **Contention Mechanics**: Under default settings, both Host and Client attempt to bind to `14001` simultaneously. Without `SO_REUSEADDR` support inside UE3's native socket wrapper, the second instance fails to bind to the port or fails to receive loopback broadcast frames.
- **Proposed Resolution**:
  - Configure the Host to advertise on port `14001` (default).
  - Configure the Client to listen on port `14002`.
  - Use a simple standalone 2-way UDP relay proxy to bridge communication between `14001` and `14002` on the local loopback interface, avoiding port contention while preserving packet exchange.

### Diagnostics Note: Standalone UDP Port Relay Verification (2026-07-24)
- **Observed Evidence**: Standalone relay script `UdpPortRelay.ps1` configured with Host on `14001` and Client on `14002` was executed successfully. Senders and listeners successfully exchanged packets:
  - ✅ Host (14001) -> Client (14002) relay: packet sent to `14001` was successfully received on `14002` prepended with loop-guard marker `0xF5`.
  - ✅ Client (14002) -> Host (14001) relay: packet sent to `14002` was successfully received on `14001` prepended with loop-guard marker `0xF5`.
  - ✅ `SO_REUSEADDR` Bindings: verified that multiple listeners can share the ports simultaneously.
  - ✅ Loop Protection: verified that loop-guard marker (`0xF5`) and outbound source port matching successfully prevent infinite packet loops.

---

## Live Port-Isolation Test Results (2026-07-24)
- **Status**: 🔴 FAILED (Discovery not working)
- **Observed Failures**:
  - Both Host and Client sessions got stuck on their respective "refresh" (updating network settings) pages during LAN search.
  - The Client's server browser list did not show the Host's session.
  - Screen positioning issue: both game instances launched on the same monitor instead of being separated onto top and bottom screens.
- **Observed Successes**:
  - Direct IP connection (`open 127.0.0.1` or `JoinLocal`) remains fully functional.

---

## Config Deployment Verification (2026-07-24)
- **Host Deployed Config**: `C:\GoW2Hollow\Gears of War 2 - Hollow\GearGame\Config\GearEngine.ini` -> `LanAnnouncePort=14001` (Correct)
- **Client Deployed Config**: `C:\GoW2Hollow\Gears of War 2 - Hollow - Client2\GearGame\Config\GearEngine.ini` -> `LanAnnouncePort=14002` (Correct)
- **Workspace-to-Deployed Sync**: 100% agreement.
- **Engine Runtime Execution Agreement**:
  - **Client**: ✅ Matches config. Log shows re-binding from default `14001` to `14002` during search: `DevOnline: Listening for lan beacon requestes on 14002`.
  - **Host**: ❌ Mismatch. Log does not show the Host ever binding or listening on `14001`.
- **Root Cause**: The Host's LAN beacon was never initialized because `SystemLinkConsole.uc`'s `ShouldUseLocalHostStartBypass` gate blocked the host travel bypass (it requires `bLANSessionCreated` to be true, which is only set when hosting starts from the LAN Browser scene, not the Party Lobby).

---

## GC and Hook Verification & Fix (2026-07-24)
- **GC/Travel Crash Fix**: 
  - Verified that `HookedPartyScene` and `HookedLANScene` were previously not cleared during level travel transitions, causing garbage collection to leak and crash on Host shutdown.
  - Implemented event `NotifyLevelChange` in `SystemLinkConsole.uc` to clean up scene references on all transitions.
  - Redundantly cleared references inside `OnLocalSystemLinkProfileWriteComplete` and `OnRealLANPartyCreated` right before travel calls.
- **Hook Re-Attachment**: 
  - Verified that `PostRender_Console` runs every frame and re-attaches `MatchmakeButton.OnClicked` to `OnLocalSystemLinkStartClicked` automatically for any new scene instance post-travel. No changes needed.





