; When a check box is checked...
Processor_Click()
{
    Gui, ICScriptHub:Submit, NoHide
    currentControl := A_GuiControl
    isChecked := %A_GuiControl%
    splitString := StrSplit(currentControl, "_")
    modVal := splitString[2]
    currentIndex := splitString[3]
    ;IC_BrivGemFarm_AdvancedSettings_Functions.ToggleSelectedChecksForMod(modVal, currentIndex, isChecked)
}

; IC_ProcessAffinity_Functions
class IC_ProcessAffinity_Functions
{
    ; Loads settings from the addon's setting.json file.
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
        Gui, Submit, NoHide
    }

    ; Saves settings to addon's setting.json file.
    SaveSettings()
    {
        Gui, Submit, NoHide
        this.Settings["ProcessAffinityBitMask"] := g_ProcessAffinityCheckbox
        g_SF.WriteObjectToJSON( A_LineFile . "\..\Settings.json", this.Settings )
    }

    ; Builds labels and checkboxes for PreferredBrivJumpZones
    BuildCoreTable()
    {
        EnvGet, ProcessorCount, NUMBER_OF_PROCESSORS
        len := 8
        loopCount := Floor(ProcessorCount/len)
        modLoopIndex := 0
        loop, %ProcessorCount%
        {
            this.AddControlCheckbox(isChecked, A_Index - 1, Mod(A_Index, len) == 1)
        }
    }

    ; Adds the checkbox control
    AddControlCheckbox(isChecked, loopCount, newRow)
    {
        global
        if (newRow)
            Gui, ICScriptHub:Add, Checkbox, vProcessorMod_%loopCount% Checked%isChecked% x10 y+10 gProcessor_Click, % loopCount
        else
            Gui, ICScriptHub:Add, Checkbox, vProcessorMod_%loopCount% Checked%isChecked% xp+35 gProcessor_Click, % loopCount
    }
}