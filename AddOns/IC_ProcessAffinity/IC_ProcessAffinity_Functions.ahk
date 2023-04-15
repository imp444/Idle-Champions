IC_ProcessAffinity_Functions.InjectAddon()

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
        ProcessHandle := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", False, "UInt", PID)
        DllCall("SetProcessAffinityMask", "UInt", ProcessHandle, "UInt", 12779520)
        DllCall("CloseHandle", "UInt", ProcessHandle)
    }
}

class IC_ProcessAffinity_SharedFunctions_Class extends IC_BrivSharedFunctions_Class
{
    ; Runs the process and set this.PID once it is found running.
    OpenProcessAndSetPID(timeoutLeft := 32000)
    {
        this.PID := 0
        processWaitingTimeout := 10000 ;10s
        waitForProcessTime := g_UserSettings[ "WaitForProcessTime" ]
        ElapsedTime := 0
        StartTime := A_TickCount
        while (!this.PID AND ElapsedTime < timeoutLeft )
        {
            g_SharedData.LoopString := "Opening IC.."
            programLoc := g_UserSettings[ "InstallPath" ]
            Run, %programLoc%
            Sleep, %waitForProcessTime%
            while(!this.PID AND ElapsedTime < processWaitingTimeout AND ElapsedTime < timeoutLeft)
            {
                existingProcessID := g_userSettings[ "ExeName"]
                Process, Exist, %existingProcessID%
                this.PID := ErrorLevel
                Sleep, 62
                ElapsedTime := A_TickCount - StartTime
            }
            ElapsedTime := A_TickCount - StartTime
            Sleep, 62
        }
        if (this.PID)
            IC_ProcessAffinity_Functions.SetProcessAffinity(this.PID)
    }
}