#Requires AutoHotkey v2.0
; ===========================================================================
; lib/hotkeys.ahk — configurable hotkeys, with a UI for changing them.
;
; The backtick that opens the menu is a poor default to impose on everyone:
; on US-International — a common layout for anyone typing Dutch, French or
; German — it is a dead key, waiting to compose à/è/ù, so claiming it
; globally breaks accented typing. On UK and other ISO layouts it sits
; somewhere different again.
;
; Bindings are stored in settings.ini in AutoHotkey syntax (^!c), but nobody
; should have to write that: the editor captures the keystroke you actually
; press and shows it as "Ctrl+Alt+C".
; ===========================================================================

global HK_Registered := Map()    ; binding string -> true, for what is live

; Display order in the editor, and the order things register in.
HK_ORDER := ["Palette", "QuickTrans", "Menu", "MenuCentred", "Clipboard", "LibraryEditor",
             "GoogleSearch", "DesktopSearch", "Reload"]

HK_Labels() {
    static labels := Map(
        "Palette",       "Open the palette (search everything)",
        "QuickTrans",    "Translate the selection (QuickTrans)",
        "Menu",          "Open Text Commander (clipboard + menu)",
        "MenuCentred",   "Classic popup menu",
        "Clipboard",     "Clipboard history",
        "LibraryEditor", "Library Editor",
        "GoogleSearch",  "Google the selection",
        "DesktopSearch", "Search the desktop (dtSearch)",
        "Reload",        "Reload Text Commander"
    )
    return labels
}

HK_Actions() {
    static actions := Map(
        "Palette",       () => PAL_Show(),
        "QuickTrans",    () => MW_ShowQuickTrans(),
        "Menu",          () => MW_Show(),
        "MenuCentred",   () => ShowMainMenu(132, 164),
        "Clipboard",     () => CB_Show(),
        "LibraryEditor", () => OpenLibraryEditor(),
        "GoogleSearch",  () => RunAction("GoogleSearch"),
        "DesktopSearch", () => RunAction("dtSearch"),
        "Reload",        () => Reload()
    )
    return actions
}

; A backtick has to be written as two here — it is AutoHotkey's escape char.
HK_Defaults() {
    static defaults := Map(
        "Palette",       "^!Space",
        "QuickTrans",    "^!t",
        "Menu",          "``",
        "MenuCentred",   "^``",
        "Clipboard",     "^!c",
        "LibraryEditor", "",        ; off unless asked for
        "GoogleSearch",  "^/",
        "DesktopSearch", "^+d",
        "Reload",        "^r"
    )
    return defaults
}

; ---------------------------------------------------------------------------
HK_Load() {
    global HK_ORDER
    out := Map()
    for name in HK_ORDER
        out[name] := Trim(AI_Ini(SettingsFile(), "Hotkeys", name,
                                 HK_Defaults()[name]))
    return out
}

HK_SaveToIni(bindings) {
    global HK_ORDER
    for name in HK_ORDER {
        try IniWrite(bindings[name], SettingsFile(), "Hotkeys", name)
        catch Error as err {
            MsgBox("Could not write settings.ini:`n`n" err.Message,
                   "Text Commander", "Icon!")
            return false
        }
    }
    return true
}

; Turn off whatever is live, then bind the given set. Rebinding without the
; first step would leave the old key working as well as the new one.
HK_Apply(bindings) {
    global HK_Registered, HK_ORDER

    for binding, _ in HK_Registered {
        try Hotkey(binding, "Off")
    }
    HK_Registered := Map()

    problems := ""
    for name in HK_ORDER {
        binding := bindings.Has(name) ? Trim(bindings[name]) : ""
        if (binding = "")            ; empty means deliberately switched off
            continue
        try {
            Hotkey(binding, HK_Wrap(HK_Actions()[name]), "On")
            HK_Registered[binding] := true
        } catch Error as err {
            problems .= "`n  " HK_Labels()[name] "  ->  " binding
                     . "   (" err.Message ")"
        }
    }
    return problems
}

RegisterConfiguredHotkeys() {
    problems := HK_Apply(HK_Load())
    if (problems != "")
        MsgBox("These shortcuts could not be registered:" problems
               "`n`nOpen the menu and choose “Keyboard shortcuts…” to fix "
               "them. The rest of Text Commander is running normally.",
               "Text Commander", "Icon!")
}

; Hotkey() passes the hotkey name to its callback; the actions take none.
HK_Wrap(action) {
    return (*) => action()
}

; ---------------------------------------------------------------------------
; Turning "^!c" into "Ctrl+Alt+C" and back is only for display — settings.ini
; always holds the AutoHotkey form.
; ---------------------------------------------------------------------------
HK_Display(binding) {
    if (binding = "")
        return "(none)"

    parts := ""
    i := 1
    while (i <= StrLen(binding)) {
        c := SubStr(binding, i, 1)
        if (c = "^")
            parts .= "Ctrl+"
        else if (c = "!")
            parts .= "Alt+"
        else if (c = "+")
            parts .= "Shift+"
        else if (c = "#")
            parts .= "Win+"
        else
            break
        i++
    }

    key := SubStr(binding, i)
    if (key = Chr(96))
        key := "` (backtick)"
    else if (StrLen(key) = 1)
        key := StrUpper(key)

    return parts key
}

; ---------------------------------------------------------------------------
; Capture the next keystroke and return it in AutoHotkey syntax.
; Returns "" if the user pressed Escape or the capture timed out.
; ---------------------------------------------------------------------------
HK_Capture(ownerHwnd) {
    captured := ""
    done := false

    g := Gui("+Owner" ownerHwnd " +ToolWindow +AlwaysOnTop",
             "Press a shortcut")
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "xm ym w320 Center",
          "Press the key combination you want to use.")
    g.Add("Text", "xm y+10 w320 Center cGray",
          "Escape cancels.  Backspace clears the shortcut.")
    g.Show("w340")

    ih := InputHook("B L0")
    ih.KeyOpt("{All}", "N")     ; notify on every key, swallow nothing extra
    ih.OnKeyDown := OnKey
    ih.Start()

    OnKey(hook, vk, sc) {
        name := GetKeyName(Format("vk{:X}sc{:X}", vk, sc))

        ; Modifiers alone are not a shortcut; wait for a real key.
        if (name ~= "i)^(LControl|RControl|Control|LAlt|RAlt|Alt"
                  . "|LShift|RShift|Shift|LWin|RWin|Win)$")
            return

        if (name = "Escape") {
            captured := "CANCEL"
            done := true
            hook.Stop()
            return
        }
        if (name = "Backspace") {
            captured := ""
            done := true
            hook.Stop()
            return
        }

        mods := ""
        if GetKeyState("Ctrl")
            mods .= "^"
        if GetKeyState("Alt")
            mods .= "!"
        if GetKeyState("Shift")
            mods .= "+"
        if GetKeyState("LWin") || GetKeyState("RWin")
            mods .= "#"

        captured := mods name
        done := true
        hook.Stop()
    }

    ; Wait for a key, but never hang if something goes wrong.
    waited := 0
    while (!done && waited < 10000) {
        Sleep(30)
        waited += 30
    }

    try ih.Stop()
    g.Destroy()

    if (captured = "CANCEL")
        return ""
    return captured
}

; ---------------------------------------------------------------------------
; The editor.
; ---------------------------------------------------------------------------
global HKE_Gui  := ""
global HKE_List := ""
global HKE_Work := ""      ; working copy, only written on Save

OpenHotkeyEditor(*) {
    global HKE_Gui, HKE_List, HKE_Work

    if (HKE_Gui != "") {
        HKE_Gui.Show()
        return
    }

    HKE_Work := HK_Load()

    HKE_Gui := Gui("+Resize +MinSize520x340", "Text Commander — Keyboard shortcuts")
    HKE_Gui.SetFont("s9", "Segoe UI")
    HKE_Gui.OnEvent("Close", HKE_Close)
    HKE_Gui.OnEvent("Escape", HKE_Close)

    HKE_Gui.Add("Text", "xm ym w560",
                "Double-click a shortcut to change it.")

    HKE_List := HKE_Gui.Add("ListView", "xm y+8 w560 h280",
                            ["Action", "Shortcut"])
    HKE_List.OnEvent("DoubleClick", (*) => HKE_Change())

    HKE_Gui.Add("Button", "xm y+10 w110", "Change…")
        .OnEvent("Click", (*) => HKE_Change())
    HKE_Gui.Add("Button", "x+6 w110", "Turn off")
        .OnEvent("Click", (*) => HKE_Clear())
    HKE_Gui.Add("Button", "x+6 w130", "Reset to default")
        .OnEvent("Click", (*) => HKE_ResetOne())
    HKE_Gui.Add("Button", "x+40 w90 Default", "Save")
        .OnEvent("Click", (*) => HKE_Save())
    HKE_Gui.Add("Button", "x+6 w70", "Close")
        .OnEvent("Click", (*) => HKE_Close())

    HKE_Refresh()
    HKE_Gui.Show("w600 h400")
}

HKE_Refresh() {
    global HKE_List, HKE_Work, HK_ORDER
    HKE_List.Opt("-Redraw")
    HKE_List.Delete()
    for name in HK_ORDER
        HKE_List.Add(, HK_Labels()[name], HK_Display(HKE_Work[name]))
    HKE_List.ModifyCol(1, 330)
    HKE_List.ModifyCol(2, 200)
    HKE_List.Opt("+Redraw")
}

HKE_SelectedName() {
    global HKE_List, HK_ORDER
    row := HKE_List.GetNext(0)
    if (row = 0) {
        MsgBox("Select a shortcut first.", "Keyboard shortcuts", "Icon!")
        return ""
    }
    return HK_ORDER[row]
}

HKE_Change() {
    global HKE_Gui, HKE_Work, HK_ORDER

    name := HKE_SelectedName()
    if (name = "")
        return

    binding := HK_Capture(HKE_Gui.Hwnd)
    if (binding = "" ) {
        ; Escape cancelled, or Backspace asked for it to be turned off.
        HKE_Refresh()
        return
    }

    ; Refuse a combination that will not register rather than saving a
    ; shortcut that silently does nothing.
    try {
        Hotkey(binding, (*) => "", "On")
        Hotkey(binding, "Off")
    } catch Error as err {
        MsgBox("Windows will not accept that combination:`n`n"
               HK_Display(binding) "`n`n" err.Message,
               "Keyboard shortcuts", "Icon!")
        return
    }

    ; Two actions on one key would mean the second silently wins.
    for other in HK_ORDER {
        if (other != name && HKE_Work[other] = binding) {
            if (MsgBox(HK_Display(binding) " is already used by:`n`n    "
                       HK_Labels()[other] "`n`nAssign it here instead? That "
                       "will turn the other one off.",
                       "Keyboard shortcuts", "YesNo Icon?") != "Yes")
                return
            HKE_Work[other] := ""
        }
    }

    HKE_Work[name] := binding
    HKE_Refresh()
}

HKE_Clear() {
    global HKE_Work
    name := HKE_SelectedName()
    if (name = "")
        return
    HKE_Work[name] := ""
    HKE_Refresh()
}

HKE_ResetOne() {
    global HKE_Work
    name := HKE_SelectedName()
    if (name = "")
        return
    HKE_Work[name] := HK_Defaults()[name]
    HKE_Refresh()
}

HKE_Save() {
    global HKE_Work
    if !HK_SaveToIni(HKE_Work)
        return

    problems := HK_Apply(HKE_Work)
    if (problems != "") {
        MsgBox("Saved, but these could not be registered:" problems,
               "Keyboard shortcuts", "Icon!")
        return
    }
    MsgBox("Shortcuts saved and active.", "Keyboard shortcuts", "Iconi T2")
}

HKE_Close(*) {
    global HKE_Gui
    try HKE_Gui.Destroy()
    HKE_Gui := ""
    return true
}
