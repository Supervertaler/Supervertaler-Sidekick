#Requires AutoHotkey v2.0
; ===========================================================================
; lib/editor.ahk — the Library Editor.
;
; Add, edit, delete and reorder any menu entry without touching the script.
; Changes are written to data\menu.json and the live menu is rebuilt on save.
;
; The tree on the left mirrors the menu's own structure: the headings that
; divide the menu into sections become the tree's sections, and submenus hang
; underneath the section they appear in. Everything the menu can show is
; therefore reachable here — snippets, searches, AI prompts, bookmarks and
; conversions alike.
;
; A "section" is a slice of the top-level array rather than an array of its
; own, so edits carry a start/end range and operate on absolute indices in
; the parent array.
; ===========================================================================

global LE_Gui     := ""
global LE_Tree    := ""
global LE_List    := ""
global LE_Nodes   := Map()   ; TreeView item id -> scope Map
global LE_Scope   := ""      ; Map("array", arr, "start", n, "end", n)
global LE_Dirty   := false

LE_KINDS := ["text", "keys", "url", "run", "search", "ai",
             "action", "heading", "submenu", "separator", "clipboard"]

; What the Value field means for each kind — shown as a hint so the field is
; never ambiguous.
LE_HINTS := Map(
    "text",      "The exact text to type out.",
    "keys",      "A key combination, e.g.  ^+*  for Ctrl+Shift+*",
    "url",       "A web address to open.",
    "run",       "A file or folder to launch.",
    "search",    "A search URL. Use {q} where the selected text goes.",
    "ai",        "The prompt. Your selected text is appended to it.",
    "action",    "The name of a built-in function.",
    "heading",   "Not used — a heading is just a label.",
    "submenu",   "Not used — a submenu holds other entries.",
    "separator", "Not used — a separator is just a dividing line.",
    "clipboard", "Not used — fills itself with your recent clips."
)

; Which data field holds the payload, per kind.
LE_ValueField(kind) {
    switch kind {
        case "search":    return "url"
        case "ai":        return "prompt"
        case "action":    return "func"
        case "url", "run": return "value"
        default:          return "value"
    }
}

; Fields carried through an edit untouched, so per-entry AI overrides and the
; like are not silently dropped when someone renames an entry.
LE_PRESERVE := ["system", "model", "provider", "effort", "maxtokens",
                "selection", "browser", "arg"]

OpenLibraryEditor(*) {
    global LE_Gui
    if (LE_Gui != "") {
        LE_Gui.Show()
        return
    }

    LE_Gui := Gui("+Resize +MinSize820x500", "Beijer.bot — Library Editor")
    LE_Gui.SetFont("s9", "Segoe UI")
    LE_Gui.OnEvent("Close", LE_OnClose)
    LE_Gui.OnEvent("Size", LE_OnSize)

    LE_Gui.Add("Text", "xm ym w260", "Section:")
    LE_Gui.Add("Text", "x+10 yp w560", "Entries:")

    global LE_Tree := LE_Gui.Add("TreeView", "xm y+4 w260 h420")
    LE_Tree.OnEvent("ItemSelect", LE_OnTreeSelect)

    global LE_List := LE_Gui.Add("ListView", "x+10 yp w560 h420",
                                 ["Label", "Type", "Value"])
    LE_List.OnEvent("DoubleClick", (*) => LE_EditSelected())

    LE_Gui.Add("Button", "xm y+8 w104", "New entry")
        .OnEvent("Click", (*) => LE_NewEntry())
    LE_Gui.Add("Button", "x+6 w80", "Edit").OnEvent("Click", (*) => LE_EditSelected())
    LE_Gui.Add("Button", "x+6 w80", "Delete").OnEvent("Click", (*) => LE_DeleteSelected())
    LE_Gui.Add("Button", "x+6 w70", "Move up").OnEvent("Click", (*) => LE_Move(-1))
    LE_Gui.Add("Button", "x+6 w80", "Move down").OnEvent("Click", (*) => LE_Move(1))

    LE_Gui.Add("Button", "x+30 w120 Default", "Save && rebuild")
        .OnEvent("Click", (*) => LE_Save())
    LE_Gui.Add("Button", "x+6 w80", "Close").OnEvent("Click", (*) => LE_OnClose())

    ; Whole-section reordering, on its own row so it is clearly a different
    ; operation from moving one entry.
    LE_Gui.Add("Text", "xm y+10 w150", "Selected section:")
    LE_Gui.Add("Button", "x+6 yp-4 w110", "Section up")
        .OnEvent("Click", (*) => LE_MoveSection(-1))
    LE_Gui.Add("Button", "x+6 w110", "Section down")
        .OnEvent("Click", (*) => LE_MoveSection(1))

    LE_BuildTree()
    LE_Gui.Show("w860 h560")
}

; ---------------------------------------------------------------------------
LE_Scope_(arr, start, end) {
    s := Map()
    s["array"] := arr
    s["start"] := start
    s["end"]   := end
    return s
}

LE_BuildTree() {
    global LE_Tree, LE_Nodes, LE_Scope, BeijerBotData

    LE_Tree.Delete()
    LE_Nodes := Map()

    top := BeijerBotData["menu"]

    root := LE_Tree.Add("Everything", , "Expand Bold")
    LE_Nodes[root] := LE_Scope_(top, 1, top.Length)

    ; Walk the top level, opening a new section at each heading. Entries that
    ; appear before the first heading belong to an implicit opening section.
    sectionId := 0
    sectionStart := 1

    CloseSection(endIdx) {
        if (sectionId && endIdx >= sectionStart)
            LE_Nodes[sectionId] := LE_Scope_(top, sectionStart, endIdx)
    }

    for i, item in top {
        kind := GetKey(item, "kind", "")

        if (kind = "heading") {
            CloseSection(i - 1)
            label := Trim(GetKey(item, "label", "(section)"))
            sectionId := LE_Tree.Add(label, root)
            sectionStart := i
            continue
        }

        if (kind = "submenu") {
            if !item.Has("items")
                item["items"] := []
            sub := item["items"]
            parent := sectionId ? sectionId : root
            id := LE_Tree.Add(GetKey(item, "label", "(unnamed)"), parent)
            LE_Nodes[id] := LE_Scope_(sub, 1, sub.Length)
        }
    }
    CloseSection(top.Length)

    LE_Scope := LE_Nodes[root]
    LE_Tree.Modify(root, "Select")
    LE_RefreshList()
}

LE_OnTreeSelect(tree, itemId) {
    global LE_Nodes, LE_Scope
    if LE_Nodes.Has(itemId) {
        LE_Scope := LE_Nodes[itemId]
        LE_RefreshList()
    }
}

LE_ScopeArray() {
    global LE_Scope
    return (LE_Scope is Map) ? LE_Scope["array"] : ""
}

LE_Count() {
    global LE_Scope
    if !(LE_Scope is Map)
        return 0
    n := LE_Scope["end"] - LE_Scope["start"] + 1
    return (n > 0) ? n : 0
}

; Row in the list -> index in the underlying array.
LE_AbsIndex(row) {
    global LE_Scope
    return LE_Scope["start"] + row - 1
}

LE_RefreshList() {
    global LE_List, LE_Scope

    LE_List.Opt("-Redraw")
    LE_List.Delete()

    arr := LE_ScopeArray()
    if (arr is Array) {
        Loop LE_Count() {
            item := arr[LE_AbsIndex(A_Index)]
            kind  := GetKey(item, "kind", "")
            label := GetKey(item, "label", "")

            value := GetKey(item, LE_ValueField(kind), "")
            if (value = "")
                value := GetKey(item, "value", "")

            value := StrReplace(StrReplace(value, "`r", " "), "`n", " ")
            if (StrLen(value) > 90)
                value := SubStr(value, 1, 90) "..."

            if (kind = "separator")
                label := "----------"

            LE_List.Add(, label, kind, value)
        }
    }

    LE_List.ModifyCol(1, 250)
    LE_List.ModifyCol(2, 70)
    LE_List.ModifyCol(3, 220)
    LE_List.Opt("+Redraw")
}

; ---------------------------------------------------------------------------
LE_SelectedRow() {
    global LE_List
    row := LE_List.GetNext(0)
    if (row = 0) {
        MsgBox("Select an entry first.", "Library Editor", "Icon!")
        return 0
    }
    return row
}

LE_NewEntry() {
    global LE_Scope, LE_Dirty
    arr := LE_ScopeArray()
    if !(arr is Array)
        return

    item := LE_EntryDialog("")
    if (item = "")
        return

    ; New entries land at the end of the section, not the end of the menu.
    arr.InsertAt(LE_Scope["end"] + 1, item)
    LE_Scope["end"] := LE_Scope["end"] + 1
    LE_Dirty := true
    LE_RefreshList()
}

LE_EditSelected() {
    global LE_Dirty
    row := LE_SelectedRow()
    if !row
        return
    arr := LE_ScopeArray()
    idx := LE_AbsIndex(row)

    updated := LE_EntryDialog(arr[idx])
    if (updated = "")
        return
    arr[idx] := updated
    LE_Dirty := true
    LE_RefreshList()
    LE_List.Modify(row, "Select Focus")
}

LE_DeleteSelected() {
    global LE_Scope, LE_Dirty
    row := LE_SelectedRow()
    if !row
        return
    arr := LE_ScopeArray()
    idx := LE_AbsIndex(row)

    item := arr[idx]
    label := GetKey(item, "label", "(separator)")

    extra := ""
    if (GetKey(item, "kind", "") = "submenu")
        extra := "`n`nThis will delete the submenu and everything in it ("
               . GetKey(item, "items", []).Length " entries)."

    if (MsgBox("Delete this entry?`n`n" label extra,
               "Library Editor", "YesNo Icon?") != "Yes")
        return

    arr.RemoveAt(idx)
    LE_Scope["end"] := LE_Scope["end"] - 1
    LE_Dirty := true

    ; Deleting a submenu or heading changes the tree, not just the list.
    if (GetKey(item, "kind", "") = "submenu"
        || GetKey(item, "kind", "") = "heading")
        LE_BuildTree()
    else
        LE_RefreshList()
}

; ---------------------------------------------------------------------------
; Moving whole sections.
;
; A section is a heading plus everything up to the next heading — a
; contiguous run of the top-level array, not a container. Reordering one
; means lifting that run and putting it back on the other side of its
; neighbour, which is why this cannot use the per-entry swap above.
; ---------------------------------------------------------------------------
LE_SectionBlocks() {
    global BeijerBotData
    top := BeijerBotData["menu"]
    blocks := []
    cur := ""

    Loop top.Length {
        i := A_Index
        if (GetKey(top[i], "kind", "") = "heading") {
            if (cur != "")
                blocks.Push(cur)
            cur := Map("start", i, "end", i)
        } else if (cur != "")
            cur["end"] := i
    }
    if (cur != "")
        blocks.Push(cur)
    return blocks
}

LE_MoveSection(delta) {
    global BeijerBotData, LE_Scope, LE_Dirty

    if !(LE_Scope is Map) {
        MsgBox("Select a section in the tree first.",
               "Library Editor", "Icon!")
        return
    }

    blocks := LE_SectionBlocks()

    idx := 0
    for i, b in blocks {
        if (b["start"] = LE_Scope["start"] && b["end"] = LE_Scope["end"]) {
            idx := i
            break
        }
    }
    if (!idx) {
        MsgBox("Select a section on the left — whole sections move, "
               "individual entries use the buttons above.",
               "Library Editor", "Icon!")
        return
    }

    target := idx + delta
    if (target < 1 || target > blocks.Length)
        return

    top := BeijerBotData["menu"]
    a := blocks[idx < target ? idx : target]      ; the earlier block
    b := blocks[idx < target ? target : idx]      ; the later one

    ; Remember which heading we are moving so it can be reselected after the
    ; tree is rebuilt; array indices will all have shifted.
    moved := top[LE_Scope["start"]]

    rebuilt := []
    Loop a["start"] - 1                            ; before both
        rebuilt.Push(top[A_Index])
    Loop b["end"] - b["start"] + 1                 ; the later block, first
        rebuilt.Push(top[b["start"] + A_Index - 1])
    if (b["start"] > a["end"] + 1) {               ; anything stranded between
        Loop b["start"] - a["end"] - 1
            rebuilt.Push(top[a["end"] + A_Index])
    }
    Loop a["end"] - a["start"] + 1                 ; the earlier block, after
        rebuilt.Push(top[a["start"] + A_Index - 1])
    Loop top.Length - b["end"]                     ; after both
        rebuilt.Push(top[b["end"] + A_Index])

    BeijerBotData["menu"] := rebuilt
    LE_Dirty := true
    LE_BuildTree()
    LE_ReselectSection(moved)
}

; Find the tree node whose scope starts at the given heading and select it.
LE_ReselectSection(heading) {
    global LE_Tree, LE_Nodes, LE_Scope, BeijerBotData

    top := BeijerBotData["menu"]
    pos := 0
    Loop top.Length {
        if (top[A_Index] == heading) {
            pos := A_Index
            break
        }
    }
    if (!pos)
        return

    for id, scope in LE_Nodes {
        if (scope["start"] = pos) {
            LE_Scope := scope
            LE_Tree.Modify(id, "Select Vis")
            LE_RefreshList()
            return
        }
    }
}

LE_Move(delta) {
    global LE_Scope, LE_List, LE_Dirty
    row := LE_SelectedRow()
    if !row
        return

    target := row + delta
    if (target < 1 || target > LE_Count())
        return

    arr := LE_ScopeArray()
    a := LE_AbsIndex(row)
    b := LE_AbsIndex(target)
    tmp := arr[a]
    arr[a] := arr[b]
    arr[b] := tmp

    LE_Dirty := true
    LE_RefreshList()
    LE_List.Modify(target, "Select Focus")
}

; ---------------------------------------------------------------------------
; Add / edit dialog. Returns a populated Map, or "" if cancelled.
; ---------------------------------------------------------------------------
LE_EntryDialog(existing) {
    global LE_Gui, LE_KINDS, LE_HINTS, LE_PRESERVE

    result := Map("ok", false, "item", "")

    isEdit := (existing is Map)
    title  := isEdit ? "Edit entry" : "New entry"

    g := Gui("+Owner" LE_Gui.Hwnd " +ToolWindow", title)
    g.SetFont("s9", "Segoe UI")

    g.Add("Text", "xm ym", "Label (what appears on the menu):")
    eLabel := g.Add("Edit", "xm y+2 w540",
                    isEdit ? GetKey(existing, "label", "") : "")

    g.Add("Text", "xm y+8", "Type:")
    ddl := g.Add("DropDownList", "xm y+2 w160", LE_KINDS)

    curKind := isEdit ? GetKey(existing, "kind", "text") : "text"
    chosen := 0
    for i, k in LE_KINDS {
        if (k = curKind) {
            chosen := i
            break
        }
    }
    if (chosen = 0) {
        ; An unrecognised kind would otherwise silently become the first entry
        ; in the list and overwrite the payload on save.
        LE_KINDS.Push(curKind)
        ddl.Add([curKind])
        chosen := LE_KINDS.Length
    }
    ddl.Choose(chosen)

    hint := g.Add("Text", "x+12 yp+3 w360 cGray",
                  LE_HINTS.Has(curKind) ? LE_HINTS[curKind] : "")

    g.Add("Text", "xm y+10", "Value:")

    curValue := isEdit ? GetKey(existing, LE_ValueField(curKind), "") : ""
    if (isEdit && curValue = "")
        curValue := GetKey(existing, "value", "")
    eValue := g.Add("Edit", "xm y+2 w540 r8 Multi", curValue)

    chkBreak := g.Add("CheckBox", "xm y+8", "Start a new column here")
    if (isEdit && GetKey(existing, "barbreak", false))
        chkBreak.Value := 1

    ; Show which extras are being carried through, so it is clear they survive.
    carried := ""
    if isEdit {
        for f in LE_PRESERVE {
            if (GetKey(existing, f, "") != "")
                carried .= (carried = "" ? "" : ", ") f
        }
    }
    if (carried != "")
        g.Add("Text", "xm y+6 w540 cGray", "Kept as-is: " carried)

    ddl.OnEvent("Change", (*) => hint.Value :=
        LE_HINTS.Has(ddl.Text) ? LE_HINTS[ddl.Text] : "")

    btnSave := g.Add("Button", "xm y+12 w100 Default", "Save")
    g.Add("Button", "x+8 w100", "Cancel").OnEvent("Click", (*) => g.Destroy())
    btnSave.OnEvent("Click", DoSave)

    DoSave(*) {
        kind  := ddl.Text
        label := Trim(eLabel.Value)
        value := eValue.Value

        needsLabel := (kind != "separator")
        needsValue := (kind = "text" || kind = "keys" || kind = "url"
                    || kind = "run" || kind = "action" || kind = "search"
                    || kind = "ai")

        if (needsLabel && label = "") {
            MsgBox("Please give the entry a label.", "Library Editor", "Icon!")
            return
        }
        if (kind = "search" && !InStr(value, "{q}")) {
            MsgBox("A search URL needs {q} to mark where the selected text "
                   "goes.`n`nFor example:`n"
                   "https://en.wiktionary.org/wiki/{q}",
                   "Library Editor", "Icon!")
            return
        }
        if (needsValue && Trim(value) = "") {
            MsgBox("Please fill in the Value field.", "Library Editor", "Icon!")
            return
        }

        item := Map()
        item["kind"] := kind
        if (kind != "separator")
            item["label"] := label

        if (kind = "submenu")
            item["items"] := isEdit ? GetKey(existing, "items", []) : []
        else if (kind != "heading" && kind != "separator"
                 && kind != "clipboard")
            item[LE_ValueField(kind)] := value

        ; Carry forward anything the dialog does not expose.
        if isEdit {
            for f in LE_PRESERVE {
                v := GetKey(existing, f, "")
                if (v != "")
                    item[f] := v
            }
        }

        if (chkBreak.Value)
            item["barbreak"] := true

        result["ok"] := true
        result["item"] := item
        g.Destroy()
    }

    g.Show()
    WinWaitClose("ahk_id " g.Hwnd)

    return result["ok"] ? result["item"] : ""
}

; ---------------------------------------------------------------------------
LE_Save() {
    global BeijerBotData, LE_Dirty
    if !SaveMenuData(BeijerBotData)
        return
    LE_Dirty := false
    ReloadBeijerBotMenu()
    LE_BuildTree()
    MsgBox("Saved. The menu has been rebuilt.", "Library Editor", "Iconi T2")
}

LE_OnClose(*) {
    global LE_Gui, LE_Dirty, BeijerBotData
    if LE_Dirty {
        answer := MsgBox("You have unsaved changes.`n`nSave before closing?",
                         "Library Editor", "YesNoCancel Icon?")
        if (answer = "Cancel")
            return true          ; keep the window open
        if (answer = "Yes")
            LE_Save()
        else {
            BeijerBotData := LoadMenuData()   ; discard edits
            ReloadBeijerBotMenu()
        }
    }
    LE_Dirty := false
    LE_Gui.Destroy()
    LE_Gui := ""
    return true
}

LE_OnSize(thisGui, minMax, width, height) {
    global LE_Tree, LE_List
    if (minMax = -1)
        return
    treeW := 260
    listW := width - treeW - 40
    h     := height - 130          ; room for the section-move row
    if (h < 120)
        h := 120
    if (listW < 200)
        listW := 200
    LE_Tree.Move(, , treeW, h)
    LE_List.Move(treeW + 30, , listW, h)
    LE_List.ModifyCol(3, listW - 340)
}
