#Requires AutoHotkey v2.0
; ===========================================================================
; lib/packs.ahk — language packs: the sources that belong to one language.
;
; After lib/langpair.ahk the pair-agnostic sources (IATE, Linguee, ProZ,
; Reverso, Wikipedia…) already serve every pair. What differs per language is
; the rest: Van Dale and Woordenlijst for Dutch, Duden for German, Larousse
; for French. A pack is one JSON file per LANGUAGE in packs\, not per pair —
; twenty files to keep, not four hundred — and a pack is shown whenever its
; language is the source or the target of the current pair.
;
; Pack entries are never written into data\menu.json. They are appended to
; the menu at the moment a view builds it (PK_WithPacks), so the Library
; Editor, which edits and saves the real menu, never sees them. Removing a
; pack is a tick in a dialog, not a hunt through the menu.
;
; Which packs are installed lives in settings.ini [Packs] Installed=nl|en.
; Until that key exists the packs for the two languages of the current pair
; are used, so a fresh install with Dutch → English gets Dutch and English
; without being asked.
;
; File format, packs\nl.json:
;   { "language": "nl", "name": "Dutch",
;     "entries": [ { "kind": "search", "label": "…", "url": "…{q}…{sl}…" },
;                  { "kind": "search", "label": "…", "by_pair": { "nl-en": "…" } } ] }
; ===========================================================================

PK_Dir() => A_ScriptDir "\packs"

; Every pack file on disk: [ Map(code, name, path, count) ], by name.
PK_Available() {
    packs := []
    Loop Files, PK_Dir() "\*.json" {
        d := LoadJsonFile(A_LoopFileFullPath)
        if !(d is Map)
            continue
        code := GetKey(d, "language", "")
        if (code = "")
            continue
        packs.Push(Map("code", code,
                       "name", GetKey(d, "name", code),
                       "path", A_LoopFileFullPath,
                       "count", GetKey(d, "entries", []).Length))
    }
    ; Sort by name so the dialog reads as a list of languages.
    n := packs.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (StrCompare(packs[j]["name"], packs[j + 1]["name"]) > 0) {
                t := packs[j], packs[j] := packs[j + 1], packs[j + 1] := t
            }
        }
    }
    return packs
}

; Codes of the installed packs. Explicit if ever saved; otherwise the two
; languages of the current pair.
PK_Installed() {
    raw := Trim(AI_Ini(SettingsFile(), "Packs", "Installed", "*"))
    if (raw = "*") {
        global LP_Src, LP_Tgt
        return [QT_Code(LP_Src), QT_Code(LP_Tgt)]
    }
    out := []
    for c in StrSplit(raw, "|") {
        if (Trim(c) != "")
            out.Push(Trim(c))
    }
    return out
}

PK_SaveInstalled(codes) {
    joined := ""
    for c in codes
        joined .= (joined = "" ? "" : "|") c
    try IniWrite(joined, SettingsFile(), "Packs", "Installed")
    PK_Invalidate()
}

; The entries to show right now: installed packs whose language is in the
; pair, minus by_pair entries that have nothing for this pair. Cached per
; (installed, pair), since the main window rebuilds its list as you type.
global PK_CacheKey := ""
global PK_CacheVal := []

PK_Invalidate() {
    global PK_CacheKey
    PK_CacheKey := ""
}

PK_Entries() {
    global PK_CacheKey, PK_CacheVal, LP_Src, LP_Tgt
    installed := PK_Installed()
    key := ""
    for c in installed
        key .= c "|"
    key .= "@" LP_PairKey()
    if (key = PK_CacheKey)
        return PK_CacheVal

    sl := QT_Code(LP_Src), tl := QT_Code(LP_Tgt)
    pair := LP_PairKey()
    out := []
    for code in installed {
        if (code != sl && code != tl)
            continue
        d := LoadJsonFile(PK_Dir() "\" code ".json")
        if !(d is Map)
            continue
        for e in GetKey(d, "entries", []) {
            if !(e is Map)
                continue
            bp := GetKey(e, "by_pair", "")
            if (bp is Map && GetKey(e, "url", "") = "" && !bp.Has(pair))
                continue
            item := e.Clone()
            item["pack"] := code
            out.Push(item)
        }
    }
    PK_CacheKey := key
    PK_CacheVal := out
    return out
}

; The menu a view should show: the user's own entries, then a Language
; packs section. Returns a new array; the original is never touched.
PK_WithPacks(menu) {
    entries := PK_Entries()
    if (entries.Length = 0)
        return menu
    out := []
    for e in menu
        out.Push(e)
    out.Push(Map("kind", "separator"))
    out.Push(Map("kind", "heading", "label", "LANGUAGE PACKS:"))
    for e in entries
        out.Push(e)
    return out
}

; ---------------------------------------------------------------------------
; The dialog: one checkbox per pack file.
; ---------------------------------------------------------------------------
PK_Dialog(*) {
    global LP_Src, LP_Tgt
    packs := PK_Available()
    g := Gui("+ToolWindow +AlwaysOnTop", "Supervertaler Sidekick — Language packs")
    g.SetFont("s9", "Segoe UI")
    g.Add("Text", "xm ym w380",
          "A pack is the sources that belong to one language – dictionaries, "
          "term banks, lexica. Installed packs appear on the menu under "
          "Language packs whenever their language is in the current pair "
          "(" LP_Src " → " LP_Tgt ").")
    if (packs.Length = 0) {
        g.Add("Text", "xm y+12 w380 cGray", "No packs found in " PK_Dir())
    }
    installed := PK_Installed()
    boxes := []
    for p in packs {
        on := false
        for c in installed {
            if (c = p["code"])
                on := true
        }
        cb := g.Add("CheckBox", "xm y+8 w380" (on ? " Checked" : ""),
                    p["name"] "   (" p["count"] " source" (p["count"] = 1 ? "" : "s") ")")
        boxes.Push(Map("box", cb, "code", p["code"]))
    }
    g.Add("Text", "xm y+12 w380 cGray",
          "Packs are files in packs\. Add a language by dropping a file "
          "there and reopening this window.")
    g.Add("Button", "xm y+14 w90 Default", "OK").OnEvent("Click", Done)
    g.Add("Button", "x+6 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()

    Done(*) {
        codes := []
        for b in boxes {
            if b["box"].Value
                codes.Push(b["code"])
        }
        PK_SaveInstalled(codes)
        g.Destroy()
        PK_Refresh()
    }
}

; Every view that shows the menu rebuilds from PK_WithPacks, keyed on
; SK_MenuRev; bumping it and rebuilding the popup is all a change needs.
PK_Refresh() {
    global SK_MenuRev
    PK_Invalidate()
    SK_MenuRev++
    try ReloadSidekickMenu()
}
