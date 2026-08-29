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
             "GoogleSearch", "DesktopSearch", "ConfirmSegment",
             "Reload"]

HK_Labels() {
    static labels := Map(
        "Palette",       "Open the palette (search everything)",
        "QuickTrans",    "Translate the selection (QuickTrans)",
        "Menu",          "Open Supervertaler Sidekick (clipboard + menu)",
        "MenuCentred",   "Classic popup menu",
        "Clipboard",     "Clipboard history",
        "LibraryEditor", "Library Editor",
        "GoogleSearch",  "Google the selection",
        "DesktopSearch", "Search the desktop (dtSearch)",
        "ConfirmSegment","Confirm segment (memoQ, Trados)",
        "Reload",        "Reload Supervertaler Sidekick"
    )
    return labels
}

; The built-ins have their behaviour compiled in, so the "Does" column has
; to be told what they do. Anything the user makes describes itself — see
; SC_Describe in lib/shortcuts.ahk.
HK_Does() {
    static does := Map(
        "Palette",       "opens the palette window",
        "QuickTrans",    "translates the selection in the main window",
        "Menu",          "opens the main window",
        "MenuCentred",   "opens the classic popup menu",
        "Clipboard",     "opens the clipboard window",
        "LibraryEditor", "opens the Library Editor",
        "GoogleSearch",  "searches google.co.uk for the selection",
        "DesktopSearch", "searches the desktop with dtSearch",
        "ConfirmSegment","presses Ctrl+Enter",
        "Reload",        "restarts Supervertaler Sidekick"
    )
    return does
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
        ; Confirm-segment is Ctrl+Enter in memoQ, CafeTran and most others;
        ; the point is to reach it from a key that suits your hands.
        "ConfirmSegment",() => Send("^{Enter}"),
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
        ; memoQ and Trados both confirm a segment with Ctrl+Enter. This
        ; puts that on a key you can hit with one hand, without giving up
        ; Ctrl+Enter. It is on by default only because it is scoped: outside
        ; those two applications NumpadEnter is left alone entirely.
        "ConfirmSegment","NumpadEnter@ahk_exe memoQ.exe"
                       . "|NumpadEnter@ahk_exe SDLTradosStudio.exe",
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
                   "Supervertaler Sidekick", "Icon!")
            return false
        }
    }
    return true
}

; Turn off whatever is live, then bind the given set. Rebinding without the
; first step would leave the old key working as well as the new one.
; A binding may name more than one key, separated by "|", and any key may be
; limited to one application by writing key@window. So
;
;   ConfirmSegment=NumpadEnter@ahk_exe memoQ.exe|MButton@ahk_exe CafeTran.exe
;
; gives the same action two keys, each live only in the tool it belongs to.
; That matters: NumpadEnter and the middle mouse button both do useful work
; elsewhere, and a global claim on either would be felt across the whole
; machine rather than in the one program it was meant for.
HK_Apply(bindings) {
    global HK_Registered, HK_ORDER

    for _, reg in HK_Registered {
        try {
            HK_Scope(reg["window"])
            Hotkey(reg["key"], "Off")
        }
    }
    HotIf()
    HK_Registered := Map()

    problems := ""
    for name in HK_ORDER {
        raw := bindings.Has(name) ? Trim(bindings[name]) : ""
        if (raw = "")                ; empty means deliberately switched off
            continue

        for piece in StrSplit(raw, "|") {
            parsed := HK_ParseBinding(piece)
            if (parsed["key"] = "")
                continue
            try {
                HK_Scope(parsed["window"])
                Hotkey(parsed["key"], HK_Wrap(HK_Actions()[name]), "On")
                HK_Registered[parsed["window"] "`n" parsed["key"]] := parsed
            } catch Error as err {
                problems .= "`n  " HK_Labels()[name] "  ->  " Trim(piece)
                         . "   (" err.Message ")"
            }
        }
    }
    HotIf()
    return problems
}

; "MButton@ahk_exe CafeTran.exe" -> {key, window}
HK_ParseBinding(piece) {
    piece := Trim(piece)
    if !InStr(piece, "@")
        return Map("key", piece, "window", "")
    bits := StrSplit(piece, "@", , 2)
    return Map("key", Trim(bits[1]),
               "window", bits.Length > 1 ? Trim(bits[2]) : "")
}

; Aim the next Hotkey() call at one window, or at everywhere.
HK_Scope(window) {
    if (window = "")
        HotIf()
    else
        HotIfWinActive(window)
}

RegisterConfiguredHotkeys() {
    problems := HK_Apply(HK_Load())
    if (problems != "")
        MsgBox("These shortcuts could not be registered:" problems
               "`n`nOpen the menu and choose “Keyboard shortcuts…” to fix "
               "them. The rest of Supervertaler Sidekick is running normally.",
               "Supervertaler Sidekick", "Icon!")
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

    out := ""
    for piece in StrSplit(binding, "|") {
        p := HK_ParseBinding(piece)
        if (p["key"] = "")
            continue
        shown := HK_DisplayKey(p["key"])
        if (p["window"] != "")
            shown .= " in " HK_WindowName(p["window"])
        out .= (out = "" ? "" : ", ") shown
    }
    return (out = "") ? "(none)" : out
}

; "ahk_exe memoQ.exe" is how AutoHotkey names a window; nobody needs to read
; that in a list of shortcuts.
HK_WindowName(window) {
    n := RegExReplace(window, "^ahk_(exe|class)\s+", "")
    return RegExReplace(n, "\.exe$", "")
}

HK_DisplayKey(binding) {
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
    ; A send-string names its keys in braces — ^{Enter}. Fine to send, not
    ; to read, and these strings are now shown to people.
    if (SubStr(key, 1, 1) = "{" && SubStr(key, -1) = "}")
        key := SubStr(key, 2, StrLen(key) - 2)
    if (key = Chr(96))
        key := "` (backtick)"
    else if (StrLen(key) = 1)
        key := StrUpper(key)
    else {
        for pair in [["MButton", "Middle click"], ["XButton1", "Mouse 4"],
                     ["XButton2", "Mouse 5"], ["NumpadEnter", "Numpad Enter"],
                     ["NumpadAdd", "Numpad +"], ["NumpadSub", "Numpad -"]] {
            if (key = pair[1])
                key := pair[2]
        }
    }

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
global HKE_Gui   := ""
global HKE_List  := ""
global HKE_Work  := ""      ; working copy of the built-in bindings
global HKE_Mine  := []      ; working copy of the user's own shortcuts
global HKE_Rows  := []      ; what each list row is, in row order

OpenHotkeyEditor(*) {
    global HKE_Gui, HKE_List, HKE_Work, HKE_Mine

    if (HKE_Gui != "") {
        HKE_Gui.Show()
        return
    }

    HKE_Work := HK_Load()
    HKE_Mine := SC_Load()

    HKE_Gui := Gui("+Resize +MinSize640x420",
                   "Supervertaler Sidekick — Keyboard shortcuts")
    HKE_Gui.SetFont("s9", "Segoe UI")
    HKE_Gui.OnEvent("Close", HKE_Close)
    HKE_Gui.OnEvent("Escape", HKE_Close)

    HKE_Gui.Add("Text", "xm ym w720",
                "A shortcut is a key to press and something for it to do. "
                "Both are shown below. The built-in ones lend their key to a "
                "part of the program, so only the key can change; the ones "
                "you make yourself can do anything the menu can.")

    HKE_List := HKE_Gui.Add("ListView", "xm y+10 w720 h300",
                            ["Action", "Does", "Shortcut"])
    HKE_List.OnEvent("DoubleClick", (*) => HKE_Change())

    HKE_Gui.Add("Button", "xm y+10 w130", "Change key…")
        .OnEvent("Click", (*) => HKE_Change())
    HKE_Gui.Add("Button", "x+6 w90", "Turn off")
        .OnEvent("Click", (*) => HKE_Clear())
    HKE_Gui.Add("Button", "x+6 w120", "Reset to default")
        .OnEvent("Click", (*) => HKE_ResetOne())

    HKE_Gui.Add("Button", "xm y+6 w130", "New shortcut…")
        .OnEvent("Click", (*) => HKE_New())
    HKE_Gui.Add("Button", "x+6 w90", "Edit…")
        .OnEvent("Click", (*) => HKE_EditItem())
    HKE_Gui.Add("Button", "x+6 w120", "Delete")
        .OnEvent("Click", (*) => HKE_DeleteItem())
    HKE_Gui.Add("Button", "x+130 yp w90 Default", "Save")
        .OnEvent("Click", (*) => HKE_Save())
    HKE_Gui.Add("Button", "x+6 w70", "Close")
        .OnEvent("Click", (*) => HKE_Close())

    HKE_Refresh()
    HKE_Gui.Show("w760 h470")
}

; Rows are the built-ins first, then a heading, then the user's own, and
; HKE_Rows records which is which so every button knows what it is acting on.
HKE_Refresh() {
    global HKE_List, HKE_Work, HKE_Mine, HKE_Rows, HK_ORDER

    HKE_List.Opt("-Redraw")
    HKE_List.Delete()
    HKE_Rows := []

    for name in HK_ORDER {
        HKE_List.Add(, HK_Labels()[name], HK_Does()[name],
                     HK_Display(HKE_Work[name]))
        HKE_Rows.Push(Map("type", "builtin", "name", name))
    }

    HKE_List.Add(, "— your own shortcuts —", "", "")
    HKE_Rows.Push(Map("type", "heading"))

    for i, item in HKE_Mine {
        HKE_List.Add(, item["label"], SC_Describe(item),
                     HK_Display(item["key"]))
        HKE_Rows.Push(Map("type", "mine", "index", i))
    }

    if (HKE_Mine.Length = 0) {
        HKE_List.Add(, "(none yet — press New shortcut…)", "", "")
        HKE_Rows.Push(Map("type", "heading"))
    }

    HKE_List.ModifyCol(1, 250)
    HKE_List.ModifyCol(2, 280)
    HKE_List.ModifyCol(3, 165)
    HKE_List.Opt("+Redraw")
}

HKE_SelectedRow() {
    global HKE_List, HKE_Rows
    row := HKE_List.GetNext(0)
    if (row < 1 || row > HKE_Rows.Length) {
        MsgBox("Select a shortcut first.", "Keyboard shortcuts", "Icon!")
        return ""
    }
    if (HKE_Rows[row]["type"] = "heading")
        return ""
    return HKE_Rows[row]
}

; ---------------------------------------------------------------------------
; The key half
; ---------------------------------------------------------------------------
HKE_Change() {
    global HKE_Gui, HKE_Work, HKE_Mine

    sel := HKE_SelectedRow()
    if (sel = "")
        return

    current := (sel["type"] = "builtin")
        ? HKE_Work[sel["name"]]
        : HKE_Mine[sel["index"]]["key"]

    ; Capturing one keystroke can only produce one unscoped key, so it would
    ; quietly throw away a binding naming several, or limited to one
    ; application. Say so before doing it.
    if (InStr(current, "|") || InStr(current, "@")) {
        if (MsgBox("That shortcut is currently:`n`n  " HK_Display(current)
                 . "`n`nCapturing a new key replaces all of it with the "
                 . "single key you press. To keep more than one, or to limit "
                 . "a key to one application, edit the Hotkeys section of "
                 . "settings.ini instead.`n`nReplace it?",
                   "Supervertaler Sidekick", "YesNo Icon?") != "Yes")
            return
    }

    binding := HK_Capture(HKE_Gui.Hwnd)
    if (binding = "") {
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
             . HK_Display(binding) "`n`n" err.Message,
               "Keyboard shortcuts", "Icon!")
        return
    }

    if (sel["type"] = "builtin")
        HKE_Work[sel["name"]] := binding
    else
        HKE_Mine[sel["index"]]["key"] := binding
    HKE_Refresh()
}

HKE_Clear() {
    global HKE_Work, HKE_Mine
    sel := HKE_SelectedRow()
    if (sel = "")
        return
    if (sel["type"] = "builtin")
        HKE_Work[sel["name"]] := ""
    else
        HKE_Mine[sel["index"]]["key"] := ""
    HKE_Refresh()
}

HKE_ResetOne() {
    global HKE_Work
    sel := HKE_SelectedRow()
    if (sel = "")
        return
    if (sel["type"] != "builtin") {
        MsgBox("Only the built-in shortcuts have a default to go back to.",
               "Keyboard shortcuts", "Icon!")
        return
    }
    HKE_Work[sel["name"]] := HK_Defaults()[sel["name"]]
    HKE_Refresh()
}

; ---------------------------------------------------------------------------
; The other half
; ---------------------------------------------------------------------------
HKE_New() {
    global HKE_Mine
    item := HKE_ItemDialog(Map("label", "", "key", "", "kind", "keys",
                               "value", "", "url", "", "func", "",
                               "before", "", "after", ""))
    if (item = "")
        return
    HKE_Mine.Push(item)
    HKE_Refresh()
}

HKE_EditItem() {
    global HKE_Mine
    sel := HKE_SelectedRow()
    if (sel = "")
        return
    if (sel["type"] = "builtin") {
        MsgBox("What a built-in shortcut does is part of the program, so it "
             . "cannot be changed here — only the key it answers to."
             . "`n`nTo make one that does something of your own, press "
             . "New shortcut.", "Keyboard shortcuts", "Icon!")
        return
    }
    item := HKE_ItemDialog(HKE_Mine[sel["index"]])
    if (item = "")
        return
    HKE_Mine[sel["index"]] := item
    HKE_Refresh()
}

HKE_DeleteItem() {
    global HKE_Mine
    sel := HKE_SelectedRow()
    if (sel = "")
        return
    if (sel["type"] = "builtin") {
        MsgBox("A built-in shortcut cannot be deleted. Press Turn off to "
             . "free up its key.", "Keyboard shortcuts", "Icon!")
        return
    }
    if (MsgBox("Delete " HKE_Mine[sel["index"]]["label"] "?",
               "Keyboard shortcuts", "YesNo Icon?") != "Yes")
        return
    HKE_Mine.RemoveAt(sel["index"])
    HKE_Refresh()
}

; One shortcut: what to call it, what it does, and what to press.
; Returns a Map, or "" if cancelled.
HKE_ItemDialog(item) {
    global HKE_Gui
    result := ""
    captured := GetKey(item, "key", "")

    g := Gui("+Owner" HKE_Gui.Hwnd " -MinimizeBox",
             "Supervertaler Sidekick — Shortcut")
    g.SetFont("s9", "Segoe UI")

    g.Add("Text", "xm ym w110", "Call it:")
    nameBox := g.Add("Edit", "x+6 yp-3 w360", item["label"])

    g.Add("Text", "xm y+12 w110", "What it does:")
    kinds := []
    chosen := 1
    for i, k in SC_Kinds() {
        kinds.Push(k["label"])
        if (k["kind"] = item["kind"])
            chosen := i
    }
    kindBox := g.Add("DropDownList", "x+6 yp-3 w360 Choose" chosen, kinds)
    kindBox.OnEvent("Change", (*) => Relabel())

    lbl1 := g.Add("Text", "xm y+12 w110", "With:")
    box1 := g.Add("Edit", "x+6 yp-3 w360", "")
    lbl2 := g.Add("Text", "xm y+10 w110", "And:")
    box2 := g.Add("Edit", "x+6 yp-3 w360", "")

    hint := g.Add("Text", "xm y+10 w470 cGray", "")

    g.Add("Text", "xm y+14 w110", "Key:")
    keyBox := g.Add("Text", "x+6 yp w250", HK_Display(captured))
    g.Add("Button", "x+6 yp-4 w100 h24", "Press a key…")
        .OnEvent("Click", (*) => Capture())

    g.Add("Button", "xm y+18 w100 h26 Default", "OK")
        .OnEvent("Click", (*) => Done(true))
    g.Add("Button", "x+6 yp w100 h26", "Cancel")
        .OnEvent("Click", (*) => Done(false))
    g.OnEvent("Close", (*) => Done(false))
    g.OnEvent("Escape", (*) => Done(false))

    CurrentKind() {
        return SC_Kinds()[kindBox.Value]["kind"]
    }

    ; The two value boxes mean different things per kind, so they are
    ; relabelled rather than left as "value 1" and "value 2".
    Relabel() {
        kind := CurrentKind()
        switch kind {
            case "keys":
                lbl1.Value := "Keys to press:"
                hint.Value := "AutoHotkey syntax: ^ is Ctrl, ! is Alt, "
                            . "+ is Shift. Ctrl+Enter is ^{Enter}."
            case "text":
                lbl1.Value := "Text to type:"
                hint.Value := ""
            case "wrap":
                lbl1.Value := "Put before:"
                hint.Value := "The selection is copied, wrapped and pasted "
                            . "back."
            case "search":
                lbl1.Value := "Address:"
                hint.Value := "Put {q} where the selection goes, e.g. "
                            . "https://www.google.com/search?q={q}"
            case "url":
                lbl1.Value := "Address:"
                hint.Value := ""
            case "run":
                lbl1.Value := "Program:"
                hint.Value := ""
            case "action":
                lbl1.Value := "Action name:"
                hint.Value := "The name of a built-in action, as used in "
                            . "menu.json."
        }
        second := (kind = "wrap")
        lbl2.Visible := second
        box2.Visible := second
        if second
            lbl2.Value := "Put after:"
    }

    Fill() {
        kind := CurrentKind()
        switch kind {
            case "wrap":
                box1.Value := GetKey(item, "before", "")
                box2.Value := GetKey(item, "after", "")
            case "search":
                box1.Value := GetKey(item, "url", "")
            case "action":
                box1.Value := GetKey(item, "func", "")
            default:
                box1.Value := GetKey(item, "value", "")
        }
    }

    Capture() {
        b := HK_Capture(g.Hwnd)
        if (b = "")
            return
        captured := b
        keyBox.Value := HK_Display(b)
    }

    Done(ok) {
        if ok {
            label := Trim(nameBox.Value)
            if (label = "") {
                MsgBox("Give it a name.", "Supervertaler Sidekick", "Icon!")
                return
            }
            kind := CurrentKind()
            out := Map("label", label, "key", Trim(captured), "kind", kind,
                       "value", "", "url", "", "func", "",
                       "before", "", "after", "")
            switch kind {
                case "wrap":
                    out["before"] := box1.Value
                    out["after"]  := box2.Value
                case "search":
                    out["url"] := Trim(box1.Value)
                case "action":
                    out["func"] := Trim(box1.Value)
                default:
                    out["value"] := box1.Value
            }
            result := out
        }
        g.Destroy()
    }

    Relabel()
    Fill()
    g.Show()
    WinWaitClose("ahk_id " g.Hwnd)
    return result
}

; ---------------------------------------------------------------------------
HKE_Save() {
    global HKE_Work, HKE_Mine

    if !HK_SaveToIni(HKE_Work)
        return
    try
        SC_SaveItems(HKE_Mine)
    catch Error as err {
        MsgBox("Could not save your shortcuts:`n`n" err.Message,
               "Keyboard shortcuts", "Icon!")
        return
    }

    problems := HK_Apply(HKE_Work) . SC_Apply(HKE_Mine)
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
