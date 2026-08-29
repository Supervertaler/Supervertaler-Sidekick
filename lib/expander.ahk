#Requires AutoHotkey v2.0
; ===========================================================================
; lib/expander.ahk — text expansion: type an abbreviation, get the full text.
;
; This is the one feature that has to be fast on every keystroke of every day,
; and there are thousands of entries. Registering them at runtime with
; Hotstring() costs 2.2 seconds for 5,500; the same 5,500 written into the
; script as static hotstrings cost about 15ms. So the entries live in
; data/expansions.json, where they can be edited, and a generated .ahk is
; written from that file and included. Editing costs one reload; typing costs
; nothing.
;
; Not to be confused with text conversions, which act on text you have already
; selected. Expansion watches what you type and has no selection at all.
; ===========================================================================

global EX_Entries := []
global EX_Gui     := ""
global EX_List    := ""
global EX_Search  := ""
global EX_Status  := ""
global EX_Shown   := []

EX_Path()    => DataFile("expansions.json")
EX_GenPath() => DataFile("expansions.gen.ahk")

; ---------------------------------------------------------------------------
; Loading and saving
; ---------------------------------------------------------------------------
EX_Load() {
    global EX_Entries

    EX_Entries := []
    data := LoadJsonFile(EX_Path())
    if !(data is Map)
        return EX_Entries

    for e in GetKey(data, "entries", []) {
        if !(e is Map)
            continue
        trigger := Trim(GetKey(e, "trigger", ""))
        if (trigger = "")
            continue
        EX_Entries.Push(Map(
            "trigger", trigger,
            "text",    GetKey(e, "text", ""),
            "options", GetKey(e, "options", "")
        ))
    }
    return EX_Entries
}

EX_Save() {
    global EX_Entries

    out := []
    for e in EX_Entries {
        out.Push(Map("trigger", e["trigger"],
                     "text",    e["text"],
                     "options", e["options"]))
    }
    EnsureDataDir()
    SaveJsonFile(EX_Path(), Map("version", 1, "entries", out))
}

; ---------------------------------------------------------------------------
; Generating the script
;
; A replacement is literal text in a hotstring, so anything AutoHotkey would
; read as syntax has to be escaped: the backtick that does the escaping, the
; newline and tab it can encode, and a semicolon, which would otherwise start
; a comment. Leading and trailing spaces need `s or they are trimmed away.
; ---------------------------------------------------------------------------
EX_EscapeText(t) {
    t := StrReplace(t, "``", "````")
    t := StrReplace(t, "`r`n", "`n")
    t := StrReplace(t, "`r", "`n")
    t := StrReplace(t, "`n", "``n")
    t := StrReplace(t, "`t", "``t")
    t := StrReplace(t, ";", "``;")

    ; Spaces at either end survive only as an escape.
    while (SubStr(t, 1, 1) = " ")
        t := "``s" SubStr(t, 2)
    while (SubStr(t, -1) = " ")
        t := SubStr(t, 1, StrLen(t) - 1) "``s"
    return t
}

; For the few entries that are code rather than text, the replacement becomes
; an argument to EX_Expand and needs string-literal escaping instead.
EX_EscapeArg(t) {
    t := StrReplace(t, "``", "````")
    t := StrReplace(t, '"', '""')
    t := StrReplace(t, "`r`n", "`n")
    t := StrReplace(t, "`r", "`n")
    t := StrReplace(t, "`n", "``n")
    t := StrReplace(t, "`t", "``t")
    return t
}

; {date}, {time} and {clipboard} are worked out as you type, so those entries
; cannot be plain text and are written as code instead.
EX_IsDynamic(text) {
    return RegExMatch(text, "\{(date|time|clipboard)(:[^}]*)?\}") > 0
}

; A trigger has to survive being written between two colons.
EX_ValidTrigger(trigger) {
    if (trigger = "")
        return false
    if InStr(trigger, ":")
        return false
    if InStr(trigger, "`n") || InStr(trigger, "`r")
        return false
    return true
}

; Returns a Map: "ok", "written" (count), "skipped" (array of triggers).
EX_Generate() {
    global EX_Entries

    lines := []
    lines.Push("; Generated from data/expansions.json — do not edit by hand.")
    lines.Push("; Anything changed here is lost the next time it is written.")
    lines.Push("")

    skipped := []
    written := 0
    seen := Map()

    for e in EX_Entries {
        trigger := e["trigger"]
        if !EX_ValidTrigger(trigger) {
            skipped.Push(trigger)
            continue
        }

        opts := RegExReplace(e["options"], "[^A-Za-z0-9*?]", "")
        key := opts "|" trigger
        ; A repeated trigger is a load-time error in AutoHotkey, so the second
        ; one is dropped rather than allowed to break the whole script.
        if seen.Has(key) {
            skipped.Push(trigger)
            continue
        }
        seen[key] := true

        if EX_IsDynamic(e["text"]) {
            lines.Push(":" opts ":" trigger "::")
            lines.Push("{")
            lines.Push('    EX_Expand("' EX_EscapeArg(e["text"]) '")')
            lines.Push("}")
        } else {
            lines.Push(":" opts ":" trigger "::" EX_EscapeText(e["text"]))
        }
        written++
    }

    try {
        EnsureDataDir()
        path := EX_GenPath()
        if FileExist(path)
            FileDelete(path)
        FileAppend(EX_Join(lines) "`r`n", path, "UTF-8")
    } catch Error as err {
        return Map("ok", false, "written", 0, "skipped", skipped,
                   "error", err.Message)
    }

    return Map("ok", true, "written", written, "skipped", skipped,
               "error", "")
}

EX_Join(lines) {
    out := ""
    for l in lines
        out .= (out = "" ? "" : "`r`n") l
    return out
}

; ---------------------------------------------------------------------------
; The dynamic ones, worked out at the moment of typing.
; ---------------------------------------------------------------------------
EX_Expand(template) {
    text := template

    while RegExMatch(text, "\{date(?::([^}]*))?\}", &m) {
        fmt := (m.Count >= 1 && m[1] != "") ? m[1] : "yyyy-MM-dd"
        text := StrReplace(text, m[0], FormatTime(, fmt), , , 1)
    }
    while RegExMatch(text, "\{time(?::([^}]*))?\}", &m) {
        fmt := (m.Count >= 1 && m[1] != "") ? m[1] : "HH:mm"
        text := StrReplace(text, m[0], FormatTime(, fmt), , , 1)
    }
    if InStr(text, "{clipboard}")
        text := StrReplace(text, "{clipboard}", A_Clipboard)

    SendText(text)
}

; ---------------------------------------------------------------------------
; Startup
;
; The generated script is included, so it has to exist before the script
; loads. When the data has moved on since it was last written, rewrite it and
; reload — once: the rewrite makes the generated file the newer of the two, so
; the next start finds nothing to do.
; ---------------------------------------------------------------------------
EX_EnsureFresh() {
    if !FileExist(EX_Path())
        return
    if !EX_Stale()
        return

    EX_Load()
    r := EX_Generate()
    if (!r["ok"] || EX_Stale())
        return                  ; do not reload into the same staleness

    Reload()
}

EX_Stale() {
    if !FileExist(EX_GenPath())
        return true
    try
        return FileGetTime(EX_Path(), "M") > FileGetTime(EX_GenPath(), "M")
    catch
        return false
}

; ===========================================================================
; The editor
; ===========================================================================
OpenExpansionEditor(*) {
    global EX_Gui, EX_List, EX_Search, EX_Status

    if (EX_Gui != "") {
        EX_Gui.Show()
        return
    }

    EX_Load()

    EX_Gui := Gui("+Resize +MinSize640x460", "Supervertaler Sidekick — Text expansion")
    EX_Gui.SetFont("s9", "Segoe UI")
    EX_Gui.OnEvent("Close", EX_Close)
    EX_Gui.OnEvent("Escape", EX_Close)

    ; A new user has no way to tell this from text conversions unless told.
    EX_Gui.SetFont("s9 Bold")
    EX_Gui.Add("Text", "xm ym w700", "Type an abbreviation, get the full text.")
    EX_Gui.SetFont("s9 Norm")
    EX_Gui.Add("Text", "xm y+2 w700",
               "These fire as you type, anywhere on the computer — no "
               "selection involved. That is what makes them different from "
               "Text conversions, which change text you have already "
               "selected.")

    EX_Gui.Add("Text", "xm y+10 w46", "Search:")
    EX_Search := EX_Gui.Add("Edit", "x+6 yp-3 w400")
    EX_Search.OnEvent("Change", (*) => EX_Refresh())

    EX_List := EX_Gui.Add("ListView", "xm y+8 w700 h340 -Multi",
                          ["Type this", "Get this", "When"])
    EX_List.OnEvent("DoubleClick", (*) => EX_Edit())

    EX_Gui.Add("Button", "xm y+8 w90 h26", "Add…")
        .OnEvent("Click", (*) => EX_Add())
    EX_Gui.Add("Button", "x+6 yp w90 h26", "Edit…")
        .OnEvent("Click", (*) => EX_Edit())
    EX_Gui.Add("Button", "x+6 yp w90 h26", "Delete")
        .OnEvent("Click", (*) => EX_Delete())
    EX_Gui.Add("Button", "x+40 yp w150 h26 Default", "Save and apply")
        .OnEvent("Click", (*) => EX_Apply())
    EX_Gui.Add("Button", "x+6 yp w90 h26", "Close")
        .OnEvent("Click", (*) => EX_Close())

    EX_Status := EX_Gui.Add("Text", "xm y+10 w700", "")
    EX_Refresh()
    EX_Gui.Show("w730 h560")
}

; Plain words for the option letters, because ":?*:" means nothing to anyone
; who has not read the AutoHotkey documentation.
EX_WhenText(opts) {
    parts := []
    if InStr(opts, "*")
        parts.Push("at once")
    else
        parts.Push("after a space")
    if InStr(opts, "?")
        parts.Push("inside words too")
    if InStr(opts, "C")
        parts.Push("capitals must match")
    if InStr(opts, "O")
        parts.Push("swallows the space")

    out := ""
    for p in parts
        out .= (out = "" ? "" : ", ") p
    return out
}

EX_Refresh() {
    global EX_List, EX_Search, EX_Entries, EX_Shown, EX_Status

    filter := ""
    try filter := Trim(EX_Search.Value)

    EX_List.Opt("-Redraw")
    EX_List.Delete()
    EX_Shown := []

    for e in EX_Entries {
        if (filter != ""
            && !InStr(e["trigger"], filter, false)
            && !InStr(e["text"], filter, false))
            continue
        EX_Shown.Push(e)
        EX_List.Add(, e["trigger"], EX_Preview(e["text"]),
                    EX_WhenText(e["options"]))
        if (EX_Shown.Length >= 2000)
            break               ; the list is for finding things, not browsing
    }

    EX_List.ModifyCol(1, 140)
    EX_List.ModifyCol(2, 380)
    EX_List.ModifyCol(3, 150)
    EX_List.Opt("+Redraw")

    shown := EX_Shown.Length
    total := EX_Entries.Length
    EX_Status.Value := (shown = total)
        ? total " expansions"
        : "showing " shown " of " total
        . (shown >= 2000 ? " — narrow the search to see the rest" : "")
}

EX_Preview(text) {
    t := StrReplace(StrReplace(text, "`r`n", " "), "`n", " ")
    t := RegExReplace(t, "\s+", " ")
    return (StrLen(t) > 90) ? SubStr(t, 1, 90) "…" : t
}

EX_Selected() {
    global EX_List, EX_Shown
    row := EX_List.GetNext(0)
    if (row < 1 || row > EX_Shown.Length)
        return ""
    return EX_Shown[row]
}

EX_Add() {
    global EX_Entries
    e := EX_Dialog(Map("trigger", "", "text", "", "options", ""))
    if (e = "")
        return
    EX_Entries.InsertAt(1, e)
    EX_Refresh()
}

EX_Edit() {
    entry := EX_Selected()
    if (entry = "")
        return
    e := EX_Dialog(entry)
    if (e = "")
        return
    entry["trigger"] := e["trigger"]
    entry["text"]    := e["text"]
    entry["options"] := e["options"]
    EX_Refresh()
}

EX_Delete() {
    global EX_Entries
    entry := EX_Selected()
    if (entry = "")
        return
    if (MsgBox("Delete the expansion for “" entry["trigger"] "”?",
               "Supervertaler Sidekick", "YesNo Icon?") != "Yes")
        return
    for i, e in EX_Entries {
        if (e == entry) {
            EX_Entries.RemoveAt(i)
            break
        }
    }
    EX_Refresh()
}

; One entry, in plain language. Returns a Map, or "" if cancelled.
EX_Dialog(entry) {
    result := ""

    g := Gui("+Owner" (EX_Gui != "" ? EX_Gui.Hwnd : "") " -MinimizeBox",
             "Supervertaler Sidekick — Expansion")
    g.SetFont("s9", "Segoe UI")

    g.Add("Text", "xm ym w120", "When I type:")
    trig := g.Add("Edit", "xm y+2 w200", entry["trigger"])

    g.Add("Text", "xm y+12 w460", "Replace it with:")
    body := g.Add("Edit", "xm y+2 w460 h140 Multi WantTab", entry["text"])

    g.Add("Text", "xm y+6 w460 cGray",
          "{date} and {time} are filled in as you type. Add a format if you "
          "want one: {date:dd MMMM yyyy}. {clipboard} pastes the clipboard.")

    opts := entry["options"]
    cbNow := g.Add("CheckBox", "xm y+12 w460",
                   "Expand at once, without waiting for a space")
    cbNow.Value := InStr(opts, "*") ? 1 : 0
    cbIn := g.Add("CheckBox", "xm y+4 w460",
                  "Expand inside longer words too")
    cbIn.Value := InStr(opts, "?") ? 1 : 0
    cbCase := g.Add("CheckBox", "xm y+4 w460",
                    "Capitals must match exactly")
    cbCase.Value := InStr(opts, "C") ? 1 : 0

    g.Add("Button", "xm y+16 w100 h26 Default", "OK")
        .OnEvent("Click", (*) => Done(true))
    g.Add("Button", "x+6 yp w100 h26", "Cancel")
        .OnEvent("Click", (*) => Done(false))
    g.OnEvent("Close", (*) => Done(false))
    g.OnEvent("Escape", (*) => Done(false))

    Done(ok) {
        if ok {
            t := Trim(trig.Value)
            if (t = "") {
                MsgBox("Give it something to type.", "Supervertaler Sidekick", "Icon!")
                return
            }
            if !EX_ValidTrigger(t) {
                MsgBox("An abbreviation cannot contain a colon or a line "
                     . "break.", "Supervertaler Sidekick", "Icon!")
                return
            }
            ; Anything the dialog does not offer — the rarer flags — is kept
            ; so editing an entry never silently drops what it had.
            keep := RegExReplace(entry["options"], "[*?C]", "")
            o := keep
            o .= cbNow.Value ? "*" : ""
            o .= cbIn.Value ? "?" : ""
            o .= cbCase.Value ? "C" : ""
            result := Map("trigger", t, "text", body.Value, "options", o)
        }
        g.Destroy()
    }

    g.Show()
    WinWaitClose("ahk_id " g.Hwnd)
    return result
}

; Write the data, rewrite the script, and restart so it takes effect.
EX_Apply() {
    global EX_Status

    try
        EX_Save()
    catch Error as err {
        MsgBox("Could not save:`n`n" err.Message, "Supervertaler Sidekick", "Icon!")
        return
    }

    r := EX_Generate()
    if !r["ok"] {
        MsgBox("Could not write the expansions:`n`n" r["error"],
               "Supervertaler Sidekick", "Icon!")
        return
    }

    note := r["written"] " expansions written."
    if (r["skipped"].Length > 0)
        note .= " " r["skipped"].Length " skipped as duplicates or "
              . "unusable abbreviations."
    EX_Status.Value := note

    if (MsgBox(note "`n`nSupervertaler Sidekick has to restart for them to take "
             . "effect. Restart now?", "Supervertaler Sidekick", "YesNo Icon?")
        = "Yes")
        Reload()
}

EX_Close(*) {
    global EX_Gui
    try EX_Gui.Destroy()
    EX_Gui := ""
    return true
}
