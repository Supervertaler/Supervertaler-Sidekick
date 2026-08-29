#Requires AutoHotkey v2.0
; ===========================================================================
; lib/palette.ahk — one searchable window over everything.
;
; The menu and the clipboard window were doing the same job through two
; different doors: present a list of text-ish things, let the user pick one,
; put the result where they were working. The menu was good at browsing and
; useless at finding; the clipboard window was the reverse.
;
; This is both. Type and it filters across clipboard history, snippets,
; searches, AI prompts, bookmarks and conversions at once. The menu stays —
; it is still the better way to browse a category you cannot name yet.
;
; The selection is captured when the window OPENS, not when you hit Enter,
; because by then focus has moved here and the original selection is out of
; reach. The clipboard is put back exactly as it was.
; ===========================================================================

global PAL_Gui       := ""
global PAL_Search    := ""
global PAL_List      := ""
global PAL_Status    := ""
global PAL_Items     := []    ; every candidate, rebuilt on open
global PAL_Shown     := []    ; the filtered subset, in row order
global PAL_Selection := ""    ; text selected when the window opened
global PAL_Source    := 0     ; window to return to

PAL_MAX_ROWS := 300           ; cap the list so a huge history stays responsive

; ---------------------------------------------------------------------------
PAL_Show(*) {
    global PAL_Gui, PAL_Source, PAL_Selection, PAL_Search

    try PAL_Source := WinGetID("A")
    catch
        PAL_Source := 0

    ; Not captured on open — see the note in MW_Show. Clearing the clipboard
    ; and waiting for a Ctrl+C that never comes cost ~400ms every time.
    PAL_Selection := ""

    PAL_BuildIndex()

    if (PAL_Gui = "")
        PAL_BuildGui()

    try PAL_Search.Value := ""
    PAL_Refresh()
    PAL_Gui.Show()
    try PAL_Search.Focus()
}

; Copy whatever is selected without disturbing the user's clipboard or
; polluting the clipboard history with our own read.
PAL_CaptureSelection() {
    global CB_Suppress

    saved := ""
    try saved := ClipboardAll()

    CB_Suppress++
    A_Clipboard := ""
    Send("^c")
    got := ClipWait(0.4, 0) ? A_Clipboard : ""

    ; Restoring also fires OnClipboardChange, so suppress that too.
    if (saved != "") {
        CB_Suppress++
        try A_Clipboard := saved
    }
    return Trim(got)
}

; ---------------------------------------------------------------------------
; Index
;
; Menu entries and clipboard clips are flattened into one list of candidates.
; Each carries the breadcrumb it came from, so "Dictionaries > Kramers" is
; findable by typing either half.
; ---------------------------------------------------------------------------
PAL_BuildIndex() {
    global PAL_Items, SidekickData, CB_Items
    PAL_Items := []

    PAL_AddMenuItems(SidekickData["menu"], "")

    for clip in CB_Items {
        text := GetKey(clip, "text", "")
        if (text = "")
            continue
        PAL_Items.Push(Map(
            "source", "clip",
            "label",  CB_Preview(text),
            "path",   "Clipboard",
            "detail", CB_FormatTime(GetKey(clip, "time", "")),
            "kind",   "clip",
            "clip",   clip
        ))
    }
}

PAL_AddMenuItems(items, path) {
    global PAL_Items

    for item in items {
        kind := GetKey(item, "kind", "")

        if (kind = "separator" || kind = "heading" || kind = "clipboard")
            continue

        label := GetKey(item, "label", "")

        if (kind = "submenu") {
            child := path = "" ? label : path " > " label
            PAL_AddMenuItems(GetKey(item, "items", []), PAL_Tidy(child))
            continue
        }

        detail := GetKey(item, "value", "")
        if (detail = "")
            detail := GetKey(item, "url", "")
        if (detail = "")
            detail := GetKey(item, "prompt", "")
        if (detail = "")
            detail := GetKey(item, "func", "")

        PAL_Items.Push(Map(
            "source", "menu",
            "label",  PAL_Tidy(label),
            "path",   path = "" ? "Menu" : path,
            "detail", CB_Preview(detail),
            "kind",   kind,
            "item",   item
        ))
    }
}

; Menu labels carry bullets, ampersand accelerators and trailing colons that
; only make sense in a menu; they would just get in the way of matching.
PAL_Tidy(label) {
    t := StrReplace(label, "•", "")
    t := StrReplace(t, "🔊", "")
    t := Trim(t)
    t := RegExReplace(t, "[:：]\s*$", "")
    return Trim(t)
}

; ---------------------------------------------------------------------------
; Filtering
;
; Scored rather than plain substring, so typing "iate" puts the IATE searches
; above a snippet that merely mentions the word somewhere in its body.
; ---------------------------------------------------------------------------
PAL_Score(cand, needle) {
    if (needle = "")
        return 1

    label := cand["label"]
    path  := cand["path"]

    lpos := InStr(label, needle, false)
    if (lpos = 1)
        return 100                      ; label starts with the query
    if (lpos)
        return SubStr(label, lpos - 1, 1) = " " ? 80 : 60

    if InStr(path, needle, false)
        return 40                       ; matched the category name

    if InStr(cand["detail"], needle, false)
        return 20                       ; matched the body text

    return 0
}

PAL_Refresh() {
    global PAL_List, PAL_Items, PAL_Shown, PAL_Search, PAL_Status, PAL_MAX_ROWS

    needle := ""
    try needle := Trim(PAL_Search.Value)

    scored := []
    for cand in PAL_Items {
        s := PAL_Score(cand, needle)
        if (s > 0)
            scored.Push(Map("score", s, "cand", cand))
    }

    ; Stable-ish ordering: best score first, original order within a score.
    ; A simple insertion sort is plenty for a few hundred rows and keeps ties
    ; in index order, which matters — clips are newest-first already.
    n := scored.Length
    i := 2
    while (i <= n) {
        cur := scored[i]
        j := i - 1
        while (j >= 1 && scored[j]["score"] < cur["score"]) {
            scored[j + 1] := scored[j]
            j--
        }
        scored[j + 1] := cur
        i++
    }

    PAL_List.Opt("-Redraw")
    PAL_List.Delete()
    PAL_Shown := []

    for row in scored {
        if (PAL_Shown.Length >= PAL_MAX_ROWS)
            break
        c := row["cand"]
        PAL_List.Add(, PAL_KindLabel(c), c["label"], c["path"], c["detail"])
        PAL_Shown.Push(c)
    }

    PAL_List.ModifyCol(1, 74)
    PAL_List.ModifyCol(2, 300)
    PAL_List.ModifyCol(3, 150)
    PAL_List.ModifyCol(4, 240)
    PAL_List.Opt("+Redraw")

    if (PAL_Shown.Length > 0)
        PAL_List.Modify(1, "Select Focus")

    capped := ""
    if (PAL_Shown.Length >= PAL_MAX_ROWS)
        capped := " (showing first " PAL_MAX_ROWS ")"

    try PAL_Status.Value := PAL_Shown.Length " of " PAL_Items.Length capped
                          . "   ·   ↑↓ choose  ·  Enter run  ·  Esc close"
}

PAL_KindLabel(c) {
    switch c["kind"] {
        case "clip":   return "clip"
        case "text":   return "snippet"
        case "keys":   return "keys"
        case "search": return "search"
        case "ai":     return "AI"
        case "url":    return "bookmark"
        case "run":    return "launch"
        case "action": return "action"
        default:       return c["kind"]
    }
}

; ---------------------------------------------------------------------------
PAL_BuildGui() {
    global PAL_Gui, PAL_Search, PAL_List, PAL_Status

    PAL_Gui := Gui("+Resize +MinSize640x380", "Supervertaler Sidekick")
    PAL_Gui.SetFont("s10", "Segoe UI")
    PAL_Gui.OnEvent("Close", PAL_Hide)
    PAL_Gui.OnEvent("Escape", PAL_Hide)
    PAL_Gui.OnEvent("Size", PAL_OnSize)

    PAL_Search := PAL_Gui.Add("Edit", "xm ym w780")
    PAL_Search.OnEvent("Change", (*) => PAL_Refresh())

    PAL_Gui.SetFont("s9")
    PAL_List := PAL_Gui.Add("ListView", "xm y+8 w780 h420",
                            ["Type", "Name", "Where", "Detail"])
    PAL_List.OnEvent("DoubleClick", (*) => PAL_RunSelected())

    PAL_Status := PAL_Gui.Add("Text", "xm y+8 w780", "")

    PAL_Keys()
}

PAL_Keys() {
    global PAL_Gui
    HotIfWinActive("ahk_id " PAL_Gui.Hwnd)

    Hotkey("Down",        (*) => PAL_Move(1),   "On")
    Hotkey("Up",          (*) => PAL_Move(-1),  "On")
    Hotkey("PgDn",        (*) => PAL_Move(10),  "On")
    Hotkey("PgUp",        (*) => PAL_Move(-10), "On")
    Hotkey("Enter",       (*) => PAL_RunSelected(), "On")
    Hotkey("NumpadEnter", (*) => PAL_RunSelected(), "On")

    HotIfWinActive()
}

PAL_Move(delta) {
    global PAL_List, PAL_Shown
    if (PAL_Shown.Length = 0)
        return
    row := PAL_List.GetNext(0)
    if (row = 0)
        row := (delta > 0) ? 0 : PAL_Shown.Length + 1
    target := row + delta
    if (target < 1)
        target := 1
    if (target > PAL_Shown.Length)
        target := PAL_Shown.Length
    PAL_List.Modify(0, "-Select")
    PAL_List.Modify(target, "Select Focus Vis")
}

; ---------------------------------------------------------------------------
PAL_RunSelected() {
    global PAL_List, PAL_Shown, PAL_Selection, PAL_Source

    row := PAL_List.GetNext(0)
    if (row = 0 || row > PAL_Shown.Length)
        return
    cand := PAL_Shown[row]

    PAL_Hide()

    ; Everything that puts text back needs the original window in front.
    if (PAL_Source && WinExist("ahk_id " PAL_Source)) {
        try {
            WinActivate("ahk_id " PAL_Source)
            WinWaitActive("ahk_id " PAL_Source, , 1)
        }
    }
    Sleep(80)

    if (cand["source"] = "clip") {
        clip := cand["clip"]
        clip["pasted"] := true
        CB_Save()
        CB_SetClipboard(GetKey(clip, "text", ""))
        Send("^v")
        return
    }

    ExecuteEntry(cand["item"], PAL_Selection)
}

PAL_Hide(*) {
    global PAL_Gui
    try PAL_Gui.Hide()
    return true
}

PAL_OnSize(thisGui, minMax, width, height) {
    global PAL_Search, PAL_List, PAL_Status
    if (minMax = -1)
        return
    w := width - 24
    h := height - 110
    if (h < 120)
        h := 120
    try {
        PAL_Search.Move(, , w)
        PAL_List.Move(, , w, h)
        PAL_List.ModifyCol(4, w - 540)
        PAL_Status.Move(, , w)
    }
}
