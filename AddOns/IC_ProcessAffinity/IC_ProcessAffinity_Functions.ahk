class IC_ProcessAffinity_SharedFunctions_Class extends IC_BrivSharedFunctions_Class
{
    ; Attemps to open IC. Game should be closed before running this function or multiple copies could open.
    OpenIC()
    {
        timeoutVal := 32000
        loadingDone := false
        g_SharedData.LoopString := "Starting Game"
        waitForProcessTime := g_UserSettings[ "WaitForProcessTime" ]
        WinGetActiveTitle, savedActive
        this.SavedActiveWindow := savedActive
        while ( !loadingZone AND ElapsedTime < timeoutVal )
        {
            this.Hwnd := 0
            this.PID := 0
            while (!this.PID AND ElapsedTime < timeoutVal )
            {
                StartTime := A_TickCount
                ElapsedTime := 0
                g_SharedData.LoopString := "Opening IC.."
                programLoc := g_UserSettings[ "InstallPath" ]
                Run, %programLoc%
                Sleep, %waitForProcessTime%
                while(ElapsedTime < 10000 AND !this.PID )
                {
                    ElapsedTime := A_TickCount - StartTime
                    existingProcessID := g_userSettings[ "ExeName"]
                    Process, Exist, %existingProcessID%
                    this.PID := ErrorLevel
                }
            }
            ; Process exists, wait for the window:
            while(!(this.Hwnd := WinExist( "ahk_exe " . g_userSettings[ "ExeName"] )) AND ElapsedTime < timeoutVal)
            {
                WinGetActiveTitle, savedActive
                this.SavedActiveWindow := savedActive
                ElapsedTime := A_TickCount - StartTime
            }
            if(ElapsedTime < timeoutVal)
            {
                this.ActivateLastWindow()
                Process, Priority, % this.PID, High
                ProcessHandle := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", False, "UInt", this.PID)
                DllCall("SetProcessAffinityMask", "UInt", ProcessHandle, "UInt", (3 << 16) + (3 << 22))
                DllCall("CloseHandle", "UInt", ProcessHandle)
                this.Memory.OpenProcessReader()
                loadingZone := this.WaitForGameReady()
                this.ResetServerCall()
            }
        }
        if(ElapsedTime >= timeoutVal)
            return -1 ; took too long to open
        else
            return 0
    }
}