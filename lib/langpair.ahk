#Requires AutoHotkey v2.0
; ===========================================================================
; lib/langpair.ahk — the language pair, and search URLs that know it.
;
; A terminology search is the same URL for every language pair except for the
; two codes in it, yet the menu used to carry "IATE (nl-en)" and "IATE (en-nl)"
; as two entries, and a German translator had to rewrite all of them. Now one
; pair is set for the whole program — the QuickTrans dropdowns, a small dialog
; under Settings, or a swap — and a search URL says {sl} and {tl} where the
; codes go. One IATE entry serves every pair.
;
; The pair is stored where QuickTrans always kept it: SourceLang and
; TargetLang in settings.ini, as language names ("Dutch"). Nothing else is
; tracked; the tray tip repeats it so it is always in view.
;
; Placeholders, matching the ones SuperLookup used so its resource list
; transfers unchanged:
;   {q}            the selected text, percent-encoded ({query} also works)
;   {sl} {tl}      two-letter codes            nl  en
;   {sl_upper}     upper-case two-letter       NL  EN
;   {sl_full}      the English name, lower     dutch  english
;   {sl3} {tl3}    ISO 639-2/T three-letter    nld  eng   (Juremy)
;   {sl3b} {tl3b}  ISO 639-2/B three-letter    dut  eng   (ProZ)
; ===========================================================================

global LP_Src := "Dutch"
global LP_Tgt := "English"

LP_Load() {
    global LP_Src, LP_Tgt
    LP_Src := QT_Setting("SourceLang", "Dutch")
    LP_Tgt := QT_Setting("TargetLang", "English")
    LP_Tip()
}

; Set the pair everywhere it is shown, and remember it.
LP_Set(src, tgt) {
    global LP_Src, LP_Tgt
    if (src = "" || tgt = "" || (src = LP_Src && tgt = LP_Tgt))
        return
    LP_Src := src
    LP_Tgt := tgt
    try {
        IniWrite(src, SettingsFile(), "QuickTrans", "SourceLang")
        IniWrite(tgt, SettingsFile(), "QuickTrans", "TargetLang")
    }
    LP_Tip()
    MW_ShowLangPair(src, tgt)
}

LP_Swap(*) {
    global LP_Src, LP_Tgt
    LP_Set(LP_Tgt, LP_Src)
    TrayTip(LP_Src " → " LP_Tgt, "Language pair", "Iconi")
}

LP_Tip() {
    global LP_Src, LP_Tgt
    A_IconTip := "Supervertaler Sidekick  ·  " LP_Src " → " LP_Tgt
}

LP_PairKey() {
    global LP_Src, LP_Tgt
    return QT_Code(LP_Src) "-" QT_Code(LP_Tgt)
}

; "Chinese (Simplified)" -> "chinese"; the sites that take a name take the
; plain one.
LP_Full(name) {
    return StrLower(Trim(RegExReplace(name, "\s*\(.*\)$", "")))
}

; ISO 639-2. The T column is the one most sites want; the B column exists
; because ProZ still speaks it, and the two differ for exactly these.
LP_Code3(code2, bibliographic := false) {
    static t := Map("nl","nld","en","eng","de","deu","fr","fra","es","spa",
        "it","ita","pt","por","da","dan","sv","swe","no","nor","fi","fin",
        "pl","pol","cs","ces","el","ell","tr","tur","ru","rus","uk","ukr",
        "ro","ron","hu","hun","bg","bul","hr","hrv","sk","slk","sl","slv",
        "et","est","lv","lav","lt","lit","ja","jpn","zh","zho","ko","kor",
        "ar","ara","he","heb","hi","hin","id","ind","vi","vie")
    static b := Map("nl","dut","de","ger","fr","fre","el","gre","cs","cze",
        "ro","rum","sk","slo","zh","chi")
    if (bibliographic && b.Has(code2))
        return b[code2]
    return t.Has(code2) ? t[code2] : code2
}

; Fill a URL template for the current pair and the given text.
LP_Expand(template, query) {
    global LP_Src, LP_Tgt
    sl := QT_Code(LP_Src)
    tl := QT_Code(LP_Tgt)
    q  := SK_UriEncode(query)
    out := template
    for pair in [["{q}", q], ["{query}", q],
                 ["{sl}", sl], ["{tl}", tl],
                 ["{sl_upper}", StrUpper(sl)], ["{tl_upper}", StrUpper(tl)],
                 ["{sl_full}", LP_Full(LP_Src)], ["{tl_full}", LP_Full(LP_Tgt)],
                 ["{sl3}", LP_Code3(sl)], ["{tl3}", LP_Code3(tl)],
                 ["{sl3b}", LP_Code3(sl, true)], ["{tl3b}", LP_Code3(tl, true)]]
        out := StrReplace(out, pair[1], pair[2])
    return out
}

; A search entry's URL for the current pair. Most entries have one "url" with
; placeholders. A site whose pair is baked into an opaque id — Van Dale's
; dictionary names, JurLex's session ids — carries "by_pair" instead: a map
; of "nl-en" -> url. Returns "" when the site has nothing for this pair.
LP_UrlFor(item) {
    bp := GetKey(item, "by_pair", "")
    if (bp is Map) {
        key := LP_PairKey()
        if bp.Has(key)
            return bp[key]
        if (GetKey(item, "url", "") = "")
            return ""
    }
    return GetKey(item, "url", "")
}

; ---------------------------------------------------------------------------
; The dialog: From, To, swap, OK.
; ---------------------------------------------------------------------------
LP_Dialog(*) {
    global LP_Src, LP_Tgt
    g := Gui("+ToolWindow +AlwaysOnTop", "Supervertaler Sidekick — Language pair")
    g.SetFont("s9", "Segoe UI")
    g.Add("Text", "xm ym w360",
          "The pair every search and translation uses. It is also the pair "
          "shown in the QuickTrans tab.")
    g.Add("Text", "xm y+12 w40", "From:")
    src := g.Add("DropDownList", "x+4 yp-3 w150", QT_LangNames())
    swap := g.Add("Button", "x+6 yp w30 h24", "⇄")
    g.Add("Text", "x+6 yp+3 w24", "To:")
    tgt := g.Add("DropDownList", "x+4 yp-3 w150", QT_LangNames())
    LP_Choose(src, LP_Src)
    LP_Choose(tgt, LP_Tgt)
    swap.OnEvent("Click", (*) => (a := src.Text, LP_Choose(src, tgt.Text), LP_Choose(tgt, a)))
    g.Add("Button", "xm y+16 w90 Default", "OK")
        .OnEvent("Click", (*) => (LP_Set(src.Text, tgt.Text), g.Destroy()))
    g.Add("Button", "x+6 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()
}

LP_Choose(ddl, name) {
    for i, n in QT_LangNames() {
        if (n = name) {
            ddl.Choose(i)
            return
        }
    }
}

; ---------------------------------------------------------------------------
; Opening a batch of URLs in one fresh browser window. Chromium browsers take
; every URL on one command line; Firefox takes the first with -new-window and
; the rest with -new-tab. Anything else gets one Run() per URL, which lands
; in the current window — still a batch, just not a separate one.
; ---------------------------------------------------------------------------
SK_OpenInNewWindow(urls, browser := "") {
    if (urls.Length = 0)
        return
    exe := (browser = "msedge") ? "msedge.exe" : SK_DefaultBrowser()
    name := StrLower(exe)
    try {
        if (name ~= "chrome|msedge|brave|vivaldi|opera|chromium") {
            args := "--new-window"
            for u in urls
                args .= ' "' u '"'
            Run('"' exe '" ' args)
        } else if InStr(name, "firefox") {
            Run('"' exe '" -new-window "' urls[1] '"')
            Sleep(800)
            for i, u in urls {
                if (i > 1)
                    Run('"' exe '" -new-tab "' u '"')
            }
        } else {
            for u in urls
                Run(u)
        }
    } catch Error as err {
        MsgBox("Could not open the searches:`n`n" err.Message,
               "Supervertaler Sidekick", "Icon!")
    }
}

; The executable behind the user's https handler, or "" if it cannot be read.
SK_DefaultBrowser() {
    try {
        progId := RegRead("HKCU\Software\Microsoft\Windows\Shell\Associations"
                        . "\UrlAssociations\https\UserChoice", "ProgId")
        cmd := RegRead("HKCR\" progId "\shell\open\command")
        if RegExMatch(cmd, '"([^"]+\.exe)"', &m)
            return m[1]
        if RegExMatch(cmd, "i)^(\S+\.exe)", &m)
            return m[1]
    }
    return ""
}
