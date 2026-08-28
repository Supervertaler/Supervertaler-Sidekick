#Requires AutoHotkey v2.0
; ===========================================================================
; lib/mainwindow.ahk — the backtick window: clipboard and menu side by side.
;
; One screen. The clipboard is on the left and has focus when the window
; opens, because that is what gets used most. The menu is on the right as a
; tree you can open and close, because browsing a category you cannot yet
; name is what a tree is good at and a filtered list is bad at.
;
; Right arrow crosses from the clipboard into the menu; left arrow collapses
; a folder, then walks up, then crosses back. Typing filters both sides at
; once — the palette's idea, kept, but now it narrows two panes instead of
; replacing them.
; ===========================================================================

global MW_Gui       := ""
global MW_Search    := ""
global MW_Clips     := ""
global MW_Tree      := ""
global MW_Status    := ""
global MW_ClipHead  := ""
global MW_MenuHead  := ""

global MW_Nodes     := Map()   ; tree item id -> menu entry Map
global MW_Sections  := []      ; top-level heading node ids, in order
global MW_Rebuilding := false  ; true while the tree is being torn down
global MW_Shown     := []      ; clips currently listed, in row order
global MW_Selection := ""      ; text selected when the window opened
global MW_Source    := 0       ; window to paste back into

MW_HEAD_ON  := "c0A5FA0"       ; focused column header
MW_HEAD_OFF := "c606060"

; ---------------------------------------------------------------------------
MW_Show(*) {
    global MW_Gui, MW_Source, MW_Selection, MW_Search

    try MW_Source := WinGetID("A")
    catch
        MW_Source := 0

    MW_Selection := PAL_CaptureSelection()

    if (MW_Gui = "")
        MW_Build()

    try MW_Search.Value := ""
    MW_RefreshClips()
    MW_RefreshTree()
    MW_Gui.Show()

    ; Land on the clipboard, not the search box: the common case is "paste
    ; the thing I copied a minute ago", which is one keystroke from here.
    MW_FocusClips()
}

MW_Build() {
    global MW_Gui, MW_Search, MW_Clips, MW_Tree, MW_Status
    global MW_ClipHead, MW_MenuHead

    MW_Gui := Gui("+Resize +MinSize720x420", "Beijer.bot")
    MW_Gui.SetFont("s9", "Segoe UI")
    MW_Gui.OnEvent("Close", MW_Hide)
    MW_Gui.OnEvent("Escape", MW_Hide)
    MW_Gui.OnEvent("Size", MW_OnSize)

    MW_Gui.Add("Text", "xm ym+3 w46", "Search:")
    MW_Search := MW_Gui.Add("Edit", "x+4 yp-3 w800")
    MW_Search.OnEvent("Change", (*) => MW_OnSearch())

    MW_ClipHead := MW_Gui.Add("Text", "xm y+10 w440 " MW_HEAD_ON, "CLIPBOARD")
    MW_MenuHead := MW_Gui.Add("Text", "x+10 yp w400 " MW_HEAD_OFF, "MENU")

    MW_Clips := MW_Gui.Add("ListView", "xm y+4 w440 h420 -Multi",
                           ["", "When", "Text"])
    MW_Clips.OnEvent("DoubleClick", (*) => MW_RunClip())
    MW_Clips.OnEvent("ItemFocus", (*) => MW_MarkFocus("clips"))
    try MW_Clips.OnNotify(-12, MW_CustomDraw)   ; grey out pasted entries

    MW_Tree := MW_Gui.Add("TreeView", "x+10 yp w400 h420")
    MW_Tree.OnEvent("DoubleClick", (*) => MW_RunTree())
    MW_Tree.OnEvent("ItemSelect", (*) => MW_MarkFocus("menu"))

    MW_Status := MW_Gui.Add("Text", "xm y+8 w850", "")

    MW_Keys()
}

; ---------------------------------------------------------------------------
; Clipboard pane
; ---------------------------------------------------------------------------
MW_RefreshClips() {
    global MW_Clips, MW_Shown, CB_Items, MW_Search

    needle := ""
    try needle := Trim(MW_Search.Value)

    MW_Clips.Opt("-Redraw")
    MW_Clips.Delete()
    MW_Shown := []

    for item in CB_Items {
        text := GetKey(item, "text", "")
        if (text = "")
            continue
        if (needle != "" && !InStr(text, needle, false))
            continue
        MW_Clips.Add(, GetKey(item, "pasted", false) ? "✓" : "",
                       CB_FormatTime(GetKey(item, "time", "")),
                       CB_Preview(text))
        MW_Shown.Push(item)
    }

    MW_Clips.ModifyCol(1, 24)
    MW_Clips.ModifyCol(2, 64)
    MW_Clips.ModifyCol(3, 330)
    MW_Clips.Opt("+Redraw")

    if (MW_Shown.Length > 0)
        MW_Clips.Modify(1, "Select Focus")
}

; This pane shows a different subset of the same history than the standalone
; clipboard window does, so it draws from its own row list.
MW_CustomDraw(ctrl, lParam) {
    global MW_Shown
    return BB_DrawPastedRows(lParam, MW_Shown)
}

; ---------------------------------------------------------------------------
; Menu pane
; ---------------------------------------------------------------------------
MW_RefreshTree() {
    global MW_Tree, MW_Nodes, MW_Sections, MW_Search, BeijerBotData

    needle := ""
    try needle := Trim(MW_Search.Value)

    ; Delete() clears the selection, which fires ItemSelect, which asks for
    ; the section legend — while MW_Sections still holds ids belonging to the
    ; tree being destroyed. Drop the stale ids first and mute the handler for
    ; the duration of the rebuild.
    MW_Rebuilding := true
    MW_Nodes := Map()
    MW_Sections := []

    MW_Tree.Opt("-Redraw")
    MW_Tree.Delete()

    if (needle = "")
        MW_FillTree(BeijerBotData["menu"], 0)
    else
        MW_FillFlat(BeijerBotData["menu"], needle, "")

    ; A section that collected nothing is not worth a jump slot.
    kept := []
    for id in MW_Sections {
        if MW_Tree.GetChild(id)
            kept.Push(id)
    }
    MW_Sections := kept

    MW_Tree.Opt("+Redraw")
    MW_Rebuilding := false
}

; Full hierarchy, folders closed, when nothing is being searched for.
;
; A heading becomes a real parent holding everything up to the next heading.
; They used to be siblings of the entries beneath them, which left the tree
; one long flat list with a few bold rows in it — nothing to collapse, and
; nowhere to jump to.
MW_FillTree(items, parent) {
    global MW_Tree, MW_Nodes, MW_Sections

    section := 0        ; heading currently collecting entries, 0 = none

    for item in items {
        kind := GetKey(item, "kind", "")
        if (kind = "separator" || kind = "clipboard")
            continue

        label := PAL_Tidy(GetKey(item, "label", ""))
        if (label = "")
            continue

        if (kind = "heading") {
            ; Not every heading is a section. The old menu used inert NOP
            ; rows for decoration ("Bracket [number]", voice-command
            ; reminders) and those came through as headings too. The data
            ; distinguishes them by its own convention: a real section title
            ; ends with a colon. Anything else is just a row.
            raw := Trim(GetKey(item, "label", ""))
            if !RegExMatch(raw, "[:：]\s*$") {
                id := MW_Tree.Add(label, section ? section : parent, "Bold")
                MW_Nodes[id] := ""
                continue
            }

            section := MW_Tree.Add(label, parent, "Bold")
            MW_Nodes[section] := ""          ; a container, not runnable
            if (parent = 0)
                MW_Sections.Push(section)    ; for Alt+1-9 and Ctrl+↑/↓
            continue
        }

        target := section ? section : parent

        if (kind = "submenu") {
            id := MW_Tree.Add(label, target)
            MW_Nodes[id] := ""
            MW_FillTree(GetKey(item, "items", []), id)
            continue
        }

        id := MW_Tree.Add(label, target)
        MW_Nodes[id] := item
    }
}

; While filtering, hierarchy gets in the way — show matching leaves flat,
; each labelled with where it came from.
MW_FillFlat(items, needle, path) {
    global MW_Tree, MW_Nodes

    for item in items {
        kind := GetKey(item, "kind", "")
        if (kind = "separator" || kind = "heading" || kind = "clipboard")
            continue

        label := PAL_Tidy(GetKey(item, "label", ""))

        if (kind = "submenu") {
            child := path = "" ? label : path " > " label
            MW_FillFlat(GetKey(item, "items", []), needle, child)
            continue
        }

        detail := GetKey(item, "value", "")
        if (detail = "")
            detail := GetKey(item, "url", "")
        if (detail = "")
            detail := GetKey(item, "prompt", "")

        if !(InStr(label, needle, false) || InStr(path, needle, false)
             || InStr(detail, needle, false))
            continue

        shown := path = "" ? label : label "   (" path ")"
        id := MW_Tree.Add(shown, 0)
        MW_Nodes[id] := item
    }
}

; ---------------------------------------------------------------------------
MW_OnSearch() {
    MW_RefreshClips()
    MW_RefreshTree()
    MW_UpdateStatus()
}

MW_UpdateStatus() {
    global MW_Status, MW_Shown, CB_Items, MW_Selection

    sel := MW_Selection = "" ? "no selection"
                             : "selection: " CB_Preview(MW_Selection)
    if (StrLen(sel) > 46)
        sel := SubStr(sel, 1, 46) "..."

    try MW_Status.Value := MW_Shown.Length " of " CB_Items.Length " clips"
        . "   ·   " sel
        . "   ·   ↑↓ move  ·  → menu  ·  ← back  ·  Enter use  ·  Esc close"
}

MW_MarkFocus(which) {
    global MW_ClipHead, MW_MenuHead, MW_HEAD_ON, MW_HEAD_OFF, MW_Status
    global MW_Rebuilding

    ; Selection churn during a rebuild is not the user moving around.
    if (MW_Rebuilding)
        return

    try {
        MW_ClipHead.SetFont(which = "clips" ? MW_HEAD_ON : MW_HEAD_OFF)
        MW_MenuHead.SetFont(which = "menu" ? MW_HEAD_ON : MW_HEAD_OFF)
    }

    ; The hints are different on each side, so show the ones that apply.
    if (which = "menu") {
        legend := MW_SectionLegend()
        try MW_Status.Value := legend != ""
            ? legend "   ·   Ctrl+↑↓ section"
            : "→ open  ·  ← close  ·  Enter use  ·  Esc close"
    } else
        MW_UpdateStatus()
}

MW_FocusClips() {
    global MW_Clips, MW_Shown
    try MW_Clips.Focus()
    if (MW_Shown.Length > 0 && MW_Clips.GetNext(0) = 0)
        MW_Clips.Modify(1, "Select Focus")
    MW_MarkFocus("clips")
    MW_UpdateStatus()
}

MW_FocusTree() {
    global MW_Tree
    try MW_Tree.Focus()
    if !MW_Tree.GetSelection() {
        first := MW_Tree.GetNext(0)
        if first
            MW_Tree.Modify(first, "Select")
    }
    MW_MarkFocus("menu")
}

MW_FocusedIs(ctrl) {
    global MW_Gui
    try return ControlGetFocus("ahk_id " MW_Gui.Hwnd) = ctrl.Hwnd
    catch
        return false
}

; ---------------------------------------------------------------------------
; Keys
;
; Up/Down are passed through to whichever control has focus so the native
; behaviour (and scrolling) is kept; they are only intercepted to hop out of
; the search box. Left/Right do the crossing between panes.
; ---------------------------------------------------------------------------
MW_Keys() {
    global MW_Gui
    HotIfWinActive("ahk_id " MW_Gui.Hwnd)

    Hotkey("Down",        (*) => MW_Down(),  "On")
    Hotkey("Up",          (*) => MW_Up(),    "On")
    Hotkey("Right",       (*) => MW_Right(), "On")
    Hotkey("Left",        (*) => MW_Left(),  "On")
    Hotkey("Enter",       (*) => MW_Activate(), "On")
    Hotkey("NumpadEnter", (*) => MW_Activate(), "On")
    Hotkey("Tab",         (*) => MW_TogglePane(), "On")
    Hotkey("^f",          (*) => MW_FocusSearch(), "On")

    ; Section jumping
    Hotkey("^Down",       (*) => MW_StepSection(1),  "On")
    Hotkey("^Up",         (*) => MW_StepSection(-1), "On")
    Hotkey("Home",        (*) => MW_GoEdge(1),  "On")
    Hotkey("End",         (*) => MW_GoEdge(-1), "On")

    Loop 9 {
        n := A_Index
        Hotkey("!" n, MW_MakeSectionJump(n), "On")
    }

    HotIfWinActive()
}

MW_MakeSectionJump(n) {
    return (*) => MW_GoSection(n)
}

; Home/End go to the ends of whichever pane has focus.
MW_GoEdge(where) {
    global MW_Clips, MW_Tree, MW_Shown

    if MW_FocusedIs(MW_Clips) {
        if (MW_Shown.Length = 0)
            return
        row := (where = 1) ? 1 : MW_Shown.Length
        MW_Clips.Modify(0, "-Select")
        MW_Clips.Modify(row, "Select Focus Vis")
        return
    }

    if (where = 1) {
        first := MW_Tree.GetNext(0)
        if first
            MW_Tree.Modify(first, "Select Vis")
        return
    }
    last := 0
    id := 0
    while (id := MW_Tree.GetNext(id, "Full"))
        last := id
    if last
        MW_Tree.Modify(last, "Select Vis")
}

MW_FocusSearch() {
    global MW_Search
    try MW_Search.Focus()
}

MW_Down() {
    global MW_Search
    if MW_FocusedIs(MW_Search) {
        MW_FocusClips()
        return
    }
    Send("{Down}")          ; our own Send does not retrigger our hotkeys
}

MW_Up() {
    global MW_Search, MW_Clips, MW_Tree
    if MW_FocusedIs(MW_Search)
        return
    ; At the top of either pane, go back up into the search box.
    if (MW_FocusedIs(MW_Clips) && MW_Clips.GetNext(0) = 1) {
        MW_FocusSearch()
        return
    }
    if (MW_FocusedIs(MW_Tree)
        && MW_Tree.GetSelection() = MW_Tree.GetNext(0)) {
        MW_FocusSearch()
        return
    }
    Send("{Up}")
}

MW_Right() {
    global MW_Search, MW_Clips, MW_Tree

    if (MW_FocusedIs(MW_Search)) {
        Send("{Right}")                 ; move the caret, not the pane
        return
    }
    if (MW_FocusedIs(MW_Clips)) {
        MW_FocusTree()
        return
    }

    ; In the tree: open a closed folder, or step into an open one.
    id := MW_Tree.GetSelection()
    if !id
        return
    if MW_Tree.GetChild(id) {
        if !MW_Tree.Get(id, "Expanded") {
            MW_Tree.Modify(id, "Expand")
            return
        }
        MW_Tree.Modify(MW_Tree.GetChild(id), "Select")
    }
}

MW_Left() {
    global MW_Search, MW_Clips, MW_Tree

    if (MW_FocusedIs(MW_Search)) {
        Send("{Left}")
        return
    }
    if (MW_FocusedIs(MW_Clips))
        return

    ; In the tree: close, then climb, then cross back to the clipboard.
    id := MW_Tree.GetSelection()
    if !id {
        MW_FocusClips()
        return
    }
    if (MW_Tree.GetChild(id) && MW_Tree.Get(id, "Expanded")) {
        MW_Tree.Modify(id, "-Expand")
        return
    }
    parent := MW_Tree.GetParent(id)
    if (parent) {
        MW_Tree.Modify(parent, "Select")
        return
    }
    MW_FocusClips()
}

MW_TogglePane() {
    global MW_Clips
    if MW_FocusedIs(MW_Clips)
        MW_FocusTree()
    else
        MW_FocusClips()
}

; ---------------------------------------------------------------------------
; Jumping around the menu
;
; Six or seven sections, each holding a dozen or more entries, is too much to
; walk one row at a time. Alt+1-9 lands on a section directly; Ctrl+↑/↓ steps
; between them from wherever you are.
; ---------------------------------------------------------------------------
MW_GoSection(n) {
    global MW_Sections, MW_Tree

    if (n < 1 || n > MW_Sections.Length)
        return
    id := MW_Sections[n]

    MW_FocusTree()
    MW_Tree.Modify(id, "Expand Select Vis")
    MW_ShowSectionHint(n)
}

; Which top-level node the selection sits under.
MW_TopAncestor(id) {
    global MW_Tree
    if !id
        return 0
    while (parent := MW_Tree.GetParent(id))
        id := parent
    return id
}

MW_StepSection(dir) {
    global MW_Sections, MW_Tree

    if (MW_Sections.Length = 0)
        return

    top := MW_TopAncestor(MW_Tree.GetSelection())

    ; Where does that sit in the section list?
    at := 0
    for i, id in MW_Sections {
        if (id = top) {
            at := i
            break
        }
    }

    if (at = 0)
        next := (dir > 0) ? 1 : MW_Sections.Length
    else {
        next := at + dir
        if (next < 1)
            next := MW_Sections.Length          ; wrap
        if (next > MW_Sections.Length)
            next := 1
    }
    MW_GoSection(next)
}

MW_ShowSectionHint(n) {
    global MW_Status, MW_Tree, MW_Sections
    if (n < 1 || n > MW_Sections.Length)
        return
    name := ""
    try name := MW_Tree.GetText(MW_Sections[n])
    catch
        return
    try MW_Status.Value := "Section " n "/" MW_Sections.Length ": " name
        . "   ·   Alt+1-9 jump  ·  Ctrl+↑↓ next section  ·  Esc close"
}

; A list of the sections with their numbers, so the shortcuts are findable.
MW_SectionLegend() {
    global MW_Sections, MW_Tree
    out := ""
    for i, id in MW_Sections {
        if (i > 9)
            break
        ; GetText throws on an id from a tree that has been rebuilt. Skip it
        ; rather than let a status-bar refresh raise an error dialog.
        text := ""
        try text := MW_Tree.GetText(id)
        catch
            continue
        out .= (out = "" ? "" : "   ") "Alt+" i " " text
    }
    return out
}

MW_Activate() {
    global MW_Search, MW_Clips, MW_Tree

    if MW_FocusedIs(MW_Search) {
        MW_FocusClips()
        return
    }
    if MW_FocusedIs(MW_Clips) {
        MW_RunClip()
        return
    }
    MW_RunTree()
}

; ---------------------------------------------------------------------------
; Doing things
; ---------------------------------------------------------------------------
MW_ReturnToSource() {
    global MW_Source
    if (MW_Source && WinExist("ahk_id " MW_Source)) {
        try {
            WinActivate("ahk_id " MW_Source)
            WinWaitActive("ahk_id " MW_Source, , 1)
        }
    }
    Sleep(80)
}

MW_RunClip() {
    global MW_Clips, MW_Shown

    row := MW_Clips.GetNext(0)
    if (row = 0 || row > MW_Shown.Length)
        return
    clip := MW_Shown[row]

    clip["pasted"] := true
    CB_Save()

    MW_Hide()
    MW_ReturnToSource()
    CB_SetClipboard(GetKey(clip, "text", ""))
    Send("^v")
}

MW_RunTree() {
    global MW_Tree, MW_Nodes, MW_Selection

    id := MW_Tree.GetSelection()
    if !id
        return

    ; A folder or heading toggles instead of running.
    if (MW_Tree.GetChild(id) || !MW_Nodes.Has(id) || MW_Nodes[id] = "") {
        if MW_Tree.GetChild(id)
            MW_Tree.Modify(id, MW_Tree.Get(id, "Expanded") ? "-Expand"
                                                           : "Expand")
        return
    }

    item := MW_Nodes[id]
    MW_Hide()
    MW_ReturnToSource()
    ExecuteEntry(item, MW_Selection)
}

MW_Hide(*) {
    global MW_Gui
    try MW_Gui.Hide()
    return true
}

MW_OnSize(thisGui, minMax, width, height) {
    global MW_Search, MW_Clips, MW_Tree, MW_Status
    global MW_ClipHead, MW_MenuHead
    if (minMax = -1)
        return

    pad   := 12
    gap   := 10
    total := width - pad * 2 - gap
    if (total < 300)
        total := 300
    leftW  := Round(total * 0.55)
    rightW := total - leftW
    h := height - 130
    if (h < 120)
        h := 120

    try {
        MW_Search.Move(, , width - pad * 2 - 50)
        MW_ClipHead.Move(, , leftW)
        MW_MenuHead.Move(pad + leftW + gap, , rightW)
        MW_Clips.Move(, , leftW, h)
        MW_Clips.ModifyCol(3, leftW - 100)
        MW_Tree.Move(pad + leftW + gap, , rightW, h)
        MW_Status.Move(, , width - pad * 2)
    }
}
