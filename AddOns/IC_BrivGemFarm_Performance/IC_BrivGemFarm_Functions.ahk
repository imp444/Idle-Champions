class IC_BrivSharedFunctions_Class extends IC_SharedFunctions_Class
{
    steelbones := ""
    sprint := ""
    
    ; Force adventure reset rather than relying on modron to reset.
    RestartAdventure( reason := "" )
    {
            g_SharedData.LoopString := "ServerCall: Restarting adventure"
            this.CloseIC( reason )
            if(this.sprint != "" AND this.steelbones != "" AND (this.sprint + this.steelbones) < 190000)
            {
                response := g_serverCall.CallPreventStackFail(this.sprint + this.steelbones)
            }
            else if(this.sprint != "" AND this.steelbones != "")
            {
                response := g_serverCall.CallPreventStackFail(this.sprint + this.steelbones)
                g_SharedData.LoopString := "ServerCall: Restarting with >190k stacks, some stacks lost."
            }
            else
            {
                g_SharedData.LoopString := "ServerCall: Restarting adventure (no manual stack conv.)"
            }
            response := g_ServerCall.CallEndAdventure()
            response := g_ServerCall.CallLoadAdventure( this.CurrentAdventure )
            g_SharedData.TriggerStart := true
    }

    ; Store important user data [UserID, Hash, InstanceID, Briv Stacks, Gems, Chests]
    SetUserCredentials()
    {
        this.UserID := this.Memory.ReadUserID()
        this.UserHash := this.Memory.ReadUserHash()
        this.InstanceID := this.Memory.ReadInstanceID()
        ; needed to know if there are enough chests to open using server calls
        this.TotalGems := this.Memory.ReadGems()
        this.TotalSilverChests := this.Memory.GetChestCountByID(1)
        this.TotalGoldChests := this.Memory.GetChestCountByID(2)
        this.sprint := this.Memory.ReadHasteStacks()
        this.steelbones := this.Memory.ReadSBStacks()
    }

    ; sets the user information used in server calls such as user_id, hash, active modron, etc.
    ResetServerCall()
    {
        this.SetUserCredentials()
        g_ServerCall := new IC_BrivServerCall_Class( this.UserID, this.UserHash, this.InstanceID )
        version := this.Memory.ReadBaseGameVersion()
        if(version != "")
            g_ServerCall.clientVersion := version
        tempWebRoot := this.Memory.ReadWebRoot()
        httpString := StrSplit(tempWebRoot,":")[1]
        isWebRootValid := httpString == "http" or httpString == "https"
        g_ServerCall.webroot := isWebRootValid ? tempWebRoot : g_ServerCall.webroot
        g_ServerCall.networkID := this.Memory.ReadPlatform() ? this.Memory.ReadPlatform() : g_ServerCall.networkID
        g_ServerCall.activeModronID := this.Memory.ReadActiveGameInstance() ? this.Memory.ReadActiveGameInstance() : 1 ; 1, 2, 3 for modron cores 1, 2, 3
        g_ServerCall.activePatronID := this.Memory.ReadPatronID() == "" ? g_ServerCall.activePatronID : this.Memory.ReadPatronID() ; 0 = no patron
        g_ServerCall.UpdateDummyData()
    }


    /*  WaitForModronReset - A function that monitors a modron resetting process.

        Returns:
        bool - true if completed successfully; returns false if reset does not occur within 75s
    */
    WaitForModronReset( timeout := 75000)
    {
        StartTime := A_TickCount
        ElapsedTime := 0
        g_SharedData.LoopString := "Modron Resetting..."
        this.SetUserCredentials()
        ; if(this.sprint != "" AND this.steelbones != "" AND (this.sprint + this.steelbones) < 190000)
        ;     response := g_serverCall.CallPreventStackFail( this.sprint + this.steelbones)
        while (this.Memory.ReadResetting() AND ElapsedTime < timeout)
        {
            ElapsedTime := A_TickCount - StartTime
        }
        g_SharedData.LoopString := "Loading z1..."
        Sleep, 50
        while(!this.Memory.ReadUserIsInited() AND ElapsedTime < timeout)
        {
            ElapsedTime := A_TickCount - StartTime
        }
        if (ElapsedTime >= timeout)
        {
            return false
        }
        return true
    }

    ; Refocuses the window that was recorded as being active before the game window opened.
    ActivateLastWindow()
    {
        if(!g_BrivUserSettings["RestoreLastWindowOnGameOpen"])
            return
        Sleep, 100 ; extra wait for window to load
        hwnd := this.Hwnd
        WinActivate, ahk_id %hwnd% ; Idle Champions likes to be activated before it can be deactivated            
        savedActive := this.SavedActiveWindow
        WinActivate, %savedActive%
    }

    ; Returns true when conditions have been met for starting a wait for dash.
    ShouldDashWait()
    {
        currentFormation := this.Memory.GetCurrentFormation()
        isShandieInFormation := this.IsChampInFormation( 47, currentFormation )
        hasHasteStacks := this.Memory.ReadHasteStacks() > 50
        dashWaitMaxZone := Max(g_SF.ModronResetZone - g_BrivUserSettings[ "DashWaitBuffer" ], 0)
        return (!g_BrivUserSettings[ "DisableDashWait" ] AND this.Memory.ReadCurrentZone() < dashWaitMaxZone AND isShandieInFormation AND hasHasteStacks)
    }
}

class IC_BrivServerCall_Class extends IC_ServerCalls_Class
{
    ; forces an attempt for the server to remember stacks
    CallPreventStackFail(stacks)
    {
        response := ""
        stacks := g_SaveHelper.GetEstimatedStackValue(stacks)
        userData := g_SaveHelper.GetCompressedDataFromBrivStacks(stacks)
        checksum := g_SaveHelper.GetSaveCheckSumFromBrivStacks(stacks)
        save :=  g_SaveHelper.GetSave(userData, checksum, this.userID, this.userHash, this.networkID, this.clientVersion, this.instanceID)
        try
        {
            response := this.ServerCallSave(save)
        }
        catch, ErrMsg
        {
            g_SharedData.LoopString := "Failed to save Briv stacks"
        }
        return response
    }
}

class IC_BrivGemFarm_Class
{
    TimerFunctions := {}
    TargetStacks := 0
    GemFarmGUID := ""

    ;=====================================================
    ;Primary Functions for Briv Gem Farm
    ;=====================================================
    ;The primary loop for gem farming using Briv and modron.
    GemFarm()
    {
        static lastResetCount := 0
        g_SharedData.TriggerStart := true
        g_SF.Hwnd := WinExist("ahk_exe " . g_userSettings[ "ExeName"])
        existingProcessID := g_userSettings[ "ExeName"]
        Process, Exist, %existingProcessID%
        g_SF.PID := ErrorLevel
        Process, Priority, % g_SF.PID, High
        ProcessHandle := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", False, "UInt", g_SF.PID)
        DllCall("SetProcessAffinityMask", "UInt", ProcessHandle, "UInt", (3 << 16) + (3 << 22))
        DllCall("CloseHandle", "UInt", ProcessHandle)
        g_SF.Memory.OpenProcessReader()
        if(g_SF.VerifyAdventureLoaded() < 0)
            return
        g_SF.CurrentAdventure := g_SF.Memory.ReadCurrentObjID()
        g_ServerCall.UpdatePlayServer()
        g_SF.ResetServerCall()
        g_SF.GameStartFormation := g_BrivUserSettings[ "BrivJumpBuffer" ] > 0 ? 3 : 1
        g_SaveHelper.Init() ; slow call, loads briv dictionary (3+s)
        formationModron := g_SF.Memory.GetActiveModronFormation()
        formationQ := g_SF.FindChampIDinSavedFormation( 1, "Speed", 1, 58 )
        formationW := g_SF.FindChampIDinSavedFormation( 2, "Stack Farm", 1, 58 )
        formationE := g_SF.FindChampIDinSavedFormation( 3, "Speed No Briv", 0, 58 )
        if(!formationQ OR !formationW OR !formationE)
            return
        g_PreviousZoneStartTime := A_TickCount
        g_SharedData.StackFail := 0
        loop
        {
            g_SharedData.LoopString := "Main Loop"
            CurrentZone := g_SF.Memory.ReadCurrentZone()
            if(CurrentZone == "" AND !g_SF.SafetyCheck()) ; Check for game closed
                g_SF.ToggleAutoProgress( 1, false, true ) ; Turn on autoprogress after a restart
            g_SF.SetFormation(g_BrivUserSettings)
            if ( g_SF.Memory.ReadResetsCount() > lastResetCount OR g_SharedData.TriggerStart) ; first loop or Modron has reset
            {
                keyspam := Array()
                g_SharedData.BossesHitThisRun := 0
                g_SF.ToggleAutoProgress( 0, false, true )
                g_SharedData.StackFail := this.CheckForFailedConv()
                g_SF.WaitForFirstGold()
                ;if g_BrivUserSettings[ "Fkeys" ]
                    ;keyspam := g_SF.GetFormationFKeys(formationModron)
                doKeySpam := true
                keyspam.Push(this.DoPartySetup())
                keyspam.Push("{ClickDmg}")
                lastResetCount := g_SF.Memory.ReadResetsCount()
                g_SF.Memory.ActiveEffectKeyHandler.Refresh()
                worstCase := g_BrivUserSettings[ "AutoCalculateWorstCase" ]
                g_SharedData.TargetStacks := this.TargetStacks := g_SF.CalculateBrivStacksToReachNextModronResetZone(worstCase) + 50 ; 50 stack safety net
                this.LeftoverStacks := g_SF.CalculateBrivStacksLeftAtTargetZone(g_SF.Memory.ReadCurrentZone(), g_SF.Memory.GetModronResetArea() + 1, worstCase)
                StartTime := g_PreviousZoneStartTime := A_TickCount
                PreviousZone := 1
                g_SharedData.SwapsMadeThisRun := 0
                g_SharedData.TriggerStart := false
                g_SharedData.LoopString := "Main Loop"
            }
            if (g_SharedData.StackFail != 2)
                g_SharedData.StackFail := Max(this.TestForSteelBonesStackFarming(), g_SharedData.StackFail)
            if (g_SharedData.StackFail == 2 OR g_SharedData.StackFail == 4 OR g_SharedData.StackFail == 6 ) ; OR g_SharedData.StackFail == 3
                g_SharedData.TriggerStart := true
            if (!Mod( g_SF.Memory.ReadCurrentZone(), 5 ) AND Mod( g_SF.Memory.ReadHighestZone(), 5 ) AND !g_SF.Memory.ReadTransitioning())
                g_SF.ToggleAutoProgress( 1, true ) ; Toggle autoprogress to skip boss bag
            if (g_SF.Memory.ReadResetting())
            {
                this.ModronResetCheck()
                keyspam = Array()
            }
            this.DoPartySetupAFter()
            if(CurrentZone > PreviousZone) ; needs to be greater than because offline could stacking getting stuck in descending zones.
            {
                PreviousZone := CurrentZone
                if((!Mod( g_SF.Memory.ReadCurrentZone(), 5 )) AND (!Mod( g_SF.Memory.ReadHighestZone(), 5)))
                {
                    g_SharedData.TotalBossesHit++
                    g_SharedData.BossesHitThisRun++
                }
                if(doKeySpam AND g_BrivUserSettings[ "Fkeys" ] AND g_SF.AreChampionsUpgraded(formationQ))
                {
                    g_SF.DirectedInput(hold:=0,release:=1, keyspam) ;keysup
                    keyspam := ["{ClickDmg}"]
                    doKeySpam := false
                }
                lastModronResetZone := g_SF.ModronResetZone
                g_SF.InitZone( keyspam )
                if g_SF.ModronResetZone != lastModronResetZone
                {
                    worstCase := g_BrivUserSettings[ "AutoCalculateWorstCase" ]
                    g_SharedData.TargetStacks := this.TargetStacks := g_SF.CalculateBrivStacksToReachNextModronResetZone(worstCase) + 50 ; 50 stack safety net
                    this.LeftoverStacks := g_SF.CalculateBrivStacksLeftAtTargetZone(this.Memory.ReadCurrentZone(), this.Memory.GetModronResetArea() + 1, worstCase)
                }
                g_SF.ToggleAutoProgress( 1 )
                continue
            }
            g_SF.ToggleAutoProgress( 1 )
            if(g_SF.CheckifStuck())
            {
                g_SharedData.TriggerStart := true
                g_SharedData.StackFail := StackFailStates.FAILED_TO_PROGRESS ; 3
                g_SharedData.StackFailStats.TALLY[g_SharedData.StackFail] += 1
            }
            Sleep, 20 ; here to keep the script responsive.
        }
    }

    ;=====================================================
    ;Functions for Briv Stack farming, mostly for gem runs
    ;=====================================================
    ;Various checks to determine when to stack SteelBones should be stacked or failed to stack.
    TestForSteelBonesStackFarming()
    {
        CurrentZone := g_SF.Memory.ReadCurrentZone()
        ; Don't test while modron resetting.
        if(CurrentZone < 0 OR CurrentZone >= g_SF.ModronResetZone)
            return
        stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
        targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? (this.TargetStacks - this.LeftoverStacks) : g_BrivUserSettings[ "TargetStacks" ]
        
        stackfail := 0
        forcedResetReason := ""
        ; passed stack zone, start stack farm. Normal operation.
        if ( stacks < targetStacks AND CurrentZone > g_BrivUserSettings[ "StackZone" ] )
        {
            this.StackFarm()
            return 0
        }
        ; stack briv between min zone and stack zone if briv is out of jumps (if stack fail recovery is on)
        if (g_SF.Memory.ReadHasteStacks() < 50 AND g_SF.Memory.ReadSBStacks() < targetStacks AND CurrentZone > g_BrivUserSettings[ "MinStackZone" ] AND g_BrivUserSettings[ "StackFailRecovery" ] AND CurrentZone < g_BrivUserSettings[ "StackZone" ] )
        {
            stackFail := StackFailStates.FAILED_TO_REACH_STACK_ZONE ; 1
            g_SharedData.StackFailStats.TALLY[stackfail] += 1
            this.StackFarm()
            return stackfail
        }
        ; Briv ran out of jumps but has enough stacks for a new adventure, restart adventure. With protections from repeating too early or resetting within 5 zones of a reset.
        if ( g_SF.Memory.ReadHasteStacks() < 50 AND stacks > targetStacks AND g_SF.Memory.ReadHighestZone() > 10 AND (g_SF.Memory.GetModronResetArea() - g_SF.Memory.ReadHighestZone() > 5 ))
        {
            stackFail := StackFailStates.FAILED_TO_REACH_STACK_ZONE_HARD ; 4
            g_SharedData.StackFailStats.TALLY[stackfail] += 1
            forcedResetReason := "Briv ran out of jumps but has enough stacks for a new adventure"
            g_SF.RestartAdventure(forcedResetReason)
        }
        ; stacks are more than the target stacks and party is more than "ResetZoneBuffer" levels past stack zone, restart adventure
        ; (for restarting after stacking without going to modron reset level)
        if ( stacks > targetStacks AND CurrentZone > g_BrivUserSettings[ "StackZone" ] + g_BrivUserSettings["ResetZoneBuffer"])
        {
            stackFail := StackFailStates.FAILED_TO_RESET_MODRON ; 6
            g_SharedData.StackFailStats.TALLY[stackfail] += 1
            forcedResetReason := " Stacks > target stacks & party > " . g_BrivUserSettings["ResetZoneBuffer"] . " levels past stack zone"
            g_SF.RestartAdventure(forcedResetReason)
        }           
        return stackfail
    }

    ; Determines if offline stacking is expected with current settings and conditions.
    ShouldOfflineStack()
    {
        gemsMax := g_BrivUserSettings[ "ForceOfflineGemThreshold" ]
        runsMax := g_BrivUserSettings[ "ForceOfflineRunThreshold" ]
        ; hybrid stacking not used. Use default test for offline stacking. 
        if !( (gemsMax > 1) OR (runsMax > 0) )
        {
            return ( g_BrivUserSettings [ "RestartStackTime" ] > 0 )
        }
        ; hybrid stacking by number of gems.
        if ( gemsMax > 0 AND g_SF.Memory.ReadGems() > (gemsMax + g_BrivUserSettings[ "MinGemCount" ]) )
        {
            return 1
        }
        ; hybrid stacking by number of runs.
        if ( runsMax > 1 )
        {
            memRead := g_SF.Memory.ReadResetsCount()
            if (memRead > 0 AND Mod( memRead, runsMax ) = 0)
            {
                return 1
            }
        }
        ; hybrid stacking enabled but conditions for offline stacking not met
        return 0
    }

    ;thanks meviin for coming up with this solution
    ;Gets total of SteelBonesStacks + Haste Stacks
    GetNumStacksFarmed()
    {
        if this.ShouldOfflineStack()
        {
            return g_BrivUserSettings[ "EarlyStacking" ] ? g_SF.Memory.ReadSBStacks() : g_SF.Memory.ReadHasteStacks() + g_SF.Memory.ReadSBStacks()
        }
        else
        {
            ; If restart stacking is disabled, we'll stack to basically the exact
            ; threshold.  That means that doing a single jump would cause you to
            ; lose stacks to fall below the threshold, which would mean StackNormal
            ; would happen after every jump.
            ; Thus, we use a static 47 instead of using the actual haste stacks
            ; with the assumption that we'll be at minimum stacks after a reset.
            return g_SF.Memory.ReadSBStacks() + 47
        }
    }

    /*  StackRestart - Stops progress and wwitches to appropriate party to prepare for stacking Briv's SteelBones.
                       Falls back from a boss zone if necessary.

    Parameters:

    Returns:
    */
    ; Stops progress and switches to appropriate party to prepare for stacking Briv's SteelBones.
    StackFarmSetup()
    {
        g_SF.KillCurrentBoss()
        inputValues := "{w}" ; Stack farm formation hotkey
        g_SF.DirectedInput(,, inputValues )
        g_SF.WaitForTransition( inputValues )
        g_SF.ToggleAutoProgress( 0 , false, true )
        StartTime := A_TickCount
        ElapsedTime := 0
        counter := 0
        sleepTime := 50
        g_SharedData.LoopString := "Setting stack farm formation."
        while ( !g_SF.IsCurrentFormation(g_SF.Memory.GetFormationByFavorite( 2 )) AND ElapsedTime < 5000 )
        {
            ElapsedTime := A_TickCount - StartTime
            if( ElapsedTime > (counter * sleepTime)) ; input limiter..
            {
                g_SF.DirectedInput(,,inputValues)
                counter++
            }
        }
        return
    }

    ;Starts stacking SteelBones based on settings (Restart or Normal).
    StackFarm()
    {
        stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
        targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? (this.TargetStacks - this.LeftoverStacks) : g_BrivUserSettings[ "TargetStacks" ]

        doOfflineStacking := this.ShouldOfflineStack()

        if ( ( stacks < targetStacks ) AND doOfflineStacking )
            this.StackRestart()
        else if (stacks < targetStacks)
            this.StackNormal()
        ; SetFormation needs to occur before dashwait in case game erronously placed party on boss zone after stack restart
        g_SF.SetFormation(g_BrivUserSettings) 
        if (g_SF.ShouldDashWait())
            g_SF.DoDashWait( Max(g_SF.ModronResetZone - g_BrivUserSettings[ "DashWaitBuffer" ], 0) )
    }

    /*  StackRestart - Stack Briv's SteelBones by switching to his formation and restarting the game.
                       Attempts to buy are open chests while game is closed.

    Parameters:

    Returns:
    */
    ; Stack Briv's SteelBones by switching to his formation and restarting the game.
    StackRestart()
    {
        lastStacks := stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
        targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? (this.TargetStacks - this.LeftoverStacks) : g_BrivUserSettings[ "TargetStacks" ]
        numSilverChests := g_SF.Memory.GetChestCountByID(1)
        numGoldChests := g_SF.Memory.GetChestCountByID(2)
        retryAttempt := 0
        while ( stacks < targetStacks AND retryAttempt < 10 )
        {
            retryAttempt++
            this.StackFarmSetup()
            g_SF.ToggleAutoProgress( 1 , false, true ) ; 
            g_SF.CurrentZone := g_SF.Memory.ReadCurrentZone() ; record current zone before saving for bad progression checks
            modronResetZone := g_SF.Memory.GetModronResetArea()
            if(modronResetZone != "" AND g_SF.CurrentZone > modronResetZone)
            {
                g_SharedData.LoopString := "Attempted to offline stack after modron reset - verify settings"
                break
            }
            g_SF.CloseIC( "StackRestart" )
            g_SharedData.LoopString := "Stack Sleep: "
            chestsCompletedString := ""
            StartTime := A_TickCount
            ElapsedTime := 0
            if(g_BrivUserSettings["DoChests"])
            {
                g_SharedData.LoopString := "Stack Sleep: " . " Buying or Opening Chests"
                chestsCompletedString := " " . this.DoChests(numSilverChests, numGoldChests)
            }
            while ( ElapsedTime < g_BrivUserSettings[ "RestartStackTime" ] )
            {
                ElapsedTime := A_TickCount - StartTime
                g_SharedData.LoopString := "Stack Sleep: " . g_BrivUserSettings[ "RestartStackTime" ] - ElapsedTime . chestsCompletedString
            }
            g_SF.SafetyCheck()
            stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
            ;check if save reverted back to below stacking conditions
            if ( g_SF.Memory.ReadCurrentZone() < g_BrivUserSettings[ "MinStackZone" ] )
            {
                g_SharedData.LoopString := "Stack Sleep: Failed (zone < min)"
                Break  ; "Bad Save? Loaded below stack zone, see value."
            }
            g_SharedData.PreviousStacksFromOffline := stacks - lastStacks
            lastStacks := stacks
        }
        g_PreviousZoneStartTime := A_TickCount
        return
    }

    /*  StackNormal - Stack Briv's SteelBones by switching to his formation and waiting for stacks to build.

    Parameters:

    Returns:
    */
    ; Stack Briv's SteelBones by switching to his formation.
    StackNormal()
    {
        stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
        targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? (this.TargetStacks - this.LeftoverStacks) : g_BrivUserSettings[ "TargetStacks" ]
        if (this.AvoidRestackTest())
            return
        this.StackFarmSetup()
        StartTime := A_TickCount
        ElapsedTime := 0
        g_SharedData.LoopString := "Stack Normal"
        prevSB := g_SF.Memory.ReadSBStacks()
        while ( stacks < targetStacks AND ElapsedTime < 300000 AND g_SF.Memory.ReadCurrentZone() > g_BrivUserSettings[ "MinStackZone" ] )
        {
            g_SF.KillCurrentBoss()
            stacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? g_SF.Memory.ReadSBStacks() : this.GetNumStacksFarmed()
            if ( g_SF.Memory.ReadSBStacks() > prevSB)
                StartTime := A_TickCount
            ElapsedTime := A_TickCount - StartTime
        }
        g_PreviousZoneStartTime := A_TickCount
        g_SF.FallBackFromZone()
        g_SF.ToggleAutoProgress( 1 )
        return
    }

    ; avoids attempts to stack again after stacking has been completed and level not reset yet.
    AvoidRestackTest()
    {
        if(stacks >= g_BrivUserSettings[ "TargetStacks" ])
            return 1
        if(g_SF.Memory.ReadCurrentZone() == 1)
            return 1
        if(!g_BrivUserSettings["AutoCalculateBrivStacks"] AND g_SF.Memory.ReadHasteStacks() >= g_BrivUserSettings[ "TargetStacks" ])
            return 1
        if(g_BrivUserSettings["AutoCalculateBrivStacks"]  AND g_SF.Memory.ReadHasteStacks() >= g_SharedData.TargetStacks)
            return 1
        return 0
    }

    ; Sends calls for buying or opening chests and tracks chest metrics.
    DoChests(numSilverChests, numGoldChests)
    {
        StartTime := A_TickCount
        loopString := ""
        if(!g_BrivUserSettings[ "DoChestsContinuous" ])
        {
            loopString := this.BuyOrOpenChests(StartTime, Min(numSilverChests, 99), Min(numGoldChests, 99)) . " "
            OutputDebug, % loopString
            return loopString
        }
        startingPurchasedSilverChests := g_SharedData.PurchasedSilverChests
        startingPurchasedGoldChests := g_SharedData.PurchasedGoldChests
        startingOpenedGoldChests := g_SharedData.OpenedGoldChests
        startingOpenedSilverChests := g_SharedData.OpenedSilverChests
        currentChestTallies := startingPurchasedSilverChests + startingPurchasedGoldChests + startingOpenedGoldChests + startingOpenedSilverChests
        ElapsedTime := 0
        doHybridStacking := ( g_BrivUserSettings[ "ForceOfflineGemThreshold" ] > 0 ) OR ( g_BrivUserSettings[ "ForceOfflineRunThreshold" ] > 1 )
        while( ( g_BrivUserSettings[ "RestartStackTime" ] > ElapsedTime ) OR doHybridStacking)
        {
            ElapsedTime := A_TickCount - StartTime
            g_SharedData.LoopString := "Stack Sleep: " . g_BrivUserSettings[ "RestartStackTime" ] - ElapsedTime . " " . loopString
            effectiveStartTime := doHybridStacking ? A_TickCount + 30000 : StartTime ; 30000 is an arbitrary time that is long enough to do buy/open (100/99) of both gold and silver chests.
            this.BuyOrOpenChests(effectiveStartTime)
            updatedTallies := g_SharedData.PurchasedSilverChests + g_SharedData.PurchasedGoldChests + g_SharedData.OpenedGoldChests + g_SharedData.OpenedSilverChests
            thisLoopString := this.GetChestDifferenceString(startingPurchasedSilverChests, startingPurchasedGoldChests, startingOpenedGoldChests, startingOpenedSilverChests)
            loopString := thisLoopString == "" ? loopString : thisLoopString
            if(updatedTallies == currentChestTallies) ; call failed, likely ran out of time. Don't want to call more if out of time.
            {
                OutputDebug, % loopString
                loopString := loopString == "" ? "Chests ----" : loopString
                return loopString
            }
            currentChestTallies := updatedTallies
        }
        return loopString
    }

    ; Builds a string that shows how many chests have been opened/bought above the values passed into this function.
    GetChestDifferenceString(lastPurchasedSilverChests, lastPurchasedGoldChests, lastOpenedGoldChests, lastOpenedSilverChests )
    {
        boughtSilver := g_SharedData.PurchasedSilverChests - lastPurchasedSilverChests 
        boughtGold := g_SharedData.PurchasedGoldChests - lastPurchasedGoldChests
        openedSilver := g_SharedData.OpenedSilverChests - lastOpenedSilverChests
        openedGold := g_SharedData.OpenedGoldChests - lastOpenedGoldChests
        buyString := (boughtSilver > 0 AND boughtGold > 0) ? "Buy: (" . boughtSilver . "s, " . boughtGold . "g)" : ""
        openString := (openedSilver > 0 AND openedGold > 0) ? "Open: (" . openedSilver . "s, " . openedGold . "g)" : ""
        separator := ((boughtSilver > 0 OR boughtGold > 0) AND (openedSilver > 0 OR openedGold > 0)) ? ", " : ""
        returnString := buyString . separator . openString
        return ((returnString != "") ? "Chests - " . returnString : "")
    }

    /* ;A function that checks if farmed SB stacks from previous run failed to convert to haste.
       ;If so, the script will manually end the adventure to attempt to convert the stacks, close IC, use a servercall to restart the adventure, and restart IC.
    */
    CheckForFailedConv()
    {
        CurrentZone := g_SF.Memory.ReadCurrentZone()
        targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? this.TargetStacks : g_BrivUserSettings[ "TargetStacks" ]
        variationLeeway := 10
        ; Zone 10 gives plenty leeway for fast starts that skip level 1 while being low enough to not have received briv stacks
        ; needed to ensure DoPartySetup
        if ( !g_BrivUserSettings[ "StackFailRecovery" ] OR CurrentZone > 10)
        {
            return 0
        }
        stacks := g_SF.Memory.ReadHasteStacks() + g_SF.Memory.ReadSBStacks()
        ; stacks not converted to haste properly. Buffer allows for automatic calc variations and possible early jump before calculation done.
        If ((g_SF.Memory.ReadHasteStacks() + variationLeeway) < targetStacks AND stacks >= targetStacks)
        {
            g_SharedData.StackFailStats.TALLY[StackFailStates.FAILED_TO_CONVERT_STACKS] += 1
            g_SF.RestartAdventure( "Failed Conversion" )
            g_SF.SafetyCheck()
            return StackFailStates.FAILED_TO_CONVERT_STACKS ; 2
        }
        ; all stacks were lost on reset. Stack leeway given for automatic calc variations. 
        If ((g_SF.Memory.ReadHasteStacks() + variationLeeway) < targetStacks AND g_SF.Memory.ReadSBStacks() <= variationLeeway)
        {
            g_SharedData.StackFailStats.TALLY[StackFailStates.FAILED_TO_KEEP_STACKS] += 1
            return StackFailStates.FAILED_TO_KEEP_STACKS ; 5
        }
        return 0
    }

    ;===========================================================
    ;Helper functions for Briv Gem Farm
    ;===========================================================
    /*  DoPartySetup - When gem farm is started or a zone is reloaded, this is called to set up the primary party.
                       Levels Shandie and Briv, waits for Shandie Dash to start, completes the quests of the zone and then go time.

        Parameters:

        Returns:
    */
    DoPartySetup()
    {
        formationFavorite1 := g_SF.Memory.GetFormationByFavorite( 1 )
        minLevels := {}, maxLevels := {}
        minLevels[58] := 80, maxLevels[58] := g_BrivUserSettings[ "BrivMaxLevel" ] ; Briv
        minLevels[47] := 120, maxLevels[47] := 120 ; Shandie
        minLevels[91] := 1, maxLevels[91] := 310 ; Widdle 260 310 350
        minLevels[75] := 220, maxLevels[75] := 220 ; Hewmann 40 200 220 360
        minLevels[115] := 100, maxLevels[115] := 100 ; Virgil
        minLevels[114] := 1, maxLevels[114] := 1 ; Kent
        minLevels[79] := 1, maxLevels[79] := 1 ; Shaka
        minLevels[81] := 1, maxLevels[81] := 1 ; Selise
        minLevels[52] := 80, maxLevels[52] := 80 ; Sentry
        minLevels[70] := 90, maxLevels[70] := 90 ; Ezmeralda 90 315
        minLevels[12] := 65, maxLevels[12] := 65 ; Arkhan
        minLevels[4] := 1, maxLevels[4] := 2150 ; Jarlaxle
        minLevels[39] := 1, maxLevels[39] := 3440 ; Paultin
        minLevels[113] := 1, maxLevels[113] := 1400 ; Egbert
        minLevels[94] := 1, maxLevels[94] := 2640 ; Rust
        champIDs := [58, 47, 91, 75, 115, 114, 79, 81, 52]
        keyspam := ["{q}"]
        for k, champID in champIDs
        {
            if (g_SF.IsChampInFormation(champID, formationFavorite1) AND g_SF.Memory.ReadChampLvlByID(champID) < minLevels[champID])
                keyspam.Push("{F" . g_SF.Memory.ReadChampSeatByID(champID) . "}")
        }
        setupDone := False
        while(!setupDone)
        {
            g_SF.DirectedInput(,, keyspam*)
            for champID, champMinLevel in minLevels
            {
                if (g_SF.IsChampInFormation(champID, formationFavorite1))
                {
                    level := g_SF.Memory.ReadChampLvlByID(champID)
                    Fkey := "{F" . g_SF.Memory.ReadChampSeatByID(champID) . "}"
                    if (level >= champMinLevel)
                    {
                        for k, v in keyspam
                        {
                            if (v == Fkey)
                                keyspam.Delete(k)
                        }
                    }
                }
            }
            if (keyspam.Length() == 1)
                setupDone := true
            Sleep, 20
        }
        if(g_BrivUserSettings[ "BrivMaxLevel" ] >= 170)
            minLevels[58] := 170
        champIDs := [58, 47, 91, 75, 115, 114, 79, 81, 52, 70, 12, 4, 39, 113, 94]
        keyspam := []
        for k, champID in champIDs
        {
            if (g_SF.IsChampInFormation(champID, formationFavorite1) AND g_SF.Memory.ReadChampLvlByID(champID) < maxLevels[champID])
                keyspam.Push("{F" . g_SF.Memory.ReadChampSeatByID(champID) . "}")
        }
        setupDone := False
        while(!setupDone)
        {
            g_SF.SetFormation(g_BrivUserSettings)
            for champID, champMinLevel in minLevels
            {
                if (g_SF.IsChampInFormation(champID, formationFavorite1))
                {
                    level := g_SF.Memory.ReadChampLvlByID(champID)
                    Fkey := "{F" . g_SF.Memory.ReadChampSeatByID(champID) . "}"
                    if (level >= champMinLevel)
                    {
                        for k, v in keyspam
                        {
                            if (v == Fkey)
                                keyspam.Delete(k)
                        }
                    }
                }
            }
            g_SF.DirectedInput(,, keyspam*)
            if (keyspam.Length() == 0)
                setupDone := true
            Sleep, 20
        }
        g_SF.DirectedInput(hold:=0,, keyspam*)
        if(g_BrivUserSettings[ "Fkeys" ])
        {
            g_SF.DirectedInput(,release :=0, keyspam*) ;keysdown
        }
        g_SF.ModronResetZone := g_SF.Memory.GetModronResetArea() ; once per zone in case user changes it mid run.
        if (g_SF.ShouldDashWait())
            g_SF.DoDashWait( Max(g_SF.ModronResetZone - g_BrivUserSettings[ "DashWaitBuffer" ], 0) )
        g_SF.ToggleAutoProgress( 1, false, true )
        return keyspam*
    }

    DoPartySetupAfter()
    {
        maxLevels := {}
        maxLevels[58] := g_BrivUserSettings[ "BrivMaxLevel" ] ; Briv
        if (maxLevels[58] < 170)
        {
            targetStacks := g_BrivUserSettings[ "AutoCalculateBrivStacks" ] ? this.TargetStacks : g_BrivUserSettings[ "TargetStacks" ]
            if g_SF.Memory.ReadSBStacks() >= targetStacks
                maxLevels[58] := 170
        }
        maxLevels[91] := 310 ; Widdle 260 310 350
        maxLevels[75] := 220 ; Hewmann 220 360
        maxLevels[4] := 2150 ; Jarlaxle
        maxLevels[39] := 3440 ; Paultin
        maxLevels[113] := 1400 ; Egbert
        maxLevels[94] := 2640 ; Rust
        formationFavorite1 := g_SF.Memory.GetFormationByFavorite( 1 )
        for champID, champMaxLevel in maxLevels
        {
            if (g_SF.IsChampInFormation(champID, formationFavorite1))
            {
                level := g_SF.Memory.ReadChampLvlByID(champID)
                Fkey := "{F" . g_SF.Memory.ReadChampSeatByID(champID) . "}"
                if (level < champMaxLevel)
                {
                    g_SF.DirectedInput(,, Fkey) ;keysdownup
                    return
                }
            }
        }
    }

    ;Waits for modron to reset. Closes IC if it fails.
    ModronResetCheck()
    {
        modronResetTimeout := 75000
        if(!g_SF.WaitForModronReset(modronResetTimeout))
            g_SF.CheckifStuck()
            ;g_SF.CloseIC( "ModronReset, resetting exceeded " . Floor(modronResetTimeout/1000) . "s" )
        g_PreviousZoneStartTime := A_TickCount
    }

    ;===========================================================
    ;functions for speeding up progression through an adventure.
    ;===========================================================

    ;=====================================================
    ;Functions for direct server calls between runs
    ;=====================================================
    /*  BuyOrOpenChests - A method to buy or open silver or gold chests based on parameters passed.

        Parameters:
        startTime - The number of milliseconds that have elapsed since the system was started, up to 49.7 days.
        numSilverChestsToOpen and numGoldChestsToOpen - expected number of chests to open in this iteration of calls.
            Used to estimate if there is enough time to perform those actions before attempting to do them.

        Return Values:
        None

        Side Effects:
        On success opening or buying, will update g_SharedData.
        On success and shinies found, will increment g_SharedData.ShinyCount by number of shinies found.

        Notes:
        First line is ignoring fact that once every 49 days this func can potentially be called w/ startTime at 0 ms.
    */
    BuyOrOpenChests( startTime := 0, numSilverChestsToOpen := 99, numGoldChestsToOpen := 99 )
    {
        startTime := startTime ? startTime : A_TickCount
        var := ""
        var2 := ""
        openSilverChestTimeEst := numSilverChestsToOpen * 30.3 ; ~3s
        openGoldChestTimeEst := numGoldChestsToOpen * 60.6 ; ~7s
        purchaseTime := 100 ; .1s
        gems := g_SF.TotalGems - g_BrivUserSettings[ "MinGemCount" ]
        if ( g_BrivUserSettings[ "BuySilvers" ] AND g_BrivUserSettings[ "RestartStackTime" ] > ( A_TickCount - startTime + purchaseTime) )
        {
            amount := Min(Floor(gems / 50), 100 )
            if(amount > 0)
            {
                response := g_ServerCall.callBuyChests( chestID := 1, amount )
                if(response.okay AND response.success)
                {
                    g_SharedData.PurchasedSilverChests += amount
                    g_SF.TotalGems := response.currency_remaining
                    gems := g_SF.TotalGems - g_BrivUserSettings[ "MinGemCount" ]
                }
            }
        }
        if ( g_BrivUserSettings[ "BuyGolds" ] AND g_BrivUserSettings[ "RestartStackTime" ] > ( A_TickCount - startTime + purchaseTime) )
        {
            amount := Min(Floor(gems / 500) , 100 )
            if(amount > 0)
            {
                response := g_ServerCall.callBuyChests( chestID := 2, amount )
                if(response.okay AND response.success)
                {
                    g_SharedData.PurchasedGoldChests += amount
                    g_SF.TotalGems := response.currency_remaining
                    gems := g_SF.TotalGems - g_BrivUserSettings[ "MinGemCount" ]
                }
            }
        }
        if ( g_BrivUserSettings[ "OpenSilvers" ] AND g_SF.TotalSilverChests > 0 AND (g_BrivUserSettings[ "RestartStackTime" ] > ( A_TickCount - startTime + openSilverChestTimeEst) AND g_SF.TotalSilverChests > 99))
        {
            amount := Min(g_SF.TotalSilverChests, 99)
            chestResults := g_ServerCall.callOpenChests( chestID := 1, amount )
            if(chestResults.success)
            {
                g_SharedData.OpenedSilverChests += amount
                g_SF.TotalSilverChests := chestResults.chests_remaining
                g_SharedData.ShinyCount += g_SF.ParseChestResults( chestResults )
            }
        }
        if ( g_BrivUserSettings[ "OpenGolds" ] AND g_SF.TotalGoldChests > 0 AND (g_BrivUserSettings[ "RestartStackTime" ] > ( A_TickCount - startTime + openGoldChestTimeEst) OR g_SF.TotalGoldChests > 99))
        {
            amount := Min(g_SF.TotalGoldChests, 99)
            chestResults := g_ServerCall.callOpenChests( chestID := 2, amount )
            if(chestResults.success)
            {
                g_SharedData.OpenedGoldChests += amount
                g_SF.TotalGoldChests := chestResults.chests_remaining
                g_SharedData.ShinyCount += g_SF.ParseChestResults( chestResults )
            }
        }
    }
}

#include %A_LineFile%\..\..\..\SharedFunctions\ObjRegisterActive.ahk
