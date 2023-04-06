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

; Save button
ProcessAffinitySave()
{
    IC_ProcessAffinity_Component.SaveSettings()
}

; ViewList
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
        ProcessorCount := 32
        this.ProcessorCount := ProcessorCount
        if (ProcessorCount > 64) ; TODO: Support for CPU Groups
        {
            GuiControl, Disable, ProcessAffinitySave
            return
        }
        this.LoadSettings()
        LV_Add("Check", "All processors") ; First check all boxes
        loop, %ProcessorCount%
        {
            LV_Add("Check", "CPU " . A_Index - 1)
        }
        settings := this.Settings["ProcessAffinityMask"]
        loop, %ProcessorCount% ; Uncheck boxes
        {
            checked := (settings & (2 ** (A_Index - 1))) > 0
            if (!checked)
                this.Update(A_Index + 1, 0)
        }
    }

    ; Loads settings from the addon's setting.json file.
    LoadSettings()
    {
        this.Settings := g_SF.LoadObjectFromJSON( A_LineFile . "\..\Settings.json")
        if(this.Settings == "")
            this.Settings := {}
        if (this.Settings["ProcessAffinityMask"] == "")
        {
            coreMask := 0
            loop, % this.ProcessorCount ; Sum up all bits
            {
                coreMask += 2 ** (A_Index - 1)
            }
            this.Settings["ProcessAffinityMask"] := coreMask
        }
    }

     ; Saves settings to addon's setting.json file.
    SaveSettings()
    {
        coreMask := 0
        rowNumber := 1 ; This causes the first loop iteration to start the search at the top of the list.
        loop
        {
            nextChecked := LV_GetNext(RowNumber, "C")
            if (not nextChecked)
                break
            rowNumber := nextChecked ; Resume the search at the row after that found by the previous iteration.
            coreMask += 2 ** (rowNumber - 2)
        }
        if (coremask == 0)
            return
        this.Settings["ProcessAffinityMask"] := coreMask
        g_SF.WriteObjectToJSON( A_LineFile . "\..\Settings.json", this.Settings )
    }

    ; Update checkboxes
    Update(checkBoxIndex := 0, on := 1)
    {
        if (checkBoxIndex == 1) ; Toggle all checkbox
            this.ToggleAllCores(on)
        else if (!on)
        {
            LV_Modify(checkBoxIndex, "-Check")
            LV_Modify(1, "-Check")
        }
        else if (this.AreAllCoresChecked())
            LV_Modify(1, "Check")
        if (LV_GetNext(,"Checked") == 0) ; Disable save if no cores are selected
            GuiControl, Disable, ProcessAffinitySave
        else
            GuiControl, Enable, ProcessAffinitySave
    }

    ; Toggle all cores, toggle on if at least one core was previously unchecked
    ToggleAllCores(on := 1)
    {
        if (!on AND !this.AreAllCoresChecked())
            return
        loop % LV_GetCount() - 1 ; Skip the toggle all checkbox
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
            nextChecked := LV_GetNext(rowNumber, "C")
            if (nextChecked - rowNumber > 1) ; Skipped over an unchecked box
                return false
            if (not rowNumber OR rowNumber == LV_GetCount()) ; There are no more selected rows.
                return true
            rowNumber := nextChecked ; Resume the search at the row after that found by the previous iteration.
        }
        return false
    }
}

#include %A_LineFile%\..\IC_ProcessAffinity_Functions.ahk