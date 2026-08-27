#Requires AutoHotkey v2.0
; ===========================================================================
; lib/clipboard.ahk — persistent clipboard history.
;
; Watches the clipboard, keeps a searchable history that survives restarts,
; and pastes any entry back into whatever window you came from.
;
; Text only. Image clips were left out deliberately: AutoHotkey has no
; workable way to thumbnail and persist them, and for translation work the
; history that matters is text. The on-disk format leaves room to add them.
;
; Privacy (borrowed from the Supervertaler Workbench's clipboard tab, which
; got this right): capture can be paused, entries can expire on a timer, and
; copies made while a password manager is in the foreground are never
; recorded at all.
; ===========================================================================

global CB_Items      := []      ; newest first
global CB_Suppress   := 0       ; >0 while we write to the clipboard ourselves
global CB_Source     := 0       ; window to paste back into
global CB_Gui        := ""
global CB_List       := ""
global CB_Search     := ""
global CB_StatusText := ""
global CB_Enabled    := true
global CB_Loaded     := false
global CB_Shown      := []      ; entries currently visible, in row order

; Offered as a starting point for the exclusion list. Not a default: someone
; who copies a URL out of their password manager and finds it missing would
; rightly call that broken, so this is opt-in.
CB_COMMON_SECRET_APPS := "keepass.exe|keepassxc.exe|1password.exe|"
                       . "bitwarden.exe|dashlane.exe|lastpass.exe|"
                       . "nordpass.exe|protonpass.exe|enpass.exe|keeper.exe"

CB_MAX_PREVIEW := 200           ; characters shown in the list
CB_MAX_CLIP    := 100000        ; refuse to store anything larger

; ---------------------------------------------------------------------------
; Settings (settings.ini, [Clipboard])
; ---------------------------------------------------------------------------
CB_Setting(key, default) {
    return AI_Ini(SettingsFile(), "Clipboard", key, default)
}

CB_MaxItems() {
    n := CB_Setting("MaxItems", "200") + 0
    return (n > 0) ? n : 200
}

CB_AutoDeleteMinutes() {
    return CB_Setting("AutoDeleteMinutes", "0") + 0
}

CB_ExcludedApps() {
    return CB_Setting("ExcludedApps", "")
}

; ---------------------------------------------------------------------------
CB_Init() {
    global CB_Enabled
    CB_Load()
    CB_Enabled := (CB_Setting("Enabled", "1") != "0")
    OnClipboardChange(CB_OnChange, 1)
    if (CB_AutoDeleteMinutes() > 0)
        SetTimer(CB_PurgeExpired, 60000)
}

; ---------------------------------------------------------------------------
; Capture
; ---------------------------------------------------------------------------
CB_OnChange(dataType) {
    global CB_Suppress, CB_Enabled, CB_Items

    ; Ignore the change we caused ourselves by pasting an entry back.
    if (CB_Suppress > 0) {
        CB_Suppress--
        return
    }

    if (!CB_Enabled || dataType != 1)      ; 1 = text
        return

    if CB_ForegroundExcluded()
        return

    text := ""
    try text := A_Clipboard
    catch
        return

    if (text = "" || StrLen(text) > CB_MAX_CLIP)
        return
    if (Trim(text) = "")
        return

    ; A re-copy of the same thing moves it to the top rather than duplicating.
    for i, item in CB_Items {
        if (GetKey(item, "text", "") == text) {
            CB_Items.RemoveAt(i)
            break
        }
    }

    entry := Map()
    entry["text"]   := text
    entry["time"]   := A_Now
    entry["pasted"] := false
    CB_Items.InsertAt(1, entry)

    limit := CB_MaxItems()
    while (CB_Items.Length > limit)
        CB_Items.Pop()

    CB_Save()
    if (CB_Gui != "")
        CB_Refresh()
}

; True when the window that owns the copy is on the exclusion list.
CB_ForegroundExcluded() {
    list := CB_ExcludedApps()
    if (list = "")
        return false
    proc := ""
    try proc := WinGetProcessName("A")
    catch
        return false
    if (proc = "")
        return false
    for name in StrSplit(list, "|") {
        name := Trim(name)
        if (name != "" && (proc = name))
            return true
    }
    return false
}

CB_PurgeExpired() {
    global CB_Items
    minutes := CB_AutoDeleteMinutes()
    if (minutes <= 0)
        return

    cutoff := DateAdd(A_Now, -minutes, "Minutes")
    changed := false
    i := CB_Items.Length
    while (i >= 1) {
        stamp := GetKey(CB_Items[i], "time", "")
        if (stamp != "" && stamp < cutoff) {
            CB_Items.RemoveAt(i)
            changed := true
        }
        i--
    }
    if (changed) {
        CB_Save()
        if (CB_Gui != "")
            CB_Refresh()
    }
}

; ---------------------------------------------------------------------------
; Persistence
; ---------------------------------------------------------------------------
CB_File() {
    return DataFile("clipboard.json")
}

CB_Load() {
    global CB_Items, CB_Loaded
    CB_Items := []
    data := LoadJsonFile(CB_File())
    if (data is Map && data.Has("items")) {
        for item in data["items"] {
            if (item is Map && GetKey(item, "text", "") != "")
                CB_Items.Push(item)
        }
    }
    CB_Loaded := true
}

CB_Save() {
    data := Map()
    data["version"] := 1
    data["items"] := CB_Items
    SaveJsonFile(CB_File(), data)
}

; ---------------------------------------------------------------------------
; Window
; ---------------------------------------------------------------------------
CB_Show(*) {
    global CB_Gui, CB_Source, CB_Search

    ; Remember where we came from so an entry can be pasted straight back.
    try CB_Source := WinGetID("A")
    catch
        CB_Source := 0

    if (CB_Gui != "") {
        CB_Refresh()
        CB_Gui.Show()
        try CB_Search.Focus()
        return
    }

    CB_BuildGui()
    CB_Refresh()
    CB_Gui.Show("w720 h520")
    try CB_Search.Focus()
}

CB_BuildGui() {
    global CB_Gui, CB_List, CB_Search, CB_StatusText

    CB_Gui := Gui("+Resize +MinSize560x360", "Beijer.bot — Clipboard")
    CB_Gui.SetFont("s9", "Segoe UI")
    CB_Gui.OnEvent("Close", CB_Hide)
    CB_Gui.OnEvent("Escape", CB_Hide)
    CB_Gui.OnEvent("Size", CB_OnSize)

    CB_Gui.Add("Text", "xm ym", "Search:")
    CB_Search := CB_Gui.Add("Edit", "x+6 yp-3 w560")
    CB_Search.OnEvent("Change", (*) => CB_Refresh())

    CB_List := CB_Gui.Add("ListView", "xm y+8 w690 h380",
                          ["", "When", "Text"])
    CB_List.OnEvent("DoubleClick", (*) => CB_PasteSelected())

    ; Grey out entries that have already been pasted. NM_CUSTOMDRAW is the
    ; only way to colour individual ListView rows; if it fails for any reason
    ; the rows simply stay black and the tick column still marks them.
    try CB_List.OnNotify(-12, CB_CustomDraw)

    CB_Gui.Add("Button", "xm y+8 w120 Default", "Paste")
        .OnEvent("Click", (*) => CB_PasteSelected())
    CB_Gui.Add("Button", "x+6 w110", "Copy")
        .OnEvent("Click", (*) => CB_CopySelected())
    CB_Gui.Add("Button", "x+6 w130", "Save as snippet")
        .OnEvent("Click", (*) => CB_SaveAsSnippet())
    CB_Gui.Add("Button", "x+6 w90", "Delete")
        .OnEvent("Click", (*) => CB_DeleteSelected())
    CB_Gui.Add("Button", "x+6 w100", "Clear all")
        .OnEvent("Click", (*) => CB_ClearAll())
    CB_Gui.Add("Button", "x+6 w110", "Reset marks")
        .OnEvent("Click", (*) => CB_ResetMarks())

    CB_StatusText := CB_Gui.Add("Text", "xm y+8 w690", "")

    CB_Keys()
}

; ---------------------------------------------------------------------------
; Keyboard navigation.
;
; Focus stays in the search box the whole time: you type to narrow the list
; and arrow through it without ever reaching for the mouse or tabbing away.
; The arrows are therefore intercepted at window level rather than left to
; the ListView, which would only work while the list itself had focus.
; ---------------------------------------------------------------------------
CB_Keys() {
    global CB_Gui
    HotIfWinActive("ahk_id " CB_Gui.Hwnd)

    Hotkey("Down",        (*) => CB_MoveSelection(1),  "On")
    Hotkey("Up",          (*) => CB_MoveSelection(-1), "On")
    Hotkey("PgDn",        (*) => CB_MoveSelection(10), "On")
    Hotkey("PgUp",        (*) => CB_MoveSelection(-10), "On")
    Hotkey("Home",        (*) => CB_MoveTo(1), "On")
    Hotkey("End",         (*) => CB_MoveTo(-1), "On")
    Hotkey("Enter",       (*) => CB_PasteSelected(), "On")
    Hotkey("NumpadEnter", (*) => CB_PasteSelected(), "On")
    Hotkey("^Enter",      (*) => CB_CopySelected(), "On")
    Hotkey("^Delete",     (*) => CB_DeleteSelected(), "On")

    ; Alt+1..9 pastes the nth visible entry outright.
    Loop 9 {
        n := A_Index
        Hotkey("!" n, CB_MakeQuickPaste(n), "On")
    }

    HotIfWinActive()
}

CB_MakeQuickPaste(n) {
    return (*) => CB_QuickPaste(n)
}

CB_QuickPaste(n) {
    global CB_List, CB_Shown
    if (n < 1 || n > CB_Shown.Length)
        return
    CB_List.Modify(0, "-Select")
    CB_List.Modify(n, "Select Focus")
    CB_PasteSelected()
}

CB_MoveSelection(delta) {
    global CB_List, CB_Shown
    if (CB_Shown.Length = 0)
        return

    row := CB_List.GetNext(0)
    if (row = 0)
        row := (delta > 0) ? 0 : CB_Shown.Length + 1

    target := row + delta
    if (target < 1)
        target := 1
    if (target > CB_Shown.Length)
        target := CB_Shown.Length

    CB_List.Modify(0, "-Select")
    CB_List.Modify(target, "Select Focus Vis")
}

CB_MoveTo(where) {
    global CB_List, CB_Shown
    if (CB_Shown.Length = 0)
        return
    target := (where = 1) ? 1 : CB_Shown.Length
    CB_List.Modify(0, "-Select")
    CB_List.Modify(target, "Select Focus Vis")
}

CB_Refresh() {
    global CB_List, CB_Items, CB_Search, CB_StatusText, CB_Enabled, CB_Shown

    filter := ""
    try filter := CB_Search.Value

    CB_List.Opt("-Redraw")
    CB_List.Delete()
    CB_Shown := []

    pastedCount := 0
    for item in CB_Items {
        text := GetKey(item, "text", "")
        if (filter != "" && !InStr(text, filter, false))
            continue
        isPasted := GetKey(item, "pasted", false)
        if (isPasted)
            pastedCount++
        CB_List.Add(, isPasted ? "✓" : "",
                      CB_FormatTime(GetKey(item, "time", "")),
                      CB_Preview(text))
        CB_Shown.Push(item)
    }

    CB_List.ModifyCol(1, 26)
    CB_List.ModifyCol(2, 110)
    CB_List.ModifyCol(3, 530)
    CB_List.Opt("+Redraw")

    ; Preselect the top entry so Enter works the moment the window opens,
    ; without the user having to arrow into the list first.
    ; "Focus" here sets the focused *item* within the list, not keyboard focus,
    ; so the caret stays in the search box and typing keeps narrowing.
    if (CB_Shown.Length > 0)
        CB_List.Modify(1, "Select Focus")

    state := CB_Enabled ? "" : "   —   capture is PAUSED"
    try CB_StatusText.Value := CB_Shown.Length " of " CB_Items.Length
                             . " entries   ·   " pastedCount " already pasted"
                             . state
                             . "        ↑↓ choose   ·   Enter paste   ·   "
                             . "Alt+1-9 paste nth   ·   Ctrl+Enter copy   ·   "
                             . "Ctrl+Del remove"
}

; Map a visible row back to its entry.
CB_ItemForRow(row) {
    global CB_Shown
    if (row >= 1 && row <= CB_Shown.Length)
        return CB_Shown[row]
    return ""
}

; ---------------------------------------------------------------------------
; Row colouring.
;
; NMLVCUSTOMDRAW on x64: dwDrawStage sits at offset 24, dwItemSpec (the
; zero-based row) at 56, and clrText / clrTextBk at 80 / 84. We answer the
; pre-paint stage asking to be called per item, then recolour pasted rows.
; ---------------------------------------------------------------------------
CB_CustomDraw(ctrl, lParam) {
    global CB_Shown

    static CDDS_PREPAINT          := 0x00000001
    static CDDS_ITEMPREPAINT      := 0x00010001
    static CDRF_NOTIFYITEMDRAW    := 0x00000020
    static CDRF_NEWFONT           := 0x00000002
    static GREY                   := 0xAAAAAA   ; BGR, so a neutral grey

    if (A_PtrSize != 8)
        return

    stage := NumGet(lParam, 24, "UInt")

    if (stage = CDDS_PREPAINT)
        return CDRF_NOTIFYITEMDRAW

    if (stage = CDDS_ITEMPREPAINT) {
        row := NumGet(lParam, 56, "UPtr") + 1        ; dwItemSpec is 0-based
        if (row >= 1 && row <= CB_Shown.Length) {
            if (GetKey(CB_Shown[row], "pasted", false)) {
                NumPut("UInt", GREY, lParam, 80)     ; clrText
                return CDRF_NEWFONT
            }
        }
    }
}

; Forget which entries have been pasted — useful at the start of a new job.
CB_ResetMarks() {
    global CB_Items
    n := 0
    for item in CB_Items {
        if (GetKey(item, "pasted", false)) {
            item["pasted"] := false
            n++
        }
    }
    if (n) {
        CB_Save()
        CB_Refresh()
    }
    try CB_StatusText.Value := "Cleared " n " paste marks."
}

CB_SelectedItem() {
    global CB_List
    row := CB_List.GetNext(0)
    if (row = 0) {
        MsgBox("Select an entry first.", "Clipboard", "Icon! T2")
        return ""
    }
    return CB_ItemForRow(row)
}

CB_Preview(text) {
    t := StrReplace(StrReplace(text, "`r`n", " "), "`n", " ")
    t := StrReplace(t, "`t", " ")
    if (StrLen(t) > CB_MAX_PREVIEW)
        t := SubStr(t, 1, CB_MAX_PREVIEW) "..."
    return t
}

CB_FormatTime(stamp) {
    if (stamp = "")
        return ""
    try {
        if (SubStr(stamp, 1, 8) = SubStr(A_Now, 1, 8))
            return FormatTime(stamp, "HH:mm")
        return FormatTime(stamp, "dd MMM HH:mm")
    } catch
        return ""
}

; ---------------------------------------------------------------------------
; Actions
; ---------------------------------------------------------------------------
CB_SetClipboard(text) {
    global CB_Suppress
    CB_Suppress++          ; don't record our own write as a new clip
    A_Clipboard := text
    ClipWait(1, 0)
}

CB_CopySelected() {
    item := CB_SelectedItem()
    if (item = "")
        return
    CB_SetClipboard(GetKey(item, "text", ""))
    try CB_StatusText.Value := "Copied to clipboard."
}

CB_PasteSelected() {
    global CB_Source
    item := CB_SelectedItem()
    if (item = "")
        return

    text := GetKey(item, "text", "")
    item["pasted"] := true
    CB_Save()

    CB_SetClipboard(text)
    CB_Hide()

    ; Hand focus back to the window the user came from, then paste.
    if (CB_Source && WinExist("ahk_id " CB_Source)) {
        try {
            WinActivate("ahk_id " CB_Source)
            WinWaitActive("ahk_id " CB_Source, , 1)
        }
    }
    Sleep(80)
    Send("^v")
}

CB_DeleteSelected() {
    global CB_Items
    item := CB_SelectedItem()
    if (item = "")
        return
    for i, it in CB_Items {
        if (it == item) {
            CB_Items.RemoveAt(i)
            break
        }
    }
    CB_Save()
    CB_Refresh()
}

CB_ClearAll() {
    global CB_Items
    if (CB_Items.Length = 0)
        return
    if (MsgBox("Delete all " CB_Items.Length " clipboard entries?",
               "Clipboard", "YesNo Icon?") != "Yes")
        return
    CB_Items := []
    CB_Save()
    CB_Refresh()
}

; Promote a clip into the snippet library, so something worth keeping stops
; being history and becomes a menu entry.
CB_SaveAsSnippet() {
    global BeijerBotData
    item := CB_SelectedItem()
    if (item = "")
        return

    text := GetKey(item, "text", "")
    label := CB_Preview(text)
    if (StrLen(label) > 60)
        label := SubStr(label, 1, 60) "..."

    result := InputBox("Label for the new snippet:", "Save as snippet",
                       "w420 h130", label)
    if (result.Result != "OK" || Trim(result.Value) = "")
        return

    target := CB_SnippetContainer()
    entry := Map()
    entry["kind"]  := "text"
    entry["label"] := Trim(result.Value)
    entry["value"] := text
    target.Push(entry)

    if SaveMenuData(BeijerBotData) {
        ReloadBeijerBotMenu()
        try CB_StatusText.Value := "Saved to the snippet library."
    }
}

; Find a sensible submenu to file new snippets under, creating one if the
; data file has no obvious home for them.
CB_SnippetContainer() {
    global BeijerBotData
    for item in BeijerBotData["menu"] {
        if (GetKey(item, "kind", "") = "submenu"
            && InStr(GetKey(item, "label", ""), "Clipboard snippets")) {
            if !item.Has("items")
                item["items"] := []
            return item["items"]
        }
    }
    sub := Map()
    sub["kind"]  := "submenu"
    sub["label"] := "• Clipboard snippets:"
    sub["items"] := []
    BeijerBotData["menu"].InsertAt(3, sub)
    return sub["items"]
}

CB_ToggleCapture(*) {
    global CB_Enabled
    CB_Enabled := !CB_Enabled
    try IniWrite(CB_Enabled ? "1" : "0", SettingsFile(), "Clipboard", "Enabled")
    if (CB_Gui != "")
        CB_Refresh()
    TrayTip("Clipboard capture " (CB_Enabled ? "resumed" : "paused"),
            "Beijer.bot", 1)
}

CB_Hide(*) {
    global CB_Gui
    try CB_Gui.Hide()
    return true
}

; ---------------------------------------------------------------------------
; Recent clips as a live submenu on the main popup.
;
; The main menu is built once at startup, but the history changes constantly,
; so this submenu is emptied and refilled each time the menu is opened.
; ---------------------------------------------------------------------------
global CB_SubMenu := ""

CB_AttachSubMenu(menuObj) {
    global CB_SubMenu
    CB_SubMenu := menuObj
}

CB_RefreshSubMenu() {
    global CB_SubMenu, CB_Items

    if (CB_SubMenu = "")
        return

    try CB_SubMenu.Delete()          ; empty it; a fresh list follows

    shown := CB_Setting("MenuEntries", "12") + 0
    if (shown < 1)
        shown := 12

    if (CB_Items.Length = 0) {
        CB_SubMenu.Add("(clipboard history is empty)", (*) => "")
        CB_SubMenu.Disable("(clipboard history is empty)")
        return
    }

    used := Map()
    count := 0
    for item in CB_Items {
        if (count >= shown)
            break
        count++

        label := CB_Preview(GetKey(item, "text", ""))
        if (StrLen(label) > 70)
            label := SubStr(label, 1, 70) "..."
        if (GetKey(item, "pasted", false))
            label := "✓ " label
        ; Menu items are identified by their text, so near-identical clips
        ; need distinguishing without changing what is displayed.
        label := UniqueMenuLabel(used, label)

        CB_SubMenu.Add(label, CB_MakeMenuPaste(item))
    }

    CB_SubMenu.Add()
    CB_SubMenu.Add("Open clipboard history…  (Ctrl+Alt+C)", (*) => CB_Show())
}

CB_MakeMenuPaste(item) {
    return (*) => CB_PasteItemDirect(item)
}

; Paste straight from the menu. The menu closes on its own, so unlike the
; window there is no source handle to restore — focus returns to whatever was
; underneath.
CB_PasteItemDirect(item) {
    text := GetKey(item, "text", "")
    if (text = "")
        return
    item["pasted"] := true
    CB_Save()
    CB_SetClipboard(text)
    Sleep(120)
    Send("^v")
}

CB_OnSize(thisGui, minMax, width, height) {
    global CB_List, CB_Search, CB_StatusText
    if (minMax = -1)
        return
    w := width - 24
    h := height - 140
    if (h < 100)
        h := 100
    try {
        CB_Search.Move(, , w - 52)
        CB_List.Move(, , w, h)
        CB_List.ModifyCol(3, w - 160)     ; text column takes the slack
        CB_StatusText.Move(, , w)
    }
}
