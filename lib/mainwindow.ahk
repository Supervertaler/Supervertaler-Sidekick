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

global MW_Nodes     := Map()   ; tree item id -> menu entry Map
global MW_Sections  := []      ; top-level heading node ids, in order
global MW_Rebuilding := false  ; true while the tree is being torn down
global MW_Shown     := []      ; clips currently listed, in row order
global MW_Selection := ""      ; text selected when the window opened
global MW_Source    := 0       ; window to paste back into

; The left pane is tabbed: clipboard history and QuickTrans. The menu tree on
; the right stays put, so a translation can be inserted and a menu action run
; without leaving the window.
global MW_Tabs      := ""
global MW_QTSource  := ""      ; editable source text
global MW_QTSrc     := ""      ; source language
global MW_QTTgt     := ""      ; target language
global MW_QTRows    := []      ; jobs in row order
global MW_QTRowCtl  := []      ; the reusable result-row controls
global MW_QTSel     := 1       ; which result row is selected
global MW_QTLabel   := ""
global MW_QTFromLbl := ""
global MW_QTArrow   := ""
global MW_QTSwapBtn := ""
global MW_QTGoBtn   := ""

; A ceiling only, so a bad engine table cannot spawn controls forever.
MW_QT_MAXROWS := 20


; ---------------------------------------------------------------------------
; tab: 1 = clipboard (default), 2 = QuickTrans. Opening straight onto the
; QuickTrans tab is what the Ctrl+Alt+T hotkey does.
MW_Show(tab := 1) {
    global MW_Gui, MW_Source, MW_Selection, MW_Search, MW_Tabs

    try MW_Source := WinGetID("A")
    catch
        MW_Source := 0

    ; The selection is NOT captured here. Doing so cost ~400ms on every open:
    ; clearing the clipboard and sending Ctrl+C means ClipWait sits out its
    ; full timeout whenever nothing is selected, which is the common case —
    ; you usually open this to paste a clip, not to act on a selection.
    ;
    ; Entries that need the selection copy it themselves once focus is back
    ; on the source window, which is what the classic popup always did.
    MW_Selection := ""

    if (MW_Gui = "")
        MW_Build()

    try MW_Search.Value := ""
    MW_RefreshClips()
    MW_RefreshTree()
    MW_ShowRestored()

    if (tab = 2) {
        MW_Tabs.Value := 2
        MW_FocusResults()
        MW_MarkFocus("clips")
    } else {
        ; Land on the clipboard, not the search box: the common case is
        ; "paste the thing I copied a minute ago", one keystroke from here.
        MW_Tabs.Value := 1
        MW_FocusClips()
    }
}

; Ctrl+Alt+T: open on the QuickTrans tab with the selection already in the
; source box, translating. This replaces the standalone QuickTrans window —
; keeping the menu tree beside the results was the point of the exercise.
MW_ShowQuickTrans(*) {
    global MW_QTSource, MW_QTRows, MW_QTSel, MW_RenderSig

    win := ""
    try win := WinGetProcessName("A")
    SK_Log("QuickTrans: triggered over " win)

    sel := SK_CopySelection(2)
    SK_Log("QuickTrans: copied " StrLen(sel) " chars")

    MW_Show(2)
    SK_Log("QuickTrans: window shown")

    if (sel != "") {
        MW_QTSource.Value := sel
        ; An exception here would abort the thread and leave the window
        ; sitting there with the text in it and nothing happening — which is
        ; exactly what it has been doing.
        try
            MW_QTTranslate()
        catch Error as err {
            SK_Log("QuickTrans: FAILED " err.Message " @ " err.File ":"
                 . err.Line)
            MW_SetStatus("Could not translate: " err.Message)
        }
        return
    }

    ; Nothing was captured. Leaving the last run on screen is worse than
    ; showing nothing: the window looks like it answered, and the answer
    ; belongs to whatever was selected the time before. Clear it, and say so.
    MW_QTSource.Value := ""
    QT_Abort()
    MW_QTRows := []
    MW_QTSel := 1
    MW_RenderSig := ""
    MW_QTLayout()
    MW_SetStatus("Could not copy the selection. Select some text and try "
               . "again, or type it above and press Ctrl+Enter.")
}

MW_Build() {
    global MW_Gui, MW_Search, MW_Clips, MW_Tree, MW_Status
    global MW_Tabs, MW_QTSource, MW_QTSrc, MW_QTTgt
    global MW_QTRowCtl, MW_QTLabel, MW_QTFromLbl, MW_QTArrow
    global MW_QTSwapBtn, MW_QTGoBtn
    global QT_OnUpdate

    MW_Gui := Gui("+Resize +MinSize720x420", "Supervertaler Sidekick")
    MW_Gui.SetFont("s9", "Segoe UI")
    MW_Gui.OnEvent("Close", MW_Hide)
    MW_Gui.OnEvent("Escape", MW_Hide)
    MW_Gui.OnEvent("Size", MW_OnSize)

    MW_Gui.Add("Text", "xm ym+3 w46", "Search:")
    MW_Search := MW_Gui.Add("Edit", "x+4 yp-3 w800")
    MW_Search.OnEvent("Change", (*) => MW_OnSearch())

    ; No column headings: the tab strip already names the left pane, and a
    ; lone "MENU" label over the tree earned nothing but a row of space.

    ; ---- left pane: two tabs ------------------------------------------
    MW_Tabs := MW_Gui.Add("Tab3", "xm y+10 w540 h430",
                          ["Clipboard", "QuickTrans"])
    MW_Tabs.OnEvent("Change", (*) => MW_OnTabChange())

    MW_Tabs.UseTab(1)
    MW_Clips := MW_Gui.Add("ListView", "xp+8 yp+28 w524 h396 -Multi",
                           ["", "When", "Text"])
    MW_Clips.OnEvent("DoubleClick", (*) => MW_RunClip())
    MW_Clips.OnEvent("ItemFocus", (*) => MW_MarkFocus("clips"))
    try MW_Clips.OnNotify(-12, MW_CustomDraw)   ; grey out pasted entries

    MW_Tabs.UseTab(2)

    ; Explicit coordinates rather than a chain of xp/yp. Relative positioning
    ; inside a tab control drifts, which is what left a stray box floating
    ; beside the language row.
    tx := 20            ; left edge inside the tab
    ty := 88            ; below the tab strip
    tw := 512

    MW_QTLabel   := MW_Gui.Add("Text", "x" tx " y" ty " w60", "Source:")
    MW_QTSource  := MW_Gui.Add("Edit", "x" tx " y" (ty + 18) " w" tw " r3 Multi")
    MW_QTSource.OnEvent("Change", (*) => MW_QTLayout())

    ly := ty + 76       ; the language row
    MW_QTFromLbl := MW_Gui.Add("Text", "x" tx " y" (ly + 4) " w36", "From:")
    MW_QTSrc     := MW_Gui.Add("DropDownList", "x" (tx + 40) " y" ly " w118",
                               QT_LangNames())
    MW_QTArrow   := MW_Gui.Add("Text", "x" (tx + 164) " y" (ly + 4) " w14", "→")
    MW_QTTgt     := MW_Gui.Add("DropDownList", "x" (tx + 182) " y" ly " w118",
                               QT_LangNames())
    MW_QTSwapBtn := MW_Gui.Add("Button", "x" (tx + 306) " y" (ly - 1) " w30 h24",
                               "⇄")
    MW_QTSwapBtn.OnEvent("Click", (*) => MW_QTSwap())
    MW_QTGoBtn   := MW_Gui.Add("Button", "x" (tx + 342) " y" (ly - 1) " w96 h24",
                               "Translate")
    MW_QTGoBtn.OnEvent("Click", (*) => MW_QTTranslate())

    ; Results are a stack of full-text fields, not list rows: a translation
    ; cut off at a column edge is no use for judging it against the others.
    ; Rows are created on demand, so adding engines later needs no constant
    ; kept in step with the engine table.
    MW_QTRowCtl := []

    MW_SelectLang(MW_QTSrc, QT_Setting("SourceLang", "Dutch"))
    MW_SelectLang(MW_QTTgt, QT_Setting("TargetLang", "English"))

    ; ---- right pane: the menu, outside the tabs ------------------------
    MW_Tabs.UseTab()
    MW_Tree := MW_Gui.Add("TreeView", "x+10 ym+38 w440 h430")
    MW_Tree.OnEvent("DoubleClick", (*) => MW_RunTree())
    MW_Tree.OnEvent("ItemSelect", (*) => MW_MarkFocus("menu"))

    MW_Status := MW_Gui.Add("Text", "xm y+440 w1000", "")

    ; Results land here as each engine replies.
    QT_OnUpdate := MW_RenderTranslations

    MW_Keys()
}

; Create result rows up to the number asked for. New controls must be added
; while tab 2 is the active target, or they would land on the clipboard tab.
MW_QTEnsureSlots(n) {
    global MW_QTRowCtl, MW_Tabs, MW_Gui, MW_QT_MAXROWS

    if (n > MW_QT_MAXROWS)
        n := MW_QT_MAXROWS
    if (MW_QTRowCtl.Length >= n)
        return

    MW_Tabs.UseTab(2)
    while (MW_QTRowCtl.Length < n) {
        i := MW_QTRowCtl.Length + 1
        MW_Gui.SetFont("s9 Bold")
        num := MW_Gui.Add("Text", "x20 y0 w18 Right", i "")
        MW_Gui.SetFont("s9 Norm")
        eng := MW_Gui.Add("Text", "x42 y0 w104", "")
        ; Which model answered, under the engine name. For OpenRouter the
        ; engine name says nothing at all — it is a gateway, and the model
        ; is the whole of what you chose — and for the rest it still beats
        ; guessing whether that was Haiku or Opus.
        MW_Gui.SetFont("s8")
        mdl := MW_Gui.Add("Text", "x42 y0 w104 cGray", "")
        MW_Gui.SetFont("s9 Norm")
        box := MW_Gui.Add("Edit", "x156 y0 w300 r2 Multi ReadOnly -VScroll", "")
        box.OnEvent("Focus", MW_MakeRowFocus(i))
        num.Visible := false
        eng.Visible := false
        mdl.Visible := false
        box.Visible := false
        MW_QTRowCtl.Push(Map("num", num, "eng", eng, "mdl", mdl, "box", box))
    }
    MW_Tabs.UseTab()
}

; Clicking or tabbing into a row makes it the selected one. Focus is the
; single source of truth: the marker follows it rather than tracking a
; separate index that can drift out of step.
MW_MakeRowFocus(i) {
    return (*) => MW_RowFocused(i)
}

MW_RowFocused(i) {
    global MW_QTSel, MW_QTRows
    if (i < 1 || i > MW_QTRows.Length)
        return
    if (MW_QTSel = i)
        return
    MW_QTSel := i
    MW_QTMarkRows()
}

; Just the markers — cheap enough to run on every focus change, unlike a
; full relayout which would move controls under the mouse.
MW_QTMarkRows() {
    global MW_QTRowCtl, MW_QTRows, MW_QTSel
    Loop MW_QTRowCtl.Length {
        if (A_Index > MW_QTRows.Length)
            break
        MW_QTRowCtl[A_Index]["num"].Value :=
            (A_Index = MW_QTSel ? "▸" : "") A_Index
    }
}

MW_SelectLang(ctrl, name) {
    for i, n in QT_LangNames() {
        if (n = name) {
            ctrl.Choose(i)
            return
        }
    }
    ctrl.Choose(1)
}

MW_ActiveTab() {
    global MW_Tabs
    try return MW_Tabs.Value
    catch
        return 1
}

MW_OnTabChange() {
    global MW_Clips
    if (MW_ActiveTab() = 2) {
        MW_QTLayout()
        MW_FocusResults()
    } else {
        try MW_Clips.Focus()
    }
    MW_MarkFocus("clips")
}

; ---------------------------------------------------------------------------
; Clipboard pane
; ---------------------------------------------------------------------------
; Rebuilding 200 rows costs ~37ms, and between two opens the history usually
; has not changed at all. Skip the work when neither the data nor the filter
; has moved.
MW_RefreshClips(force := false) {
    global MW_Clips, MW_Shown, CB_Items, MW_Search, CB_Rev
    static lastRev := -1
    static lastNeedle := "`n(never)"

    needle := ""
    try needle := Trim(MW_Search.Value)

    if (!force && CB_Rev = lastRev && needle == lastNeedle)
        return
    lastRev := CB_Rev
    lastNeedle := needle

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
    return SK_DrawPastedRows(lParam, MW_Shown)
}

; ---------------------------------------------------------------------------
; QuickTrans tab
; ---------------------------------------------------------------------------
MW_QTTranslate() {
    global MW_QTSource, MW_QTSrc, MW_QTTgt, MW_RenderSig

    text := Trim(MW_QTSource.Value)
    if (text = "") {
        MW_SetStatus("Nothing to translate — select some text, or type it "
                   . "above and press Ctrl+Enter.")
        return
    }

    ; With several LLMs enabled, translating every selection through all of
    ; them costs real money. When auto-fetch is off the free machine
    ; translation runs on its own and the LLMs wait for Ctrl+Shift+Enter.
    groups := (QT_Setting("AutoFetchAI", "1") = "0") ? ["mt"] : ""

    MW_RenderSig := ""                 ; a new run draws from scratch
    n := QT_Start(text, QT_Code(MW_QTSrc.Text), QT_Code(MW_QTTgt.Text), groups)
    SK_Log("QuickTrans: " n " engines started")
    if (n = 0) {
        MW_SetStatus("No engines configured. MyMemory needs no key; add "
                   . "others under Settings → AI providers.")
        return
    }
    MW_RenderTranslations(false)
}

; Bring in the engines that were held back.
MW_QTFetchAI() {
    global MW_QTSource, MW_QTSrc, MW_QTTgt

    text := Trim(MW_QTSource.Value)
    if (text = "")
        return

    n := QT_StartMore(text, QT_Code(MW_QTSrc.Text), QT_Code(MW_QTTgt.Text),
                      ["ai"])
    if (n = 0) {
        MW_SetStatus("No AI engines left to ask.")
        return
    }
    MW_RenderTranslations(false)
}

MW_QTSwap() {
    global MW_QTSrc, MW_QTTgt
    a := MW_QTSrc.Text, b := MW_QTTgt.Text
    MW_SelectLang(MW_QTSrc, b)
    MW_SelectLang(MW_QTTgt, a)
    MW_QTTranslate()
}

global MW_Rendering        := false
global MW_RenderAgain      := false
global MW_RenderAgainDone  := false
global MW_RenderSig        := ""

; QT_Poll fires every 120ms and lands here, and the layout yields — SendMessage
; does, and so does creating controls. So the next tick interrupts the pass
; before it has finished, and the two fight: MW_Tabs.UseTab is global state, so
; a nested pass resets the tab while the outer one is still adding rows, and
; the rows are built against the wrong tab. They exist, they are just not on
; the tab you are looking at — eight engines answer and nothing appears.
;
; So one pass at a time. A tick that arrives mid-pass is not dropped, it is
; remembered and run at the end, because the last one carries finished=true
; and losing it would leave the window saying "Translating…" forever.
MW_RenderTranslations(finished := false) {
    global MW_Rendering, MW_RenderAgain, MW_RenderAgainDone, MW_RenderSig

    if MW_Rendering {
        MW_RenderAgain := true
        if finished
            MW_RenderAgainDone := true
        return
    }

    ; Skip a pass that would draw exactly what is already on screen. QT_Poll
    ; calls this every 120ms whether or not an engine has answered, and a full
    ; relayout five times a second for the minute the slowest engine takes is
    ; both wasted and visibly restless.
    sig := ""
    for job in QT_Ordered()
        sig .= job["state"] ":" StrLen(job["text"]) ";"
    if (!finished && sig = MW_RenderSig)
        return
    MW_RenderSig := sig

    MW_Rendering := true
    try
        MW_RenderOnce(finished)
    finally
        MW_Rendering := false

    ; A tick that arrived mid-pass is remembered — but it is NOT run here.
    ; Running it here would keep this thread busy until the engines were done,
    ; and this thread is usually the hotkey that opened the window: it would
    ; answer no key and no click for the whole minute. Hand it to a one-shot
    ; timer, which runs on a thread of its own once this one has let go.
    if MW_RenderAgain {
        MW_RenderAgain := false
        pending := MW_RenderAgainDone
        MW_RenderAgainDone := false
        SetTimer(MW_RenderLater.Bind(pending), -60)
    }
}

MW_RenderLater(finished) {
    MW_RenderTranslations(finished)
}

MW_RenderOnce(finished := false) {
    global MW_QTRowCtl, MW_QTRows, MW_QTSel, MW_Gui

    jobs := QT_Ordered()
    MW_QTRows := jobs

    if (MW_QTSel < 1)
        MW_QTSel := 1
    if (MW_QTSel > jobs.Length)
        MW_QTSel := jobs.Length

    MW_Gui.Opt("+OwnDialogs")
    MW_QTLayout()

    if (finished) {
        ; Once there is something to insert, take focus off the source box so
        ; the digits act on the results instead of being typed into it.
        if MW_EditingSource()
            MW_FocusResults()
        held := QT_PendingCount(["ai"])
        MW_SetStatus("Done.  1-9 insert  ·  ↑↓ choose  ·  Enter insert  ·  "
                   . "Ctrl+Enter re-translate  ·  Ctrl+C copy"
                   . (held ? "  ·  Ctrl+Shift+Enter ask " held " AI engine"
                           . (held = 1 ? "" : "s") : "  ·  Esc close"))
    }
    else
        MW_SetStatus("Translating…")

}

; Moving and resizing eight rows one at a time leaves fragments of the old
; layout on screen: nothing erases the background a control has just vacated,
; and a row that shrinks leaves the tail of its previous text behind. So the
; pass runs with painting frozen, and the results area is repainted once at
; the end — the results area only, since redrawing the whole window would
; make the menu tree flicker on every keystroke in the source box.
MW_QTLayout() {
    global MW_Gui

    top := 0
    ; Whatever happens in the body, painting has to come back on — a window
    ; left frozen looks exactly like a hung program.
    ; No WM_SETREDRAW. SendMessage pumps the message queue, and pumping it in
    ; the middle of a layout let QT_Poll's 120ms timer land inside the pass —
    ; which reset MW_Tabs.UseTab while rows were being created, leaving the
    ; rows attached to the wrong tab. Eight engines answered and the window
    ; stayed empty. A minimal copy of this window without these two calls
    ; draws perfectly under the same conditions.
    ;
    ; What they were for was cosmetic: suppressing the fragments a shrinking
    ; row leaves behind. MW_QTRepaint below still erases the results area,
    ; which handles most of that, and a stray fragment is a far smaller
    ; problem than no results at all.
    top := MW_QTLayoutBody()
    MW_QTRepaint(top)
}

; Erase and repaint everything from the top of the results down, children
; included. Without RDW_ERASE the vacated background keeps its old pixels,
; which is the whole problem here.
MW_QTRepaint(top) {
    global MW_Gui, MW_Tabs

    try MW_Tabs.GetPos(&tabX, &tabY, &tabW, &tabH)
    catch
        return
    if (top < tabY)
        top := tabY + 20

    rect := Buffer(16, 0)
    NumPut("Int", tabX + 2,        rect, 0)
    NumPut("Int", top,             rect, 4)
    NumPut("Int", tabX + tabW - 2, rect, 8)
    NumPut("Int", tabY + tabH - 2, rect, 12)

    ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN. Deliberately not
    ; RDW_UPDATENOW: this runs on every keystroke in the source box, and
    ; forcing a synchronous repaint each time would make typing stutter.
    ; Marking the area dirty is enough — Windows paints it on the next pass.
    DllCall("RedrawWindow", "Ptr", MW_Gui.Hwnd, "Ptr", rect.Ptr,
            "Ptr", 0, "UInt", 0x0085)
}

; Lay out the whole QuickTrans tab: the source box grows with its text, the
; language row follows it down, and the result rows fill what is left. Each
; translation gets as many lines as it needs so nothing is cut off — which is
; the whole reason these are stacked fields rather than list rows.
; Returns the y the results start at, for the repaint above.
MW_QTLayoutBody() {
    global MW_QTRowCtl, MW_QTRows, MW_QTSel
    global MW_Tabs, MW_QTSource, MW_QTLabel, MW_QTFromLbl, MW_QTArrow
    global MW_QTSrc, MW_QTTgt, MW_QTSwapBtn, MW_QTGoBtn

    ; Make sure there is a row for every engine that reported. Doing it here
    ; means adding an engine needs nothing else changed.
    MW_QTEnsureSlots(MW_QTRows.Length)

    MW_Tabs.GetPos(&tabX, &tabY, &tabW, &tabH)
    left   := tabX + 8
    width  := tabW - 20
    bottom := tabY + tabH - 10
    lineH  := 15

    ; ---- source box, sized to its contents -----------------------------
    srcW := width
    srcChars := Round(srcW / 6.6)
    if (srcChars < 20)
        srcChars := 20

    text := ""
    try text := MW_QTSource.Value
    lines := MW_WrappedLines(text, srcChars)
    if (lines < 3)
        lines := 3                     ; never smaller than it started
    if (lines > 10)
        lines := 10                    ; past this it scrolls
    srcH := lines * lineH + 8

    y := tabY + 30
    MW_QTLabel.Move(left, y, 60)
    y += 18
    MW_QTSource.Move(left, y, srcW, srcH)
    y += srcH + 10

    ; ---- language row ---------------------------------------------------
    MW_QTFromLbl.Move(left, y + 4, 36)
    MW_QTSrc.Move(left + 40, y, 118)
    MW_QTArrow.Move(left + 164, y + 4, 14)
    MW_QTTgt.Move(left + 182, y, 118)
    MW_QTSwapBtn.Move(left + 306, y - 1, 30, 24)
    MW_QTGoBtn.Move(left + 342, y - 1, 96, 24)
    y += 36

    ; ---- results ---------------------------------------------------------
    resultsTop := y
    boxLeft := left + 130
    boxW    := width - 130
    if (boxW < 120)
        boxW := 120
    perLine := Round(boxW / 6.6)
    if (perLine < 20)
        perLine := 20

    Loop MW_QTRowCtl.Length {
        i := A_Index
        r := MW_QTRowCtl[i]

        if (i > MW_QTRows.Length || y > bottom - 24) {
            r["num"].Visible := false
            r["eng"].Visible := false
            r["mdl"].Visible := false
            r["box"].Visible := false
            continue
        }

        job := MW_QTRows[i]
        switch job["state"] {
            case "pending": rowText := "…"
            case "error":   rowText := "(" job["text"] ")"
            default:        rowText := job["text"]
        }

        rl := MW_WrappedLines(rowText, perLine)
        if (rl > 6)
            rl := 6                    ; past this the field scrolls
        h := rl * lineH + 8
        if (y + h > bottom)
            h := bottom - y
        if (h < lineH + 8)
            h := lineH + 8

        ; A row showing a model name needs room for both label lines, or the
        ; model ends up nearer the next engine than its own and the reader
        ; has to work out which is which.
        model := MW_RowModel(job["engine"])
        if (model != "" && h < 34)
            h := 34

        r["num"].Move(left, y + 2, 18)
        r["num"].Value := (i = MW_QTSel ? "▸" : "") i
        r["eng"].Move(left + 22, y + 2, 104)
        r["eng"].Value := job["engine"]["label"]

        r["mdl"].Move(left + 22, y + 16, 104, 26)
        r["mdl"].Value := model
        r["box"].Move(boxLeft, y, boxW, h)
        r["box"].Value := rowText

        r["num"].Visible := true
        r["eng"].Visible := true
        r["mdl"].Visible := (model != "")
        r["box"].Visible := true

        y += h + 14
    }

    return resultsTop
}

; The model an engine actually used, for the grey line under its name. The
; machine-translation engines have exactly one, so naming it would be noise.
MW_RowModel(engine) {
    id := engine["id"]
    providers := AI_Providers()
    if !providers.Has(id)
        return ""
    return QT_Model(id, providers[id]["default_model"])
}

; Lines a string needs at a given width, counting its own newlines too — a
; character count alone would under-measure a multi-paragraph selection.
MW_WrappedLines(text, perLine) {
    if (text = "")
        return 1
    total := 0
    for part in StrSplit(StrReplace(text, "`r`n", "`n"), "`n") {
        n := Ceil(StrLen(part) / perLine)
        total += (n < 1) ? 1 : n
    }
    return (total < 1) ? 1 : total
}

MW_QTMove(delta) {
    global MW_QTRows, MW_QTSel, MW_QTRowCtl
    if (MW_QTRows.Length = 0)
        return

    target := MW_QTSel + delta
    if (target < 1)
        target := 1
    if (target > MW_QTRows.Length)
        target := MW_QTRows.Length
    if (target = MW_QTSel)
        return

    MW_QTSel := target
    MW_QTMarkRows()

    ; Move the focus ring too, so there is one indicator rather than a marker
    ; on one row and a focus ring stranded on another.
    try MW_QTRowCtl[target]["box"].Focus()
}

; True while the caret is in the source box, so digits and arrows typed there
; reach the text instead of inserting a translation.
MW_EditingSource() {
    global MW_Gui, MW_QTSource
    if (MW_ActiveTab() != 2)
        return false
    try return ControlGetFocus("ahk_id " MW_Gui.Hwnd) = MW_QTSource.Hwnd
    catch
        return false
}

MW_QTInsertRow(n) {
    global MW_QTRows
    if (n < 1 || n > MW_QTRows.Length)
        return
    MW_QTInsert(MW_QTRows[n])
}

MW_QTInsertSelected() {
    global MW_QTRows, MW_QTSel
    if (MW_QTSel < 1 || MW_QTSel > MW_QTRows.Length)
        return
    MW_QTInsert(MW_QTRows[MW_QTSel])
}

; Ctrl+C copies whatever is currently selected — a translation on the
; QuickTrans tab, a clip on the clipboard tab — rather than whatever happens
; to be highlighted inside a control. Anywhere else it falls through to a
; normal copy, so selecting text in the source box and copying still works.
MW_Copy() {
    global MW_QTRows, MW_QTSel, MW_Shown, MW_Clips, MW_Tree

    if (MW_EditingSource() || MW_FocusedIs(MW_Tree)) {
        Send("^c")
        return
    }

    if (MW_ActiveTab() = 2) {
        if (MW_QTSel < 1 || MW_QTSel > MW_QTRows.Length)
            return
        job := MW_QTRows[MW_QTSel]
        if (job["state"] != "done") {
            MW_SetStatus("That row has nothing to copy yet.")
            return
        }
        ; A deliberate copy, so let it enter the clipboard history the way any
        ; other Ctrl+C would.
        A_Clipboard := job["text"]
        MW_SetStatus("Copied " job["engine"]["label"] "'s translation.")
        return
    }

    if MW_FocusedIs(MW_Clips) {
        row := MW_Clips.GetNext(0)
        if (row = 0 || row > MW_Shown.Length)
            return
        A_Clipboard := GetKey(MW_Shown[row], "text", "")
        MW_SetStatus("Copied.")
        return
    }

    Send("^c")
}

MW_QTInsert(job) {
    if (job["state"] != "done")
        return
    text := job["text"]
    MW_Hide()
    MW_ReturnToSource()
    SendText(text)
}

; ---------------------------------------------------------------------------
; Menu pane
; ---------------------------------------------------------------------------
; ~196 nodes cost ~25ms to build, and the menu changes far less often than
; the window is opened.
MW_RefreshTree(force := false) {
    global MW_Tree, MW_Nodes, MW_Sections, MW_Rebuilding
    global MW_Search, SidekickData, SK_MenuRev
    static lastRev := -1
    static lastNeedle := "`n(never)"

    needle := ""
    try needle := Trim(MW_Search.Value)

    if (!force && SK_MenuRev = lastRev && needle == lastNeedle)
        return
    lastRev := SK_MenuRev
    lastNeedle := needle

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
        MW_FillTree(SidekickData["menu"], 0)
    else
        MW_FillFlat(SidekickData["menu"], needle, "")

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

        ; A separator ends the current section. Without this, a section only
        ; ends when the next heading starts, so anything after the LAST
        ; heading gets swallowed into it — which is where "Search everything"
        ; and "Settings" ended up after being moved to the bottom. Every
        ; separator in the data sits at a group boundary, so this is safe.
        if (kind = "separator") {
            section := 0
            continue
        }

        if (kind = "clipboard")
            continue

        ; Chrome that only makes sense in the classic popup: the app title,
        ; and the shortcut to the clipboard window — this window already has
        ; the clipboard in the pane on the left.
        if GetKey(item, "menuonly", false)
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
        if GetKey(item, "menuonly", false)
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

MW_SetStatus(text) {
    global MW_Status
    try MW_Status.Value := text
}

MW_UpdateStatus() {
    global MW_Status, MW_Shown, CB_Items

    ; No "selection:" readout any more — nothing is copied on open, so there
    ; is nothing to report until an entry actually asks for it.
    try MW_Status.Value := MW_Shown.Length " of " CB_Items.Length " clips"
        . "   ·   ↑↓ move  ·  → menu  ·  ← back  ·  Enter use  ·  Esc close"
}

MW_MarkFocus(which) {
    global MW_Status, MW_Rebuilding

    ; Selection churn during a rebuild is not the user moving around.
    if (MW_Rebuilding)
        return

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

    ; Tabs
    Hotkey("^Tab",        (*) => MW_NextTab(),  "On")
    Hotkey("^1",          (*) => MW_GoTab(1),   "On")
    Hotkey("^2",          (*) => MW_GoTab(2),   "On")
    Hotkey("^Enter",      (*) => MW_QTTranslate(), "On")
    Hotkey("^+Enter",     (*) => MW_QTFetchAI(), "On")
    Hotkey("^c",          (*) => MW_Copy(), "On")

    ; Plain digits insert a translation, but only on the QuickTrans tab and
    ; only when the caret is not in the source box.
    Loop 9 {
        d := A_Index
        Hotkey(d "", MW_MakeDigit(d), "On")
    }

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

MW_MakeDigit(n) {
    return (*) => MW_Digit(n)
}

; A digit means three different things depending on where you are: text in
; the source box, a translation to insert on the QuickTrans tab, and a
; character to search for anywhere else.
MW_Digit(n) {
    global MW_Search
    if MW_EditingSource() {
        Send(n "")
        return
    }
    if (MW_ActiveTab() = 2) {
        MW_QTInsertRow(n)
        return
    }
    ; On the clipboard tab a digit is just typing: send it to the search box.
    try {
        MW_Search.Focus()
        Send(n "")
    }
}

MW_GoTab(n) {
    global MW_Tabs
    try MW_Tabs.Value := n
    MW_OnTabChange()
}

MW_NextTab() {
    MW_GoTab(MW_ActiveTab() = 1 ? 2 : 1)
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
    global MW_Search, MW_Tree
    if MW_FocusedIs(MW_Search) {
        MW_FocusClips()
        return
    }
    if (MW_ActiveTab() = 2 && !MW_FocusedIs(MW_Tree) && !MW_EditingSource()) {
        MW_QTMove(1)
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
    if (MW_ActiveTab() = 2 && !MW_FocusedIs(MW_Tree) && !MW_EditingSource()) {
        MW_QTMove(-1)
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
    ; Cross into the tree from either pane — but only from outside it. Without
    ; the second test, Right on the QuickTrans tab re-focuses the tree forever
    ; and never reaches the expanding below.
    if (MW_FocusedIs(MW_Clips)
        || (MW_ActiveTab() = 2 && !MW_FocusedIs(MW_Tree))) {
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
    if (MW_FocusedIs(MW_Clips) || (MW_ActiveTab() = 2 && !MW_FocusedIs(MW_Tree)))
        return

    ; In the tree: close, then climb, then cross back to the left pane.
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
    MW_FocusLeft()
}

; Back to whichever tab is on show, not always the clipboard.
MW_FocusLeft() {
    if (MW_ActiveTab() = 2) {
        MW_FocusResults()
        MW_MarkFocus("clips")
        return
    }
    MW_FocusClips()
}

; Focus belongs on the results, not the source box. The numbered rows exist
; so 1-9 inserts one, and that cannot work while the digits are being typed
; into the source. The source box is one Tab away when it needs editing.
MW_FocusResults() {
    global MW_QTRowCtl, MW_QTRows, MW_QTSource
    if (MW_QTRows.Length > 0 && MW_QTRowCtl.Length > 0) {
        try {
            MW_QTRowCtl[1]["box"].Focus()
            return
        }
    }
    try MW_QTSource.Focus()
}

MW_TogglePane() {
    global MW_Clips, MW_Tree
    if (MW_FocusedIs(MW_Tree))
        MW_FocusLeft()
    else
        MW_FocusTree()
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

    if MW_EditingSource() {
        MW_QTTranslate()
        return
    }
    if MW_FocusedIs(MW_Search) {
        MW_FocusClips()
        return
    }
    if (MW_ActiveTab() = 2 && !MW_FocusedIs(MW_Tree)) {
        MW_QTInsertSelected()
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
    MW_SaveGeometry()
    try MW_Gui.Hide()
    return true
}

; ---------------------------------------------------------------------------
; Remember where the window was and how big, so resizing it is a decision you
; make once rather than every time it opens.
; ---------------------------------------------------------------------------
MW_ShowRestored() {
    global MW_Gui

    x := QT_Int(AI_Ini(SettingsFile(), "Window", "X", ""), -99999)
    y := QT_Int(AI_Ini(SettingsFile(), "Window", "Y", ""), -99999)
    w := QT_Int(AI_Ini(SettingsFile(), "Window", "W", ""), 0)
    h := QT_Int(AI_Ini(SettingsFile(), "Window", "H", ""), 0)

    if (w < 400 || h < 300) {
        MW_Gui.Show("w1040 h620")
        return
    }

    ; Gui.Show scales its arguments by the display's DPI while WinGetPos
    ; reports raw pixels, so saving one and restoring through the other makes
    ; the window grow by the scaling factor every time it is reopened - 25%
    ; a go on a 125% display. Show it first, then place it with WinMove,
    ; which speaks the same raw pixels the geometry was saved in.
    MW_Gui.Show("Hide")

    ; A saved position from a monitor that is no longer attached would put the
    ; window somewhere unreachable.
    if (x = -99999 || y = -99999 || !MW_OnAnyScreen(x, y, w, h)) {
        try WinMove(, , w, h, "ahk_id " MW_Gui.Hwnd)
        MW_Gui.Show()
        return
    }
    try WinMove(x, y, w, h, "ahk_id " MW_Gui.Hwnd)
    MW_Gui.Show()
}

MW_OnAnyScreen(x, y, w, h) {
    ; Just needs the title bar to be somewhere clickable.
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &tp, &r, &b)
        if (x + w > l && x < r && y + 30 > tp && y < b)
            return true
    }
    return false
}

MW_SaveGeometry() {
    global MW_Gui
    if (MW_Gui = "")
        return
    try {
        if (WinGetMinMax("ahk_id " MW_Gui.Hwnd) != 0)
            return              ; do not save a maximised or minimised size
        ; WinGetPos, not Gui.GetPos: raw screen pixels, matching WinMove.
        WinGetPos(&x, &y, &w, &h, "ahk_id " MW_Gui.Hwnd)
        if (w < 400 || h < 300)
            return
        ini := SettingsFile()
        IniWrite(x, ini, "Window", "X")
        IniWrite(y, ini, "Window", "Y")
        IniWrite(w, ini, "Window", "W")
        IniWrite(h, ini, "Window", "H")
    }
}

QT_Int(v, default) {
    v := Trim(v "")
    if (v = "" || !RegExMatch(v, "^-?\d+$"))
        return default
    return v + 0
}

MW_OnSize(thisGui, minMax, width, height) {
    global MW_Search, MW_Clips, MW_Tree, MW_Status
    global MW_Tabs, MW_QTSource
    if (minMax = -1)
        return

    pad   := 12
    gap   := 10
    total := width - pad * 2 - gap
    if (total < 400)
        total := 400
    leftW  := Round(total * 0.56)
    rightW := total - leftW
    h := height - 130
    if (h < 160)
        h := 160

    try {
        MW_Search.Move(, , width - pad * 2 - 50)
        MW_Tabs.Move(, , leftW, h)
        inner := leftW - 16              ; inside the tab control's border

        ; Tab 1
        MW_Clips.Move(, , inner, h - 34)
        MW_Clips.ModifyCol(3, inner - 100)

        ; Tab 2: source box and language row are fixed height, the results
        ; list takes whatever is left.
        MW_QTSource.Move(, , inner - 8)

        MW_Tree.Move(pad + leftW + gap, , rightW, h)
        MW_Status.Move(, , width - pad * 2)
    }
}
