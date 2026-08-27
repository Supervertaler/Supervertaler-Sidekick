#Requires AutoHotkey v2.0
; ===========================================================================
; lib/editor.ahk — the Library Editor.
;
; Add, edit, delete and reorder menu entries without touching the script.
; Changes are written to data\menu.json and the live menu is rebuilt on save.
; ===========================================================================

global LE_Gui     := ""
global LE_Tree    := ""
global LE_List    := ""
global LE_Nodes   := Map()   ; TreeView item id  ->  the array it represents
global LE_Current := ""      ; array currently shown in the ListView
global LE_Dirty   := false

LE_KINDS := ["text", "keys", "url", "run", "search",
             "action", "heading", "submenu", "separator"]

; What the Value field means for each kind — shown as a hint so the field is
; never ambiguous.
LE_HINTS := Map(
    "text",      "The exact text to type out.",
    "keys",      "A key combination, e.g.  ^+*  for Ctrl+Shift+*",
    "url",       "A web address to open.",
    "run",       "A file or folder to launch.",
    "search",    "A search URL. Use {q} where the selected text goes.",
    "action",    "The name of a built-in function (see the list below).",
    "heading",   "Not used — headings are just labels.",
    "submenu",   "Not used — a submenu holds other entries.",
    "separator", "Not used — a separator is just a dividing line."
)

OpenLibraryEditor(*) {
    global LE_Gui
    if (LE_Gui != "") {
        LE_Gui.Show()
        return
    }

    LE_Gui := Gui("+Resize +MinSize760x420", "Beijer.bot — Library Editor")
    LE_Gui.SetFont("s9", "Segoe UI")
    LE_Gui.OnEvent("Close", LE_OnClose)
    LE_Gui.OnEvent("Size", LE_OnSize)

    LE_Gui.Add("Text", "xm ym w220", "Section:")
    LE_Gui.Add("Text", "x+10 yp w560", "Entries:")

    global LE_Tree := LE_Gui.Add("TreeView", "xm y+4 w220 h420")
    LE_Tree.OnEvent("ItemSelect", LE_OnTreeSelect)

    global LE_List := LE_Gui.Add("ListView", "x+10 yp w560 h420",
                                 ["Label", "Type", "Value"])
    LE_List.OnEvent("DoubleClick", (*) => LE_EditSelected())

    LE_Gui.Add("Button", "xm y+8 w104", "New entry")
        .OnEvent("Click", (*) => LE_NewEntry())
    LE_Gui.Add("Button", "x+6 w104", "Edit").OnEvent("Click", (*) => LE_EditSelected())
    LE_Gui.Add("Button", "x+6 w104", "Delete").OnEvent("Click", (*) => LE_DeleteSelected())
    LE_Gui.Add("Button", "x+6 w70", "Move up").OnEvent("Click", (*) => LE_Move(-1))
    LE_Gui.Add("Button", "x+6 w70", "Move down").OnEvent("Click", (*) => LE_Move(1))

    LE_Gui.Add("Button", "x+40 w110 Default", "Save && rebuild")
        .OnEvent("Click", (*) => LE_Save())
    LE_Gui.Add("Button", "x+6 w80", "Close").OnEvent("Click", (*) => LE_OnClose())

    LE_BuildTree()
    LE_Gui.Show("w800 h500")
}

; ---------------------------------------------------------------------------
LE_BuildTree() {
    global LE_Tree, LE_Nodes, LE_Current, BeijerBotData

    LE_Tree.Delete()
    LE_Nodes := Map()

    root := LE_Tree.Add("Top level", , "Expand Bold")
    LE_Nodes[root] := BeijerBotData["menu"]

    for item in BeijerBotData["menu"] {
        if (GetKey(item, "kind", "") != "submenu")
            continue
        label := GetKey(item, "label", "(unnamed)")
        if !item.Has("items")
            item["items"] := []
        id := LE_Tree.Add(label, root)
        LE_Nodes[id] := item["items"]
    }

    LE_Current := BeijerBotData["menu"]
    LE_Tree.Modify(root, "Select")
    LE_RefreshList()
}

LE_OnTreeSelect(tree, itemId) {
    global LE_Nodes, LE_Current
    if LE_Nodes.Has(itemId) {
        LE_Current := LE_Nodes[itemId]
        LE_RefreshList()
    }
}

LE_RefreshList() {
    global LE_List, LE_Current

    LE_List.Opt("-Redraw")
    LE_List.Delete()

    if (LE_Current is Array) {
        for item in LE_Current {
            kind  := GetKey(item, "kind", "")
            label := GetKey(item, "label", "")

            value := GetKey(item, "value", "")
            if (value = "")
                value := GetKey(item, "url", "")
            if (value = "")
                value := GetKey(item, "func", "")

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
    global LE_Current, LE_Dirty
    item := LE_EntryDialog("")
    if (item = "")
        return
    LE_Current.Push(item)
    LE_Dirty := true
    LE_RefreshList()
}

LE_EditSelected() {
    global LE_Current, LE_Dirty
    row := LE_SelectedRow()
    if !row
        return
    updated := LE_EntryDialog(LE_Current[row])
    if (updated = "")
        return
    LE_Current[row] := updated
    LE_Dirty := true
    LE_RefreshList()
}

LE_DeleteSelected() {
    global LE_Current, LE_Dirty
    row := LE_SelectedRow()
    if !row
        return
    label := GetKey(LE_Current[row], "label", "(separator)")
    if (MsgBox("Delete this entry?`n`n" label,
               "Library Editor", "YesNo Icon?") != "Yes")
        return
    LE_Current.RemoveAt(row)
    LE_Dirty := true
    LE_RefreshList()
}

LE_Move(delta) {
    global LE_Current, LE_List, LE_Dirty
    row := LE_SelectedRow()
    if !row
        return
    target := row + delta
    if (target < 1 || target > LE_Current.Length)
        return
    tmp := LE_Current[row]
    LE_Current[row] := LE_Current[target]
    LE_Current[target] := tmp
    LE_Dirty := true
    LE_RefreshList()
    LE_List.Modify(target, "Select Focus")
}

; ---------------------------------------------------------------------------
; Add / edit dialog. Returns a populated Map, or "" if cancelled.
; ---------------------------------------------------------------------------
LE_EntryDialog(existing) {
    global LE_Gui, LE_KINDS, LE_HINTS

    result := Map("ok", false, "item", "")

    isEdit := (existing is Map)
    title  := isEdit ? "Edit entry" : "New entry"

    g := Gui("+Owner" LE_Gui.Hwnd " +ToolWindow", title)
    g.SetFont("s9", "Segoe UI")

    g.Add("Text", "xm ym", "Label (what appears on the menu):")
    eLabel := g.Add("Edit", "xm y+2 w520",
                    isEdit ? GetKey(existing, "label", "") : "")

    g.Add("Text", "xm y+8", "Type:")
    ddl := g.Add("DropDownList", "xm y+2 w160", LE_KINDS)

    curKind := isEdit ? GetKey(existing, "kind", "text") : "text"
    for i, k in LE_KINDS {
        if (k = curKind) {
            ddl.Choose(i)
            break
        }
    }

    hint := g.Add("Text", "x+12 yp+3 w340 cGray",
                  LE_HINTS.Has(curKind) ? LE_HINTS[curKind] : "")

    g.Add("Text", "xm y+10", "Value:")

    curValue := ""
    if isEdit {
        curValue := GetKey(existing, "value", "")
        if (curValue = "")
            curValue := GetKey(existing, "url", "")
        if (curValue = "")
            curValue := GetKey(existing, "func", "")
    }
    eValue := g.Add("Edit", "xm y+2 w520 r7 Multi", curValue)

    chkBreak := g.Add("CheckBox", "xm y+8", "Start a new column here")
    if (isEdit && GetKey(existing, "barbreak", false))
        chkBreak.Value := 1

    ddl.OnEvent("Change", (*) => hint.Value :=
        LE_HINTS.Has(ddl.Text) ? LE_HINTS[ddl.Text] : "")

    btnSave := g.Add("Button", "xm y+12 w100 Default", "Save")
    g.Add("Button", "x+8 w100", "Cancel").OnEvent("Click", (*) => g.Destroy())

    btnSave.OnEvent("Click", DoSave)

    DoSave(*) {
        kind  := ddl.Text
        label := Trim(eLabel.Value)
        value := eValue.Value

        if (kind != "separator" && label = "") {
            MsgBox("Please give the entry a label.", "Library Editor", "Icon!")
            return
        }
        if (kind = "search" && !InStr(value, "{q}")) {
            MsgBox("A search URL needs {q} to mark where the selected "
                   "text goes.`n`nFor example:`n"
                   "https://en.wiktionary.org/wiki/{q}",
                   "Library Editor", "Icon!")
            return
        }
        if ((kind = "text" || kind = "keys" || kind = "url" || kind = "run"
             || kind = "action") && value = "") {
            MsgBox("Please fill in the Value field.", "Library Editor", "Icon!")
            return
        }

        item := Map()
        item["kind"] := kind
        if (kind != "separator")
            item["label"] := label

        switch kind {
            case "search":
                item["url"] := value
                ; Keep whichever browser the entry already used.
                if (isEdit && GetKey(existing, "browser", "") != "")
                    item["browser"] := existing["browser"]
            case "action":
                item["func"] := value
                if (isEdit && GetKey(existing, "arg", "") != "")
                    item["arg"] := existing["arg"]
            case "submenu":
                item["items"] := isEdit ? GetKey(existing, "items", []) : []
            case "heading", "separator":
                ; label only
            default:
                item["value"] := value
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
        else
            BeijerBotData := LoadMenuData()   ; discard edits
    }
    LE_Gui.Destroy()
    LE_Gui := ""
    return true
}

LE_OnSize(thisGui, minMax, width, height) {
    global LE_Tree, LE_List
    if (minMax = -1)
        return
    treeW := 220
    listW := width - treeW - 40
    h     := height - 90
    if (h < 120)
        h := 120
    LE_Tree.Move(, , treeW, h)
    LE_List.Move(treeW + 30, , listW, h)
}
