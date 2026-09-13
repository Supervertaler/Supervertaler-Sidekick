#Requires AutoHotkey v2.0
; ===========================================================================
; lib/packs.ahk — language packs: everything a translator in one pair needs.
;
; A pack is one JSON file per language PAIR in packs\ — nl-en.json is Dutch
; and English in both directions — holding the sources for that pair: the
; bilingual dictionaries, the monolingual ones on either side, and a
; MultiSearch that opens the lot at once. One tick installs it. A translator
; who works Dutch and German installs nl-de and nothing else.
;
; A pack is direction-agnostic: its URLs say {sl} and {tl}, so the same file
; serves Dutch → English and English → Dutch, and a source that only exists
; one way carries by_pair. A pack is shown whenever the current pair is its
; pair in either direction, so someone with nl-en and nl-de installed sees
; only the one that applies.
;
; Pack entries are never written into data\menu.json. They are appended to
; the menu at the moment a view builds it (PK_WithPacks), so the Library
; Editor, which edits and saves the real menu, never sees them. Removing a
; pack is one untick, not a hunt through the menu.
;
; Which packs are installed lives in settings.ini [Packs] Installed=nl-en.
; Until that key exists, the pack for the current pair is installed if one
; exists, so a fresh install with Dutch → English gets Dutch ⇄ English
; without being asked.
;
; File format, packs\nl-en.json:
;   { "pair": "nl-en", "name": "Dutch ⇄ English",
;     "entries": [ { "kind": "multisearch", "label": "…", "value": "url\nurl" },
;                  { "kind": "search", "label": "…", "url": "…{q}…{sl}…" },
;                  { "kind": "search", "label": "…", "by_pair": { "nl-en": "…" } } ] }
; ===========================================================================

PK_Dir() => A_ScriptDir "\packs"

; "nl-en" and "en-nl" are the same pack. A pack keeps the pair as its file
; declares it; comparisons ignore direction.
PK_Same(a, b) {
    a := StrLower(Trim(a)), b := StrLower(Trim(b))
    if (a = b)
        return true
    bits := StrSplit(b, "-")
    return (bits.Length = 2) && (a = bits[2] "-" bits[1])
}

; Every pack file on disk: [ Map(pair, name, path, count) ], by name.
PK_Available() {
    packs := []
    Loop Files, PK_Dir() "\*.json" {
        d := LoadJsonFile(A_LoopFileFullPath)
        if !(d is Map)
            continue
        pair := GetKey(d, "pair", "")
        if (pair = "")
            continue
        packs.Push(Map("pair", StrLower(Trim(pair)),
                       "name", GetKey(d, "name", pair),
                       "path", A_LoopFileFullPath,
                       "count", GetKey(d, "entries", []).Length))
    }
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

; Pair keys of the installed packs. Explicit if ever saved; otherwise the
; pack for the current pair, if there is one.
PK_Installed() {
    raw := Trim(AI_Ini(SettingsFile(), "Packs", "Installed", "*"))
    if (raw = "*") {
        for p in PK_Available() {
            if PK_Same(p["pair"], LP_PairKey())
                return [p["pair"]]
        }
        return []
    }
    out := []
    for c in StrSplit(raw, "|") {
        if (Trim(c) != "")
            out.Push(StrLower(Trim(c)))
    }
    return out
}

PK_SaveInstalled(pairs) {
    joined := ""
    for p in pairs
        joined .= (joined = "" ? "" : "|") p
    try IniWrite(joined, SettingsFile(), "Packs", "Installed")
    PK_Invalidate()
}

; The entries to show right now: the installed pack for the current pair,
; minus by_pair entries that have nothing for this direction. Cached per
; (installed, pair), since the main window rebuilds its list as you type.
global PK_CacheKey := ""
global PK_CacheVal := []

PK_Invalidate() {
    global PK_CacheKey
    PK_CacheKey := ""
}

PK_Entries() {
    global PK_CacheKey, PK_CacheVal
    installed := PK_Installed()
    direction := LP_PairKey()
    key := ""
    for p in installed
        key .= p "|"
    key .= "@" direction
    if (key = PK_CacheKey)
        return PK_CacheVal

    out := []
    for p in PK_Available() {
        if !PK_Same(p["pair"], direction)
            continue
        on := false
        for i in installed {
            if PK_Same(i, p["pair"])
                on := true
        }
        if !on
            continue
        d := LoadJsonFile(p["path"])
        if !(d is Map)
            continue
        pair := p["pair"]
        for e in GetKey(d, "entries", []) {
            if !(e is Map)
                continue
            bp := GetKey(e, "by_pair", "")
            if (bp is Map && GetKey(e, "url", "") = "" && !bp.Has(direction))
                continue
            item := e.Clone()
            item["pack"] := pair
            out.Push(item)
        }
    }
    PK_CacheKey := key
    PK_CacheVal := out
    return out
}

; The menu a view should show: the user's own entries, then a Language
; pack section. Returns a new array; the original is never touched.
PK_WithPacks(menu) {
    entries := PK_Entries()
    if (entries.Length = 0)
        return menu
    out := []
    for e in menu
        out.Push(e)
    out.Push(Map("kind", "separator"))
    out.Push(Map("kind", "heading", "label", "LANGUAGE PACK:"))
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
    g.Add("Text", "xm ym w400",
          "A language pack is everything for one pair, both directions: the "
          "dictionaries and term sites, and a MultiSearch that opens them all "
          "at once. Tick the pairs you work in. The pack for the current pair "
          "(" LP_Src " → " LP_Tgt ") is the one shown on the menu.")
    if (packs.Length = 0)
        g.Add("Text", "xm y+12 w400 cGray", "No packs found in " PK_Dir())
    installed := PK_Installed()
    boxes := []
    for p in packs {
        on := false
        for c in installed {
            if PK_Same(c, p["pair"])
                on := true
        }
        cb := g.Add("CheckBox", "xm y+8 w400" (on ? " Checked" : ""),
                    p["name"] "   (" p["count"] " source" (p["count"] = 1 ? "" : "s") ")")
        boxes.Push(Map("box", cb, "pair", p["pair"]))
    }
    g.Add("Text", "xm y+12 w400 cGray",
          "Packs are files in packs\. Add a pair by dropping a file there "
          "and reopening this window.")
    g.Add("Button", "xm y+14 w90 Default", "OK").OnEvent("Click", Done)
    g.Add("Button", "x+6 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()

    Done(*) {
        pairs := []
        for b in boxes {
            if b["box"].Value
                pairs.Push(b["pair"])
        }
        PK_SaveInstalled(pairs)
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
