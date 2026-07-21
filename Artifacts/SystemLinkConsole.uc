class SystemLinkConsole extends Console;

var transient GearUISceneFELobby_Party HookedPartyScene;
var transient GearUISceneFE_LAN HookedLANScene;

var transient bool bPartyHookLogged;
var transient bool bLANHookLogged;

var transient OnlineSubsystem GlobalOnlineSubsystem;
var transient OnlineSubsystemCommonImpl GlobalCommonSubsystem;
var transient OnlineGameInterfaceImpl LANGameInterface;

var transient OnlineGameInterface OriginalGameInterface;
var transient OnlineGameInterfaceImpl OriginalGameInterfaceImpl;

var transient int PendingLANControllerId;
var transient GearPartyGameSettings PendingLANSettings;
var transient bool bLANCreatePending;
var transient bool bLANSessionCreated;
var transient bool bLANPartySettingsRepairLogged;
var transient bool bLANBrowserSearchRequested;
var transient bool bLANBrowserSearchStarted;
var transient bool bLANJoinObserverInstalled;
var transient int LANBrowserSearchDelayFrames;
var transient bool bLANPostTravelProbePending;
var transient bool bAutoStartProcessed;
var transient int LANPostTravelProbeFrames;


/*
 * Runs every frame through the active console.
 */
event PostRender_Console(Canvas Canvas)
{
    super.PostRender_Console(Canvas);

    InstallPartyLobbyHook();
    RepairLANPartyGameSettings();
    ProbePostTravelLANBeacon();
    InstallLANBrowserHook();
    StartPendingLANBrowserSearch();
    AutoInitializeDirectListenHost();
    AutoInitializeClientSearch();
    ProcessAutoStartMode();
}


/*
 * CreateOnlineGame completes before ClientTravel begins, so its immediate
 * callback may be too early to prove whether IpDrv starts advertising once
 * GearPartyGame owns the listen world. Sample the same interface across the
 * transition and after the party lobby is active. The frame counter pauses
 * while no PartyLobby scene exists, so it cannot expire on a loading screen.
 * No old scene or WorldInfo reference is retained because that would prevent
 * garbage collection during travel.
 */
function ProbePostTravelLANBeacon()
{
    local OnlineGameSettings NativeSettings;
    local OnlineSubsystem CurrentSubsystem;

    if (!bLANPostTravelProbePending ||
        HookedPartyScene == None ||
        HookedPartyScene.GetWorldInfo() == None ||
        LANGameInterface == None)
    {
        return;
    }

    LANPostTravelProbeFrames++;

    if (LANPostTravelProbeFrames != 1 &&
        LANPostTravelProbeFrames != 60 &&
        LANPostTravelProbeFrames != 180 &&
        LANPostTravelProbeFrames != 360 &&
        LANPostTravelProbeFrames != 600)
    {
        return;
    }

    NativeSettings = LANGameInterface.GetGameSettings('Game');
    CurrentSubsystem =
        class'Engine.GameEngine'.static.GetOnlineSubsystem();

    LogInternal(
        "[SystemLinkMod] POST-TRAVEL LAN STATE: Frame=" $
        string(LANPostTravelProbeFrames) $
        " BeaconState=" $ string(LANGameInterface.LanBeaconState) $
        " HasGameSettings=" $ string(NativeSettings != None) $
        " IsLAN=" $
        string(NativeSettings != None && NativeSettings.bIsLanMatch) $
        " Advertise=" $
        string(NativeSettings != None &&
            NativeSettings.bShouldAdvertise) $
        " InterfaceStillGlobal=" $
        string(CurrentSubsystem != None &&
            CurrentSubsystem.GameInterface == LANGameInterface) $
        " NetMode=" $
        string(HookedPartyScene.GetWorldInfo().NetMode) $
        " World=" $ string(HookedPartyScene.GetWorldInfo()) $
        " WorldGame=" $
        string(HookedPartyScene.GetWorldInfo().Game)
    );

    if (LANPostTravelProbeFrames == 600)
    {
        bLANPostTravelProbePending = false;
    }
}


/*
 * Keep Hollow's concrete GearPartyGame and cooked lobby resources, but
 * repair its Xbox-style 'Party' lookup with the PC IpDrv 'Game' session.
 */
function RepairLANPartyGameSettings()
{
    local GearPartyGame_Base PartyGame;
    local GearPartyGameSettings ActiveLANSettings;

    if (!bLANSessionCreated || LANGameInterface == None ||
        HookedPartyScene == None ||
        HookedPartyScene.GetWorldInfo() == None)
    {
        return;
    }

    PartyGame = GearPartyGame_Base(
        HookedPartyScene.GetWorldInfo().Game
    );

    if (PartyGame == None)
    {
        return;
    }

    ActiveLANSettings = GearPartyGameSettings(
        LANGameInterface.GetGameSettings('Game')
    );

    if (ActiveLANSettings == None)
    {
        ActiveLANSettings = PendingLANSettings;
    }

    if (ActiveLANSettings == None)
    {
        return;
    }

    PartyGame.PartySettings = ActiveLANSettings;

    EnsureLANLocalPlayerReady(
        HookedPartyScene.GetWorldInfo()
    );

    if (!bLANPartySettingsRepairLogged)
    {
        bLANPartySettingsRepairLogged = true;

        LogInternal(
            "[SystemLinkMod] Repaired GearPartyGame PartySettings " $
            "from IpDrv Game session"
        );
    }
}


/*
 * Hollow's offline player interface leaves the local host with a zero
 * UniqueNetId and DLCFlag=-1. The stock party UI treats that PRI as a
 * still-connecting network player and refuses to start System Link.
 * Repair only the local host; real remote identities are never changed.
 */
function EnsureLANLocalPlayerReady(WorldInfo ActiveWorld)
{
    local PlayerController PC;
    local GearPRI PRI;
    local UniqueNetId ZeroId;
    local bool bChanged;

    if (ActiveWorld == None)
    {
        return;
    }

    foreach ActiveWorld.AllControllers(class'PlayerController', PC)
    {
        if (PC == None || !PC.IsLocalPlayerController())
        {
            continue;
        }

        PRI = GearPRI(PC.PlayerReplicationInfo);

        if (PRI == None)
        {
            continue;
        }

        bChanged = false;

        if (PRI.DLCFlag == -1)
        {
            PRI.DLCFlag = 0;
            bChanged = true;
        }

        if (bChanged)
        {
            LogInternal(
                "[SystemLinkMod] Local LAN host PRI marked ready: " $
                "Name=" $ PRI.PlayerName $
                " HasNetId=" $ string(PRI.UniqueId != ZeroId) $
                " DLCFlag=" $ string(PRI.DLCFlag)
            );
        }
    }
}


/*
 * Redirect the Party Lobby option submission so System Link opens
 * directly without DestroyOnlineGame or RecreateParty.
 */
function InstallPartyLobbyHook()
{
    local GameUISceneClient SceneClient;
    local GearUISceneFELobby_Party PartyScene;

    SceneClient = class'UIRoot'.static.GetSceneClient();

    if (SceneClient == None)
    {
        return;
    }

    PartyScene = GearUISceneFELobby_Party(
        SceneClient.FindSceneByTag('PartyLobby')
    );

    if (PartyScene == None)
    {
        HookedPartyScene = None;
        bPartyHookLogged = false;
        return;
    }

    if (PartyScene.lstPartyOptions == None)
    {
        return;
    }

    PartyScene.lstPartyOptions.OnListOptionSubmitted =
        OnPartyListValueSubmitted;

    if (ShouldUseLocalHostStartBypass(PartyScene) &&
        PartyScene.MatchmakeButton != None)
    {
        PartyScene.MatchmakeButton.OnClicked =
            OnLocalSystemLinkStartClicked;
    }

    if (HookedPartyScene != PartyScene || !bPartyHookLogged)
    {
        HookedPartyScene = PartyScene;
        bPartyHookLogged = true;

        LogInternal(
            "[SystemLinkMod] PartyLobby hook installed"
        );
    }
}


/*
 * The offline host has a real local PRI but no online UniqueNetId. Bypass
 * only the stock zero-ID count gate for a one-player System Link host.
 * Once a remote PRI exists, the original validation path remains active.
 */
function bool ShouldUseLocalHostStartBypass(
    GearUISceneFELobby_Party PartyScene
)
{
    local GearPartyGRI PartyGRI;

    if (!bLANSessionCreated || PartyScene == None ||
        !PartyScene.IsSystemLinkMatch())
    {
        return false;
    }

    PartyGRI = GearPartyGRI(PartyScene.GetGRI());

    return PartyGRI != None &&
        PartyGRI.ConnectingPlayerCount == 0 &&
        PartyGRI.PRIArray.Length == 1;
}


function bool OnLocalSystemLinkStartClicked(
    UIScreenObject EventObject,
    int PlayerIndex
)
{
    if (!ShouldUseLocalHostStartBypass(HookedPartyScene))
    {
        return false;
    }

    LogInternal(
        "[SystemLinkMod] Starting one-player LAN host through " $
        "local PRI validation bypass"
    );

    HookedPartyScene.SaveGameSettingsToProfile(
        PlayerIndex,
        OnLocalSystemLinkProfileWriteComplete
    );

    return true;
}


function OnLocalSystemLinkProfileWriteComplete(
    byte ControllerId,
    bool bWasSuccessful
)
{
    local LocalPlayer LP;
    local GearPC PC;
    local GearPartyGame_Base PartyGame;

    if (HookedPartyScene == None ||
        HookedPartyScene.GetWorldInfo() == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN START ERROR: party scene lost"
        );
        return;
    }

    LP = HookedPartyScene.GetPlayerOwner(
        class'UIInteraction'.static.GetPlayerIndex(ControllerId)
    );

    if (LP != None)
    {
        PC = GearPC(LP.Actor);

        if (PC != None)
        {
            PC.ClearSaveProfileDelegate(
                OnLocalSystemLinkProfileWriteComplete
            );
        }
    }

    PartyGame = HookedPartyScene.GetPartyGameInfo();

    if (PartyGame == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN START ERROR: PartyGame missing"
        );
        return;
    }

    PartyGame.BuildCustomMatchCurrentPlayerList();
    PartyGame.bIsTraveling = true;

    if (LANGameInterface != None)
    {
        LANGameInterface.StartOnlineGame('Game');
    }

    LogInternal(
        "[SystemLinkMod] Traveling to System Link pregame; " $
        "ProfileSaved=" $ string(bWasSuccessful)
    );

    HookedPartyScene.GetWorldInfo().ServerTravel(
        "gearstart?game=" $
        "SystemLinkMod.SystemLinkPreGameLobbyGame"
    );
}


/*
 * Redirect the LAN browser's Y/Create Party callback.
 *
 * We deliberately do not set the original PartyLobby
 * bWantsToStartLANParty flag. Therefore its OnLANSceneClosed()
 * will not call RecreateParty().
 */
function InstallLANBrowserHook()
{
    local GameUISceneClient SceneClient;
    local GearUISceneFE_LAN LANScene;

    SceneClient = class'UIRoot'.static.GetSceneClient();

    if (SceneClient == None)
    {
        return;
    }

    LANScene = GearUISceneFE_LAN(
        SceneClient.FindSceneByTag('LANGame')
    );

    if (LANScene == None)
    {
        if (bLANBrowserSearchStarted && LANGameInterface != None)
        {
            LANGameInterface.ClearFindOnlineGamesCompleteDelegate(
                OnLANBrowserFindComplete
            );
        }

        if (bLANJoinObserverInstalled && LANGameInterface != None)
        {
            LANGameInterface.ClearJoinOnlineGameCompleteDelegate(
                OnLANJoinObserved
            );
        }

        HookedLANScene = None;
        bLANHookLogged = false;
        bLANBrowserSearchRequested = false;
        bLANBrowserSearchStarted = false;
        bLANJoinObserverInstalled = false;
        LANBrowserSearchDelayFrames = 0;
        return;
    }

    LANScene.OnStartLANParty = CreateLocalSystemLinkParty;
    LANScene.OnCancelFromLANScene = CancelLocalSystemLinkBrowser;

    if (HookedLANScene != LANScene || !bLANHookLogged)
    {
        HookedLANScene = LANScene;
        bLANHookLogged = true;

        LogInternal(
            "[SystemLinkMod] Create Party callback replaced"
        );
    }
}


/*
 * The stock cancel delegate sets PartyLobby.bCanceledLANScene. Its close
 * callback then calls CancelSystemLinkSelection(true), which destroys and
 * recreates the old online party and leaves Hollow on "updating network
 * settings". Keep the existing party and let OnLANSceneClosed take its
 * normal System Link return path instead.
 */
function CancelLocalSystemLinkBrowser()
{
    if (HookedPartyScene != None)
    {
        HookedPartyScene.bCanceledLANScene = false;
        HookedPartyScene.bWantsToStartLANParty = false;
    }

    LogInternal(
        "[SystemLinkMod] LAN browser cancel: preserving current party"
    );
}


/*
 * OpenLANScene() activates the stock scene synchronously. Its activation-time
 * search therefore runs through Hollow's original offline interface before
 * this console can install IpDrv, producing the "not logged in" failures in
 * Launch.log and no UDP packet at all.
 *
 * Queue the replacement search until PostRender_Console on the next frame.
 * At that point the scene and all of its widgets/data stores are completely
 * initialized, avoiding the old activation-time reentrancy lockup.
 */
function StartPendingLANBrowserSearch()
{
    if (bLANBrowserSearchRequested &&
        LANBrowserSearchDelayFrames > 0)
    {
        LANBrowserSearchDelayFrames--;
        return;
    }

    if (!bLANBrowserSearchRequested || bLANBrowserSearchStarted ||
        HookedLANScene == None)
    {
        return;
    }
    /*
     * Preserve an active hosted Game session.
     * IpDrv cannot search and host through the same LAN interface safely.
     */
    if (bLANSessionCreated &&
        LANGameInterface != None &&
        LANGameInterface.GetGameSettings('Game') != None)
    {
        bLANBrowserSearchRequested = false;
        bLANBrowserSearchStarted = false;

        if (HookedLANScene != None)
        {
            HookedLANScene.bIsSearching = false;
        }

        LogInternal(
            "[SystemLinkMod] LAN SEARCH SKIPPED: active host session preserved"
        );
        return;
    }


    GlobalOnlineSubsystem =
        class'Engine.GameEngine'.static.GetOnlineSubsystem();

    /*
     * On a later browser visit the IpDrv interface may already be global,
     * allowing the stock activation callback to start the correct async LAN
     * search itself. Adopt that one instead of dispatching a duplicate.
     */
    if (HookedLANScene.bIsSearching &&
        LANGameInterface != None &&
        GlobalOnlineSubsystem != None &&
        GlobalOnlineSubsystem.GameInterface == LANGameInterface)
    {
        bLANBrowserSearchRequested = false;
        bLANBrowserSearchStarted = true;

        LANGameInterface.AddFindOnlineGamesCompleteDelegate(
            OnLANBrowserFindComplete
        );

        LogInternal(
            "[SystemLinkMod] LAN SEARCH ADOPTED: " $
            "stock scene already dispatched IpDrv search"
        );
        return;
    }

    /*
     * A synchronous failure from the old offline interface can leave this
     * UI flag set until its deferred completion timer runs. The two-frame
     * delay above normally clears it; never treat it as a real LAN search.
     */
    if (HookedLANScene.bIsSearching)
    {
        LogInternal(
            "[SystemLinkMod] LAN SEARCH: clearing stale offline UI state"
        );
        HookedLANScene.bIsSearching = false;
    }

    if (!EnsureLANSubsystem())
    {
        LogInternal(
            "[SystemLinkMod] LAN SEARCH ERROR: subsystem unavailable"
        );

        bLANBrowserSearchRequested = false;
        return;
    }

    if (!PrepareLANBrowserDataStore())
    {
        bLANBrowserSearchRequested = false;
        return;
    }

    bLANBrowserSearchRequested = false;
    bLANBrowserSearchStarted = true;

    LANGameInterface.AddFindOnlineGamesCompleteDelegate(
        OnLANBrowserFindComplete
    );

    LogInternal(
        "[SystemLinkMod] LAN SEARCH START: Controller=" $
        string(HookedLANScene.GetBestControllerId())
    );

    HookedLANScene.TriggerPartySearch();

    LogInternal(
        "[SystemLinkMod] LAN SEARCH DISPATCHED: SceneSearching=" $
        string(HookedLANScene.bIsSearching)
    );
}


/*
 * Automatically initialize the LAN subsystem and create the 'Game' session
 * if Hollow is launched directly into a listen server map.
 */
function AutoInitializeDirectListenHost()
{
    local GearPartyGameSettings LANSettings;

    if (bLANSessionCreated || bLANCreatePending)
    {
        return;
    }

    if (!EnsureLANSubsystem())
    {
        LogInternal("[SystemLinkMod] AUTO-HOST ERROR: EnsureLANSubsystem failed");
        return;
    }

    LogInternal("[SystemLinkMod] AUTO-HOST: Initializing LAN host session from main menu...");

    LANSettings = new class'GearGame.GearPartyGameSettings';
    ConfigureLANSettings(LANSettings, None);
    PendingLANSettings = LANSettings;

    LANGameInterface.ClearCreateOnlineGameCompleteDelegate(OnAutoHostLANPartyCreated);
    LANGameInterface.AddCreateOnlineGameCompleteDelegate(OnAutoHostLANPartyCreated);

    bLANCreatePending = true;
    bLANSessionCreated = false;

    LogInternal(
        "[SystemLinkMod] AUTO-HOST: Calling CreateOnlineGame"
    );

    if (!LANGameInterface.CreateOnlineGame(0, 'Game', LANSettings))
    {
        LANGameInterface.ClearCreateOnlineGameCompleteDelegate(OnAutoHostLANPartyCreated);
        bLANCreatePending = false;
        LogInternal("[SystemLinkMod] AUTO-HOST ERROR: CreateOnlineGame native call returned false");
    }
}


/*
 * Callback for AutoInitializeDirectListenHost.
 * Starts the online session and performs ClientTravel to GearPartyGame.
 */
function OnAutoHostLANPartyCreated(name SessionName, bool bWasSuccessful)
{
    local PlayerController PC;

    bLANCreatePending = false;
    bLANSessionCreated = bWasSuccessful;

    LogInternal(
        "[SystemLinkMod] AUTO-HOST CALLBACK: Session=" $ string(SessionName) $
        " Success=" $ string(bWasSuccessful)
    );

    if (bWasSuccessful && LANGameInterface != None)
    {
        LANGameInterface.StartOnlineGame(SessionName);
        LogInternal("[SystemLinkMod] AUTO-HOST SUCCESS: LAN Beacon active on port 14001! Traveling to Party Lobby...");

        if (ConsoleTargetPlayer != None && ConsoleTargetPlayer.Actor != None)
        {
            PC = ConsoleTargetPlayer.Actor;
            PC.ClientTravel("GearStart?listen?game=GearGameContent.GearPartyGame", TRAVEL_Absolute);
        }
    }
}


/*
 * Automatically initialize LAN search if the client is in the LAN browser scene.
 */
function AutoInitializeClientSearch()
{
    local GameUISceneClient SceneClient;
    local GearUISceneFE_LAN LANScene;

    if (bLANSessionCreated || bLANCreatePending || bLANBrowserSearchStarted)
    {
        return;
    }

    SceneClient = class'UIRoot'.static.GetSceneClient();
    if (SceneClient == None)
    {
        return;
    }

    LANScene = GearUISceneFE_LAN(
        SceneClient.FindSceneByTag('LANGame')
    );

    if (LANScene == None)
    {
        return;
    }

    if (!bLANBrowserSearchRequested)
    {
        bLANBrowserSearchRequested = true;
        LANBrowserSearchDelayFrames = 1;
        LogInternal("[SystemLinkMod] AUTO-SEARCH: LAN browser active; requested automatic search");
    }
}


/*
 * Process configured AutoStartMode ('Host' or 'Client') directly from config.
 */
function ProcessAutoStartMode()
{
    local SystemLinkLANGameInterface ModInterface;

    if (bAutoStartProcessed)
    {
        return;
    }

    if (!EnsureLANSubsystem())
    {
        return;
    }

    ModInterface = SystemLinkLANGameInterface(LANGameInterface);
    if (ModInterface == None || ModInterface.AutoStartMode == "" || ModInterface.AutoStartMode ~= "None")
    {
        bAutoStartProcessed = true;
        return;
    }

    if (ModInterface.AutoStartMode ~= "Host")
    {
        if (!bLANSessionCreated && !bLANCreatePending)
        {
            bAutoStartProcessed = true;
            LogInternal("[SystemLinkMod] AUTO-START CONFIG: AutoStartMode=Host -> initializing host session");
            AutoInitializeDirectListenHost();
        }
    }
    else if (ModInterface.AutoStartMode ~= "Client")
    {
        if (!bLANBrowserSearchRequested && !bLANBrowserSearchStarted)
        {
            bAutoStartProcessed = true;
            LogInternal("[SystemLinkMod] AUTO-START CONFIG: AutoStartMode=Client -> requesting LAN search");
            bLANBrowserSearchRequested = true;
            LANBrowserSearchDelayFrames = 2;
        }
    }
}


/*
 * UIDataStore_OnlineGameSearch caches OnlineSub.GameInterface during Init().
 * That happens at startup, before SystemLinkMod creates the IpDrv interface,
 * so changing only the global interface leaves LANGameSearch calling the old
 * Steam interface. Rebind the datastore and its completion delegate, then
 * repair the missing LAN flag on GearLANPartySearch.
 */
function bool PrepareLANBrowserDataStore()
{
    local OnlineGameSearch BrowserSearch;

    if (HookedLANScene == None || HookedLANScene.LANDataStore == None ||
        LANGameInterface == None || GlobalOnlineSubsystem == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN SEARCH ERROR: datastore unavailable"
        );
        return false;
    }

    if (OriginalGameInterface != None)
    {
        OriginalGameInterface.ClearFindOnlineGamesCompleteDelegate(
            HookedLANScene.LANDataStore.OnSearchComplete
        );
    }

    HookedLANScene.LANDataStore.OnlineSub = GlobalOnlineSubsystem;
    HookedLANScene.LANDataStore.GameInterface = LANGameInterface;

    LANGameInterface.AddFindOnlineGamesCompleteDelegate(
        HookedLANScene.LANDataStore.OnSearchComplete
    );

    if (!bLANJoinObserverInstalled)
    {
        LANGameInterface.AddJoinOnlineGameCompleteDelegate(
            OnLANJoinObserved
        );
        bLANJoinObserverInstalled = true;

        LogInternal(
            "[SystemLinkMod] LAN JOIN OBSERVER INSTALLED"
        );
    }

    BrowserSearch =
        HookedLANScene.LANDataStore.GetCurrentGameSearch();

    if (BrowserSearch == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN SEARCH ERROR: search object missing"
        );
        return false;
    }

    BrowserSearch.bIsLanQuery = true;
    BrowserSearch.bUsesArbitration = false;

    LogInternal(
        "[SystemLinkMod] LAN SEARCH PREPARED: SearchClass=" $
        string(BrowserSearch.Class) $
        " IsLAN=" $ string(BrowserSearch.bIsLanQuery) $
        " InterfaceClass=" $
        string(HookedLANScene.LANDataStore.GameInterface.Class) $
        " UniqueId=" $ string(LANGameInterface.LanGameUniqueId) $
        " PlatformMask=" $
        string(LANGameInterface.LanPacketPlatformMask) $
        " Port=" $ string(LANGameInterface.LanAnnouncePort)
    );

    return true;
}


function OnLANBrowserFindComplete(bool bWasSuccessful)
{
    local OnlineGameSearch CompletedSearch;
    local int ResultCount;

    if (LANGameInterface != None)
    {
        LANGameInterface.ClearFindOnlineGamesCompleteDelegate(
            OnLANBrowserFindComplete
        );

        CompletedSearch = LANGameInterface.GetGameSearch();
    }

    if (CompletedSearch != None)
    {
        ResultCount = CompletedSearch.Results.Length;
    }

    bLANBrowserSearchStarted = false;

    LogInternal(
        "[SystemLinkMod] LAN SEARCH COMPLETE: Success=" $
        string(bWasSuccessful) $
        " Results=" $ string(ResultCount)
    );
}


/*
 * Passive diagnostic for the stock LAN scene's join path. The scene still
 * owns the real join callback and travel. This observer only records whether
 * native JoinOnlineGame completed and which PC connect string it resolved.
 */
function OnLANJoinObserved(name SessionName, bool bWasSuccessful)
{
    local string ConnectAddress;
    local bool bAddressResolved;

    if (LANGameInterface != None && bWasSuccessful)
    {
        bAddressResolved = LANGameInterface.GetResolvedConnectString(
            SessionName,
            ConnectAddress
        );
    }

    LogInternal(
        "[SystemLinkMod] LAN JOIN OBSERVED: Session=" $
        string(SessionName) $
        " Success=" $ string(bWasSuccessful) $
        " Resolved=" $ string(bAddressResolved) $
        " Address=" $ ConnectAddress
    );
}


/*
 * Replacement for the native PartyLobby list submission.
 */
function OnPartyListValueSubmitted(
    UIList Sender,
    name OptionName,
    int PlayerIndex
)
{
    local array<UIDataStore> Unused;
    local UIDataStorePublisher Publisher;
    local GearProfileSettings Profile;
    local int SelectedContext;

    if (HookedPartyScene == None)
    {
        return;
    }

    if (OptionName != 'MatchModeOption')
    {
        HookedPartyScene.ListValueSubmitted(
            Sender,
            OptionName,
            PlayerIndex
        );

        return;
    }

    Publisher = UIDataStorePublisher(Sender);

    if (Publisher != None)
    {
        Publisher.SaveSubscriberValue(Unused);
    }

    Profile = HookedPartyScene.GetPlayerProfile(PlayerIndex);

    if (Profile == None ||
        !Profile.GetProfileSettingValueId(
            Profile.const.VERSUS_MATCH_MODE,
            SelectedContext
        ))
    {
        HookedPartyScene.UpdateSceneState();
        return;
    }

    if (SelectedContext == 2)
    {
        OpenNativeSystemLinkBrowser(
            HookedPartyScene,
            Profile,
            PlayerIndex
        );

        return;
    }

    HookedPartyScene.ListValueSubmitted(
        Sender,
        OptionName,
        PlayerIndex
    );
}


/*
 * Set System Link state and open the existing LAN browser.
 */
function OpenNativeSystemLinkBrowser(
    GearUISceneFELobby_Party PartyScene,
    GearProfileSettings Profile,
    int PlayerIndex
)
{
    local GearPartyGame_Base PartyGame;
    local GearPartyGameSettings LANSettings;

    if (PartyScene == None)
    {
        return;
    }

    /*
     * Keep this false so browser closure cannot trigger
     * RecreateParty().
     */
    PartyScene.bWantsToStartLANParty = false;
    PartyScene.bCanceledLANScene = false;
    PartyScene.PreviousMatchMode = 2;

    if (Profile != None)
    {
        Profile.SetProfileSettingValueId(
            Profile.const.VERSUS_MATCH_MODE,
            2
        );
    }

    PartyGame = PartyScene.GetPartyGameInfo();

    if (PartyGame != None)
    {
        LANSettings = PartyGame.PartySettings;

        if (LANSettings == None)
        {
            LANSettings =
                new class'GearGame.GearPartyGameSettings';

            PartyGame.PartySettings = LANSettings;
        }

        ConfigureLANSettings(
            LANSettings,
            Profile
        );
    }

    PartyScene.SetMenuItemsInPartyList();

    /*
     * HOTFIX:
     * UpdateRemoteSettings() can launch the blocking
     * "Network settings are being updated" modal while entering
     * the LAN browser. LAN selection is already configured locally.
     */
    if (!bLANSessionCreated)
    {
        PartyScene.UpdateSceneState();
    }
    else
    {
        LogInternal(
            "[SystemLinkMod] UPDATE SCENE STATE SKIPPED: active LAN host"
        );
    }

    /*
     * MERGE FROM 20260721-012444:
     * Pre-mark the registered LAN search objects as LAN queries.
     * This does not replace the active GameInterface or start a search,
     * so the working 010224 host/menu flow remains intact.
     */
    ConfigureRegisteredLANSearchObjects();

    /*
     * HOST-FIRST FLOW:
     *
     * Do not replace the global GameInterface before opening LANGame.
     * The stock scene starts an automatic search during activation; in
     * Hollow's offline runtime the newly injected IpDrv search can remain
     * pending forever and lock Create Party/Back.
     *
     * CreateLocalSystemLinkParty() installs the real LAN interface only
     * after the player presses Create Party.
     */
    PartyScene.OpenLANScene();

    /*
     * OpenLANScene is synchronous, so hook the new browser
     * immediately instead of waiting for another frame.
     */
    InstallLANBrowserHook();

    /*
     * The stock activation-time search already failed through the original
     * offline interface. Start one real IpDrv search on the next frame.
     */
    bLANBrowserSearchRequested = true;
    LANBrowserSearchDelayFrames = 2;

    LogInternal(
        "[SystemLinkMod] System Link browser opened"
    );
}


/*
 * Selective import from backup 20260721-012444 FixLANDataStoreSearch().
 *
 * The original branch also replaced the global interface before opening
 * the browser and forced LANScene.bIsSearching=false every frame. Those
 * behaviours are intentionally excluded because they conflict with the
 * stable 010224 party/menu and controlled-search flow.
 */
function ConfigureRegisteredLANSearchObjects()
{
    local DataStoreClient DataStoreManager;
    local GearUIDataStore_GameSearchLAN LANDataStore;
    local GearUIDataStore_CoopSearchLAN CoopLANDataStore;
    local OnlineGameSearch SearchObj;
    local int i;

    DataStoreManager = class'UIInteraction'.static.GetDataStoreClient();

    if (DataStoreManager == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN SEARCH PRECONFIG: datastore client missing"
        );
        return;
    }

    LANDataStore = GearUIDataStore_GameSearchLAN(
        DataStoreManager.FindDataStore('LANGameSearch')
    );

    if (LANDataStore != None)
    {
        for (i = 0; i < LANDataStore.GameSearchCfgList.Length; i++)
        {
            SearchObj = LANDataStore.GameSearchCfgList[i].Search;

            if (SearchObj != None)
            {
                SearchObj.bIsLanQuery = true;
                SearchObj.bUsesArbitration = false;
            }
        }

        LogInternal(
            "[SystemLinkMod] LAN SEARCH PRECONFIG: LANGameSearch configured"
        );
    }

    CoopLANDataStore = GearUIDataStore_CoopSearchLAN(
        DataStoreManager.FindDataStore('LANCoopSearch')
    );

    if (CoopLANDataStore != None)
    {
        for (i = 0; i < CoopLANDataStore.GameSearchCfgList.Length; i++)
        {
            SearchObj = CoopLANDataStore.GameSearchCfgList[i].Search;

            if (SearchObj != None)
            {
                SearchObj.bIsLanQuery = true;
                SearchObj.bUsesArbitration = false;
            }
        }

        LogInternal(
            "[SystemLinkMod] LAN SEARCH PRECONFIG: LANCoopSearch configured"
        );
    }
}


/*
 * Called by GearUISceneFE_LAN.OnCreatePartyClicked().
 *
 * That native function automatically closes the browser immediately
 * after this callback returns.
 */
function bool EnsureLANSubsystem()
{
    GlobalOnlineSubsystem =
        class'Engine.GameEngine'.static.GetOnlineSubsystem();

    if (GlobalOnlineSubsystem == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN ERROR: global OnlineSubsystem is None"
        );

        return false;
    }

    GlobalCommonSubsystem =
        OnlineSubsystemCommonImpl(GlobalOnlineSubsystem);

    if (GlobalCommonSubsystem == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN ERROR: global subsystem is not " $
            "OnlineSubsystemCommonImpl"
        );

        return false;
    }

    if (LANGameInterface == None)
    {
        /*
         * Preserve the normal interface in case we add a restore path.
         */
        OriginalGameInterface =
            GlobalOnlineSubsystem.GameInterface;

        OriginalGameInterfaceImpl =
            GlobalCommonSubsystem.GameInterfaceImpl;

        /*
         * OnlineGameInterfaceImpl is the stock IpDrv LAN implementation.
         * It owns Create/Find/Join/GetResolvedConnectString and the
         * UDP LAN beacon configured on port 14001.
         *
         * Its class is declared "within OnlineSubsystemCommonImpl", so
         * the existing global common subsystem must be its Outer.
         */
        LANGameInterface =
            new(GlobalCommonSubsystem)
            class'SystemLinkMod.SystemLinkLANGameInterface';

        if (LANGameInterface == None)
        {
            LogInternal(
                "[SystemLinkMod] LAN ERROR: could not create " $
                "OnlineGameInterfaceImpl"
            );

            return false;
        }

        LANGameInterface.OwningSubsystem =
            GlobalCommonSubsystem;
    }

    /*
     * Route all stock UI and GearPartyGame session calls through the
     * same LAN interface. This is the key difference from the previous
     * secondary-subsystem attempt.
     */
    GlobalCommonSubsystem.GameInterfaceImpl =
        LANGameInterface;

    if (!GlobalOnlineSubsystem.SetGameInterface(LANGameInterface))
    {
        LogInternal(
            "[SystemLinkMod] LAN ERROR: SetGameInterface failed"
        );

        return false;
    }

    if (GlobalOnlineSubsystem.GameInterface == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN ERROR: global GameInterface is None"
        );

        return false;
    }

    LogInternal(
        "[SystemLinkMod] GLOBAL GAME INTERFACE ROUTED TO IPDRV LAN"
    );

    return true;
}

function CreateLocalSystemLinkParty()
{
    local GearPartyGame_Base PartyGame;
    local GearPartyGameSettings LANSettings;
    local GearProfileSettings Profile;
    local int PlayerIndex;
    local int ControllerId;
    local bool bCreateStarted;

    if (HookedPartyScene == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE ERROR: PartyLobby missing"
        );

        return;
    }

    if (bLANCreatePending)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE ignored: already pending"
        );

        return;
    }

    PlayerIndex = HookedPartyScene.GetBestPlayerIndex();
    ControllerId = HookedPartyScene.GetBestControllerId();
    PendingLANControllerId = ControllerId;

    Profile = HookedPartyScene.GetPlayerProfile(PlayerIndex);
    PartyGame = HookedPartyScene.GetPartyGameInfo();

    if (PartyGame == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE ERROR: PartyGame missing"
        );

        return;
    }

    LANSettings = PartyGame.PartySettings;

    if (LANSettings == None)
    {
        LANSettings =
            new class'GearGame.GearPartyGameSettings';
    }

    ConfigureLANSettings(
        LANSettings,
        Profile
    );

    PartyGame.PartySettings = LANSettings;
    PendingLANSettings = LANSettings;

    if (Profile != None)
    {
        Profile.SetProfileSettingValueId(
            Profile.const.VERSUS_MATCH_MODE,
            2
        );
    }

    /*
     * Keep the original broken OnLANSceneClosed path disabled.
     */
    HookedPartyScene.bWantsToStartLANParty = false;
    HookedPartyScene.bCanceledLANScene = false;
    HookedPartyScene.PreviousMatchMode = 2;

    if (!EnsureLANSubsystem())
    {
        return;
    }

    LANGameInterface.ClearCreateOnlineGameCompleteDelegate(
        OnRealLANPartyCreated
    );

    LANGameInterface.AddCreateOnlineGameCompleteDelegate(
        OnRealLANPartyCreated
    );

    bLANCreatePending = true;
    bLANSessionCreated = false;

    LogInternal(
        "[SystemLinkMod] Calling PC CreateOnlineGame: " $
        "Session=Game Controller=" $ string(ControllerId) $
        " IsLAN=" $ string(LANSettings.bIsLanMatch) $
        " Advertise=" $ string(LANSettings.bShouldAdvertise)
    );

    bCreateStarted =
        LANGameInterface.CreateOnlineGame(
            byte(ControllerId),
            'Game',
            LANSettings
        );

    if (!bCreateStarted)
    {
        LANGameInterface.ClearCreateOnlineGameCompleteDelegate(
            OnRealLANPartyCreated
        );

        bLANCreatePending = false;

        LogInternal(
            "[SystemLinkMod] LAN CREATE ERROR: native call returned false"
        );

        return;
    }

    LogInternal(
        "[SystemLinkMod] CreateOnlineGame returned True: " $
        "Pending=" $ string(bLANCreatePending) $
        " SessionCreated=" $ string(bLANSessionCreated) $
        " BeaconState=" $ string(LANGameInterface.LanBeaconState) $
        " UniqueId=" $ string(LANGameInterface.LanGameUniqueId) $
        " PlatformMask=" $
        string(LANGameInterface.LanPacketPlatformMask)
    );
}


/*
 * Completion callback from OnlineGameInterfaceImpl.
 */
function OnRealLANPartyCreated(
    name SessionName,
    bool bWasSuccessful
)
{
    local LocalPlayer LP;
    local OnlineGameSettings NativeSettings;
    local int PlayerIndex;
    local string PlayerName;
    local string TravelURL;

    if (LANGameInterface != None)
    {
        LANGameInterface.ClearCreateOnlineGameCompleteDelegate(
            OnRealLANPartyCreated
        );
    }

    bLANCreatePending = false;

    LogInternal(
        "[SystemLinkMod] LAN CREATE CALLBACK: Session=" $
        string(SessionName) $
        " Success=" $
        string(bWasSuccessful) $
        " BeaconState=" $ string(LANGameInterface.LanBeaconState) $
        " UniqueId=" $ string(LANGameInterface.LanGameUniqueId) $
        " PlatformMask=" $
        string(LANGameInterface.LanPacketPlatformMask)
    );

    /*
     * Hollow's PC IpDrv implementation supports one session named 'Game'.
     * GearPartyGame receives the same settings through the repair hook.
     */
    if (SessionName != 'Game' || !bWasSuccessful)
    {
        bLANSessionCreated = false;

        LogInternal(
            "[SystemLinkMod] REAL LAN PARTY CREATION FAILED"
        );

        return;
    }

    bLANSessionCreated = true;

    NativeSettings = LANGameInterface.GameSettings;

    if (NativeSettings == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE STATE: NativeSettings=None"
        );
    }
    else
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE STATE: IsLAN=" $
            string(NativeSettings.bIsLanMatch) $
            " Advertise=" $
            string(NativeSettings.bShouldAdvertise) $
            " Public=" $
            string(NativeSettings.NumPublicConnections)
        );
    }

    if (HookedPartyScene == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE ERROR: PartyLobby lost before travel"
        );

        return;
    }

    PlayerIndex = HookedPartyScene.GetBestPlayerIndex();
    LP = HookedPartyScene.GetPlayerOwner(PlayerIndex);

    if (LP == None || LP.Actor == None)
    {
        LogInternal(
            "[SystemLinkMod] LAN CREATE ERROR: LocalPlayer missing"
        );

        return;
    }

    /*
     * Preserve the existing offline/local identity layer. Only the game
     * session interface was replaced, so the normal player interface can
     * still supply the nickname.
     */
    PlayerName = "";

    if (GlobalOnlineSubsystem != None &&
        GlobalOnlineSubsystem.PlayerInterface != None)
    {
        PlayerName =
            GlobalOnlineSubsystem.PlayerInterface.GetPlayerNickname(
                byte(PendingLANControllerId)
            );
    }

    if (PlayerName == "" || PlayerName ~= "Connecting")
    {
        PlayerName = "Player1";
    }

    TravelURL =
        "GearStart?listen?game=GearGameContent.GearPartyGame?Name=" $
        PlayerName $
        "?";

    LogInternal(
        "[SystemLinkMod] REAL LAN PARTY CREATED - URL=" $
        TravelURL
    );

    bLANPostTravelProbePending = true;
    LANPostTravelProbeFrames = 0;

    LP.Actor.ClientTravel(
        TravelURL,
        0
    );
}

function ConfigureLANSettings(
    GearPartyGameSettings LANSettings,
    GearProfileSettings Profile
)
{
    local int PartyType;

    if (LANSettings == None)
    {
        return;
    }

    LANSettings.bIsLanMatch = true;
    LANSettings.bShouldAdvertise = true;
    LANSettings.bIsDedicated = false;
    LANSettings.bUsesStats = false;
    LANSettings.bUsesPresence = false;

    LANSettings.bAllowJoinInProgress = false;
    LANSettings.bAllowInvites = false;
    LANSettings.bAllowJoinViaPresence = false;
    LANSettings.bAllowJoinViaPresenceFriendsOnly = false;

    LANSettings.NumPublicConnections = 10;
    LANSettings.NumPrivateConnections = 0;

    /*
     * 101 = VERSUS_MATCH_MODE
     * 2   = System Link
     */
    LANSettings.SetStringSettingValue(
        101,
        2,
        false
    );

    PartyType = 1;

    if (Profile != None)
    {
        Profile.GetProfileSettingValueId(
            102,
            PartyType
        );
    }

    /*
     * 102 = party/invite type.
     */
    LANSettings.SetStringSettingValue(
        102,
        PartyType,
        false
    );

    /*
     * Native System Link match property.
     */
    LANSettings.SetIntProperty(
        268435457,
        1
    );
}





