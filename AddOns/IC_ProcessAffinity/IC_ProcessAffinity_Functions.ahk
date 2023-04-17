class IC_ProcessAffinity_Functions
{
    ; Adds IC_ProcessAffinity_Addon.ahk to the startup of the Briv Gem Farm script.
    InjectAddon()
    {
        splitStr := StrSplit(A_LineFile, "\")
        addonDirLoc := splitStr[(splitStr.Count()-1)]
        addonLoc := "#include *i %A_LineFile%\..\..\" . addonDirLoc . "\IC_ProcessAffinity_Addon.ahk`n"
        FileAppend, %addonLoc%, %g_BrivFarmModLoc%
    }

    SetProcessAffinity(PID := 0)
    {
        if (PID == 0)
            return
        ProcessHandle := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", False, "UInt", PID)
        DllCall("SetProcessAffinityMask", "UInt", ProcessHandle, "UInt", 12779520)
        DllCall("CloseHandle", "UInt", ProcessHandle)
    }

    SetProcessAffinityInverse(PID := 0)
    {
        if (PID == 0)
            return
        ProcessHandle := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", False, "UInt", PID)
        DllCall("SetProcessAffinityMask", "UInt", ProcessHandle, "UInt", 3997695)
        DllCall("CloseHandle", "UInt", ProcessHandle)
    }

    SetAllAffinities()
    {
        existingProcessID := g_UserSettings[ "ExeName"]
        Process, Exist, %existingProcessID%
        gamePID := ErrorLevel
        this.SetProcessAffinity(gamePID)
    }
}

class IC_ProcessAffinity_SharedFunctions_Class extends IC_BrivSharedFunctions_Class
{
    ; Set affinity after restart
    OpenProcessAndSetPID(timeoutLeft := 32000)
    {
        base.OpenProcessAndSetPID(timeoutLeft)
        IC_ProcessAffinity_Functions.SetProcessAffinity(this.PID) ; IdleDragons.exe
    }

    ; Set affinity after clicking "Start Gem Farm"
    VerifyAdventureLoaded()
    {
        IC_ProcessAffinity_Functions.SetProcessAffinity(this.PID) ; IdleDragons.exe
        return base.VerifyAdventureLoaded()
    }
}