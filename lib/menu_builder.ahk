#Requires AutoHotkey v2.0
; ===========================================================================
; lib/menu_builder.ahk — turn data/menu.json into a live AutoHotkey menu.
;
; Entry kinds:
;   separator            a divider line
;   heading              greyed-out, non-clickable label
;   submenu   items[]    nested menu
;   text      value      insert literal text (no key interpretation)
;   keys      value      send a key combination, e.g. "^+*"
;   url       value      open a web address
;   run       value      launch a local file or folder
;   search    url        copy the selection and open url with {q} replaced
;   ai        prompt     run an AI prompt over the selection (see lib/ai.ahk)
;   action    func, arg  call a built-in registered via RegisterAction()
;
; Any entry may set "barbreak": true to start a new menu column.
;
; Self-contained: everything this module needs is defined here, so it does not
; depend on the ordering or brace structure of the main script.
; ===========================================================================

; Built-in actions that data entries can reference by name.
global BeijerBotActions := Map()

RegisterAction(name, fn) {
    global BeijerBotActions
    BeijerBotActions[name] := fn
}

BuildMenuFromData(items) {
    m := Menu()
    PopulateMenu(m, items)
    return m
}

PopulateMenu(m, items) {
    ; AutoHotkey identifies menu items by their text, so two items sharing a
    ; label would collide — the second silently overwrites the first. Track
    ; what we have used and pad duplicates with zero-width spaces, which keeps
    ; them distinct without changing what the user sees.
    used := Map()

    for item in items {
        kind := GetKey(item, "kind", "")

        if (kind = "separator") {
            m.Add()
            continue
        }

        label := UniqueMenuLabel(used, GetKey(item, "label", ""))
        opts  := GetKey(item, "barbreak", false) ? "BarBreak" : ""

        switch kind {
            case "submenu":
                sub := Menu()
                PopulateMenu(sub, GetKey(item, "items", []))
                m.Add(label, sub, opts)

            case "heading":
                m.Add(label, (*) => "", opts)
                m.Disable(label)

            case "text":
                m.Add(label, HandlerText(GetKey(item, "value", "")), opts)

            case "keys":
                m.Add(label, HandlerKeys(GetKey(item, "value", "")), opts)

            case "url":
                m.Add(label, HandlerOpen(GetKey(item, "value", "")), opts)

            case "run":
                m.Add(label, HandlerOpen(GetKey(item, "value", "")), opts)

            case "search":
                m.Add(label, HandlerSearch(GetKey(item, "url", ""),
                                           GetKey(item, "browser", "")), opts)

            case "ai":
                m.Add(label, HandlerAI(item), opts)

            case "action":
                m.Add(label, HandlerAction(GetKey(item, "func", ""),
                                           GetKey(item, "arg", "")), opts)

            default:
                ; Unknown kind — show it disabled rather than dropping it, so a
                ; typo in the data file is visible instead of mysterious.
                m.Add(label " (?)", (*) => "", opts)
                m.Disable(label " (?)")
        }
    }
}

UniqueMenuLabel(used, label) {
    if (label = "")
        label := " "
    while used.Has(label)
        label .= Chr(0x200B)          ; zero-width space
    used[label] := true
    return label
}

; ---------------------------------------------------------------------------
; Handler factories.
;
; Each returns a closure from its own call scope, so every menu item captures
; its own value. Building the closure inline in the loop would make every item
; share the loop variable and act on whatever the last entry happened to be.
; ---------------------------------------------------------------------------
HandlerText(v) {
    return (*) => SendText(v)
}

HandlerKeys(v) {
    return (*) => SendInput(v)
}

HandlerOpen(v) {
    return (*) => OpenTarget(v)
}

HandlerSearch(url, browser) {
    return (*) => RunSearch(url, browser)
}

HandlerAction(name, arg) {
    return (*) => RunAction(name, arg)
}

; AI entries carry their prompt plus optional per-entry overrides (system,
; model, provider, effort), so the whole entry is handed to AI_Ask().
HandlerAI(item) {
    prompt := GetKey(item, "prompt", "")
    opts := Map()
    for field in ["system", "model", "provider", "effort", "maxtokens",
                  "selection"] {
        v := GetKey(item, field, "")
        if (v != "")
            opts[field] := v
    }
    return (*) => AI_Ask(prompt, opts)
}

; ---------------------------------------------------------------------------
OpenTarget(target) {
    try {
        Run(target)
    } catch Error as err {
        MsgBox("Could not open:`n" target "`n`n" err.Message,
               "Beijer.bot", "Icon!")
    }
}

RunSearch(urlTemplate, browser := "") {
    if (urlTemplate = "")
        return

    query := Trim(BB_CopySelection())
    if (query = "") {
        MsgBox("Select some text first.", "Beijer.bot", "Icon! T2")
        return
    }

    url := StrReplace(urlTemplate, "{q}", BB_UriEncode(query))
    try {
        if (browser = "msedge")
            Run('msedge.exe "' url '"')
        else
            Run(url)
    } catch Error as err {
        MsgBox("Could not open the search:`n" url "`n`n" err.Message,
               "Beijer.bot", "Icon!")
    }
}

RunAction(name, arg := "") {
    global BeijerBotActions
    if !BeijerBotActions.Has(name) {
        MsgBox("This menu entry refers to an unknown action: " name,
               "Beijer.bot", "Icon!")
        return
    }
    fn := BeijerBotActions[name]
    try {
        if (arg != "")
            fn.Call(arg)
        else
            fn.Call()
    } catch Error as err {
        MsgBox("Action '" name "' failed:`n`n" err.Message,
               "Beijer.bot", "Icon!")
    }
}

; ---------------------------------------------------------------------------
; Selection and URL helpers.
; ---------------------------------------------------------------------------

; Copy whatever is selected in the foreground window and return it.
; Returns "" if nothing could be copied.
BB_CopySelection(timeoutSec := 1) {
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(timeoutSec, 0)
        return ""
    return A_Clipboard
}

; Percent-encode a string for use in a URL.
;
; The main script's older UriEncode() only replaced spaces, which produced
; broken URLs for any term containing &, ?, +, # or an accented character —
; and Dutch/English terminology hits those constantly. This encodes the text
; as UTF-8 and escapes every byte outside the unreserved set (RFC 3986).
BB_UriEncode(str) {
    static unreserved := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                       . "abcdefghijklmnopqrstuvwxyz"
                       . "0123456789-_.~"

    if (str = "")
        return ""

    size := StrPut(str, "UTF-8")
    buf  := Buffer(size)
    StrPut(str, buf, "UTF-8")

    out := ""
    ; size includes the terminating null, which must not be encoded.
    Loop size - 1 {
        byte := NumGet(buf, A_Index - 1, "UChar")
        char := Chr(byte)
        if (byte < 128 && InStr(unreserved, char, true))
            out .= char
        else
            out .= Format("%{:02X}", byte)
    }
    return out
}

; ---------------------------------------------------------------------------
; Hotstrings declared in the data file, registered at run time.
; ---------------------------------------------------------------------------
RegisterHotstrings(list) {
    for hs in list {
        abbr := GetKey(hs, "abbr", "")
        if (abbr = "")
            continue
        opts := GetKey(hs, "opts", "")
        try
            Hotstring(":" opts ":" abbr, GetKey(hs, "value", ""))
        catch Error as err
            MsgBox("Could not register hotstring '" abbr "':`n`n" err.Message,
                   "Beijer.bot", "Icon!")
    }
}
