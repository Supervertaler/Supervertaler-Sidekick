#Requires AutoHotkey v2.0
; ===========================================================================
; lib/shortcuts.ahk — shortcuts you make yourself.
;
; A keyboard shortcut is two halves: a key to press, and something for it to
; do. The built-in ones in lib/hotkeys.ahk have the second half compiled in —
; "Confirm segment" sends Ctrl+Enter and there is no way to see that, let
; alone change it. These are the other kind: both halves are data, so the
; list can grow without touching the program.
;
; The "something to do" is an ordinary library entry — the same kinds the
; menu uses, run through the same ExecuteEntry. So a shortcut is a menu entry
; with a key attached, and learning one editor teaches the other.
; ===========================================================================

global SC_Items := []

SC_Path() => DataFile("shortcuts.json")

; ---------------------------------------------------------------------------
SC_Load() {
    global SC_Items

    SC_Items := []
    data := LoadJsonFile(SC_Path())
    if !(data is Map)
        return SC_Items

    for e in GetKey(data, "shortcuts", []) {
        if !(e is Map)
            continue
        SC_Items.Push(Map(
            "label",  GetKey(e, "label", ""),
            "key",    GetKey(e, "key", ""),
            "kind",   GetKey(e, "kind", "keys"),
            "value",  GetKey(e, "value", ""),
            "url",    GetKey(e, "url", ""),
            "func",   GetKey(e, "func", ""),
            "before", GetKey(e, "before", ""),
            "after",  GetKey(e, "after", "")))
    }
    return SC_Items
}

SC_SaveItems(items) {
    out := []
    for e in items {
        row := Map("label", e["label"], "key", e["key"], "kind", e["kind"])
        ; Only carry the fields the kind actually uses, so the file stays
        ; readable by hand.
        for f in SC_FieldsFor(e["kind"])
            row[f] := e[f]
        out.Push(row)
    }
    EnsureDataDir()
    SaveJsonFile(SC_Path(), Map("version", 1, "shortcuts", out))
}

; ---------------------------------------------------------------------------
; The kinds, in the words the editor shows.
; ---------------------------------------------------------------------------
SC_Kinds() {
    static kinds := [
        Map("kind", "keys",   "label", "Press keys"),
        Map("kind", "text",   "label", "Type text"),
        Map("kind", "wrap",   "label", "Surround the selection"),
        Map("kind", "search", "label", "Search the web for the selection"),
        Map("kind", "url",    "label", "Open a web page"),
        Map("kind", "run",    "label", "Run a program"),
        Map("kind", "action", "label", "Run a built-in action")
    ]
    return kinds
}

SC_KindLabel(kind) {
    for k in SC_Kinds() {
        if (k["kind"] = kind)
            return k["label"]
    }
    return kind
}

; Which fields a kind stores, so the editor knows what to ask for.
SC_FieldsFor(kind) {
    switch kind {
        case "wrap":   return ["before", "after"]
        case "search": return ["url"]
        case "action": return ["func"]
        default:       return ["value"]
    }
}

; ---------------------------------------------------------------------------
; What a shortcut does, in a sentence, for the "Does" column. The whole point
; of this module is that this is answerable at all.
; ---------------------------------------------------------------------------
SC_Describe(item) {
    kind := GetKey(item, "kind", "")

    switch kind {
        case "keys":
            v := GetKey(item, "value", "")
            return (v = "") ? "presses nothing" : "presses " HK_Display(v)
        case "text":
            return "types " SC_Quote(GetKey(item, "value", ""))
        case "wrap":
            return "surrounds the selection with "
                 . SC_Quote(GetKey(item, "before", "")) " and "
                 . SC_Quote(GetKey(item, "after", ""))
        case "search":
            return "searches " SC_Host(GetKey(item, "url", ""))
                 . " for the selection"
        case "url":
            return "opens " SC_Host(GetKey(item, "value", ""))
        case "run":
            return "runs " SC_Short(GetKey(item, "value", ""), 40)
        case "action":
            return "runs the built-in " GetKey(item, "func", "")
    }
    return kind
}

SC_Quote(t) {
    t := StrReplace(StrReplace(t, "`r`n", " "), "`n", " ")
    return Chr(0x201C) SC_Short(t, 30) Chr(0x201D)
}

; Just the site, since a search template is mostly query string.
SC_Host(url) {
    if RegExMatch(url, "^[a-z]+://([^/]+)", &m)
        return RegExReplace(m[1], "^www\.", "")
    return SC_Short(url, 30)
}

SC_Short(t, n) {
    return (StrLen(t) > n) ? SubStr(t, 1, n) Chr(0x2026) : t
}

; ---------------------------------------------------------------------------
; Registration. The key half understands everything HK_Apply does: several
; keys separated by "|", and key@window to limit one to an application.
; ---------------------------------------------------------------------------
SC_Apply(items) {
    problems := ""

    for item in items {
        raw := Trim(GetKey(item, "key", ""))
        if (raw = "")
            continue

        for piece in StrSplit(raw, "|") {
            parsed := HK_ParseBinding(piece)
            if (parsed["key"] = "")
                continue
            try {
                HK_Scope(parsed["window"])
                Hotkey(parsed["key"], SC_Wrap(item), "On")
            } catch Error as err {
                problems .= "`n  " GetKey(item, "label", "(unnamed)")
                         . "  ->  " Trim(piece) "   (" err.Message ")"
            }
        }
    }
    HotIf()
    return problems
}

; A closure per shortcut, so each one keeps its own entry.
SC_Wrap(item) {
    return (*) => ExecuteEntry(item)
}

RegisterUserShortcuts() {
    problems := SC_Apply(SC_Load())
    if (problems != "")
        MsgBox("These shortcuts of yours could not be registered:" problems
               "`n`nOpen “Keyboard shortcuts…” to fix them.",
               "Supervertaler Sidekick", "Icon!")
}
