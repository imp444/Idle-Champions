GUIFunctions.AddTab("Process Affinity")

global g_ProcessAffinity := new IC_ProcessAffinity_Component

; Add GUI fields to this addon's tab.
Gui, ICScriptHub:Tab, Process Affinity
Gui, ICScriptHub:Font, w700
Gui, ICScriptHub:Add, Text, , Core affinity:
Gui, ICScriptHub:Font, w400
Gui, ICScriptHub:Add, Button , x+10 vProcessAffinitySave gProcessAffinitySave, Save

Gui, ICScriptHub:Add, ListView, AltSubmit Checked -Hdr -Multi x15 y+5 w120 h320 vProcessAffinityView gProcessAffinityView, CoreID
GUIFunctions.UseThemeListViewBackgroundColor("ProcessAffinityView")
IC_ProcessAffinity_Component.BuildCoreList()

ProcessAffinitySave()
{
    IC_ProcessAffinity_Functions.SaveSettings()
}

ProcessAffinityView()
{
    if (A_GuiEvent == "I")
    {
        if InStr(ErrorLevel, "C", true)
            IC_ProcessAffinity_Component.Update(A_EventInfo, 1)
        else if InStr(ErrorLevel, "c", true)
            IC_ProcessAffinity_Component.Update(A_EventInfo, 0)
    }
}

Class IC_ProcessAffinity_Component
{
    ; Builds checkboxes for CoreAffinity
    BuildCoreList()
    {
        EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
        if (ProcessorCount > 64) ; TODO: Support for CPU Groups
        {
            GuiControl, Disable, ProcessAffinitySave
            return
        }
        isChecked := "Check" ; TODO: Load from file
        LV_Add(isChecked, "All processors")
        loop, %ProcessorCount%
        {
            LV_Add(isChecked, "CPU " . A_Index - 1)
        }
    }

    ; Loads settings from the addon's setting.json file. TODO
    LoadSettings()
    {
        this.Settings := g_SF.LoadObjectFromJSON( A_LineFile . "\..\Settings.json")
        if(this.Settings == "")
        {
            this.Settings := {}
            this.Settings["ProcessAffinityBitMask"] := True
            this.SaveSettings()
        }
        if(this.Settings["ProcessAffinityBitMask"] == "")
            this.Settings["ProcessAffinityBitMask"] := True
        GuiControl,ICScriptHub:, g_ProcessAffinityCheckbox, % this.Settings["ProcessAffinityBitMask"]
    }

     ; Saves settings to addon's setting.json file. TODO
    SaveSettings()
    {
        this.Settings["ProcessAffinityBitMask"] := g_ProcessAffinityCheckbox
        g_SF.WriteObjectToJSON( A_LineFile . "\..\Settings.json", this.Settings )
    }

    ; Update checkboxes
    Update(checkBoxIndex := 0, on := 1)
    {
        if (checkBoxIndex == 1)
            this.ToggleAllCores(on)
        else if (!on)
            LV_Modify(1, "-Check")
        else if (this.AreAllCoresChecked())
            LV_Modify(1, "Check")
        if (LV_GetNext(,"Checked") == 0)
            GuiControl, Disable, ProcessAffinitySave
        else
            GuiControl, Enable, ProcessAffinitySave
    }

    ; Toggle all cores, toggle on if at least one core was previously unchecked
    ToggleAllCores(on := 1)
    {
        if (!on AND !this.AreAllCoresChecked())
            return
        loop % LV_GetCount() - 1 ; Skip the all core toggle chechbox
        {
            LV_Modify(A_Index + 1, on ? "Check" : "-Check")
        }
    }

    ; Returns true if all the core checkboxes are checked
    AreAllCoresChecked()
    {
        rowNumber := 1 ; This causes the first loop iteration to start the search at the top of the list.
        loop
        {
            nextChecked := LV_GetNext(RowNumber, "C")
            if (nextChecked - rowNumber > 1)
                return false
            if (not rowNumber OR rowNumber == LV_GetCount()) ; There are no more selected rows.
                return true
            rowNumber := nextChecked ; Resume the search at the row after that found by the previous iteration.
        }
        return false
    }
}

#include %A_LineFile%\..\IC_ProcessAffinity_Functions.ahk