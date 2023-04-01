GUIFunctions.AddTab("Process Affinity")

global g_ProcessAffinity := new IC_ProcessAffinity_Component

; Add GUI fields to this addon's tab.
Gui, ICScriptHub:Tab, Process Affinity
Gui, ICScriptHub:Font, w700
Gui, ICScriptHub:Add, Text, , Core affinity:
Gui, ICScriptHub:Font, w400

;GUIFunctions.UseThemeTextColor("TableTextColor")

IC_ProcessAffinity_Functions.BuildCoreTable()

#include %A_LineFile%\..\IC_ProcessAffinity_Functions.ahk