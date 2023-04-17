#include %A_LineFile%\..\IC_ProcessAffinity_Functions.ahk
#include %A_LineFile%\..\..\..\SharedFunctions\IC_UpdateClass_Class.ahk
IC_UpdateClass_Class.UpdateClassFunctions(g_SF, IC_ProcessAffinity_SharedFunctions_Class)
IC_ProcessAffinity_Functions.SetProcessAffinityInverse(DllCall("GetCurrentProcessId")) ; IC_BrivGemFarm_Run.ahk