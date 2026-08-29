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
;   clipboard            live submenu of recent clips (see lib/clipboard.ahk)
;   action    func, arg  call a built-in registered via RegisterAction()
;
; Any entry may also set:
;   "barbreak": true   start a new menu column here
;   "bold": true       draw it bold (headings get this automatically)
;   "icon": "Sidekick.ico"    show an icon, path relative to the script folder
;
; Self-contained: everything this module needs is defined here, so it does not
; depend on the ordering or brace structure of the main script.
; ===========================================================================

; Built-in actions that data entries can reference by name.
global SidekickActions := Map()

RegisterAction(name, fn) {
    global SidekickActions
    SidekickActions[name] := fn
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

    ; Windows draws menu items by position, so headings are collected as we go
    ; and styled once the menu is complete.
    headings := []
    pos := 0

    for item in items {
        kind := GetKey(item, "kind", "")

        if (kind = "separator") {
            m.Add()
            pos++
            continue
        }

        label := UniqueMenuLabel(used, GetKey(item, "label", ""))
        opts  := GetKey(item, "barbreak", false) ? "BarBreak" : ""

        switch kind {
            case "submenu":
                sub := Menu()
                PopulateMenu(sub, GetKey(item, "items", []))
                m.Add(label, sub, opts)

            case "clipboard":
                ; A live submenu: its contents are rebuilt from the clipboard
                ; history every time the main menu is opened.
                sub := Menu()
                m.Add(label, sub, opts)
                CB_AttachSubMenu(sub)

            case "heading":
                ; Deliberately NOT disabled. A disabled item is drawn greyed
                ; out by Windows, which made every section title look
                ; unavailable. Left enabled it draws in normal text; clicking
                ; one simply does nothing.
                m.Add(label, (*) => "", opts)
                headings.Push(pos)
                MenuApplyIcon(m, item, label)

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

        ; Any entry can ask to be bold or carry an icon, not just headings.
        if (kind != "heading") {
            MenuApplyIcon(m, item, label)
            if GetKey(item, "bold", false)
                headings.Push(pos)
        }

        pos++
    }

    for p in headings
        MenuItemBold(m, p)
}

MenuApplyIcon(m, item, label) {
    icon := GetKey(item, "icon", "")
    if (icon = "")
        return
    path := InStr(icon, ":") ? icon : A_ScriptDir "\" icon
    if !FileExist(path)
        return
    try m.SetIcon(label, path, GetKey(item, "iconindex", 1))
}

; ---------------------------------------------------------------------------
; Draw a menu item in bold.
;
; Windows renders the menu's "default" item in bold. It documents only one
; default per menu, and SetMenuItemInfo does return ERROR_INVALID_PARAMETER
; for the second and subsequent items — but the MFS_DEFAULT state bit is
; applied to each one regardless, which is what the renderer reads. Failures
; are ignored on purpose: the worst case is a heading drawn in normal text.
; ---------------------------------------------------------------------------
MenuItemBold(menuObj, position) {
    static MIIM_STATE  := 0x0001
    static MFS_DEFAULT := 0x1000
    static SIZE        := (A_PtrSize = 8) ? 80 : 48
    static OFF_STATE   := 12

    try {
        hMenu := menuObj.Handle

        mii := Buffer(SIZE, 0)
        NumPut("UInt", SIZE, mii, 0)
        NumPut("UInt", MIIM_STATE, mii, 4)
        if !DllCall("GetMenuItemInfoW", "Ptr", hMenu, "UInt", position,
                    "Int", 1, "Ptr", mii, "Int")
            return false

        state := NumGet(mii, OFF_STATE, "UInt")

        NumPut("UInt", SIZE, mii, 0)
        NumPut("UInt", MIIM_STATE, mii, 4)
        NumPut("UInt", state | MFS_DEFAULT, mii, OFF_STATE)
        DllCall("SetMenuItemInfoW", "Ptr", hMenu, "UInt", position,
                "Int", 1, "Ptr", mii, "Int")
        return true
    } catch {
        return false
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

; ---------------------------------------------------------------------------
; Run one entry, whatever surface asked for it.
;
; The menu copies the selection at the moment you click. The palette copies it
; when it opens, because by the time you have typed a query the focus has
; moved. So a caller that already has the text passes it in; anything else
; leaves `sel` empty and the entry grabs it live.
; ---------------------------------------------------------------------------
ExecuteEntry(item, sel := "") {
    kind := GetKey(item, "kind", "")

    switch kind {
        case "text":
            SendText(GetKey(item, "value", ""))

        case "keys":
            SendInput(GetKey(item, "value", ""))

        case "url", "run":
            OpenTarget(GetKey(item, "value", ""))

        case "search":
            RunSearch(GetKey(item, "url", ""), GetKey(item, "browser", ""), sel)

        case "ai":
            RunAIEntry(item, sel)

        case "action":
            RunAction(GetKey(item, "func", ""), GetKey(item, "arg", ""))
    }
}

RunAIEntry(item, sel := "") {
    opts := Map()
    for field in ["system", "model", "provider", "effort", "maxtokens",
                  "selection"] {
        v := GetKey(item, field, "")
        if (v != "")
            opts[field] := v
    }
    if (sel != "")
        opts["text"] := sel
    AI_Ask(GetKey(item, "prompt", ""), opts)
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
               "Supervertaler Sidekick", "Icon!")
    }
}

RunSearch(urlTemplate, browser := "", sel := "") {
    if (urlTemplate = "")
        return

    ; A caller that already captured the selection passes it in; the menu
    ; does not, and grabs it at click time.
    query := Trim(sel != "" ? sel : SK_CopySelection())
    if (query = "") {
        MsgBox("Select some text first.", "Supervertaler Sidekick", "Icon! T2")
        return
    }

    url := StrReplace(urlTemplate, "{q}", SK_UriEncode(query))
    try {
        if (browser = "msedge")
            Run('msedge.exe "' url '"')
        else
            Run(url)
    } catch Error as err {
        MsgBox("Could not open the search:`n" url "`n`n" err.Message,
               "Supervertaler Sidekick", "Icon!")
    }
}

RunAction(name, arg := "") {
    global SidekickActions
    if !SidekickActions.Has(name) {
        MsgBox("This menu entry refers to an unknown action: " name,
               "Supervertaler Sidekick", "Icon!")
        return
    }
    fn := SidekickActions[name]
    try {
        if (arg != "")
            fn.Call(arg)
        else
            fn.Call()
    } catch Error as err {
        MsgBox("Action '" name "' failed:`n`n" err.Message,
               "Supervertaler Sidekick", "Icon!")
    }
}

; ---------------------------------------------------------------------------
; Selection and URL helpers.
; ---------------------------------------------------------------------------

; Copy whatever is selected in the foreground window and return it.
; Returns "" if nothing could be copied.
SK_CopySelection(timeoutSec := 1) {
    ; The hotkey that got us here is usually still held down — Ctrl+Alt+T for
    ; QuickTrans, say — and the copy then reaches the app as Ctrl+Alt+C
    ; rather than Ctrl+C. Most apps do nothing with that, so nothing lands on
    ; the clipboard and the window opens empty. Give the fingers a moment to
    ; leave the keys, but only a moment: a key held down on purpose, or stuck,
    ; must not hang the program.
    stop := A_TickCount + 400
    while (A_TickCount < stop
           && (GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
               || GetKeyState("Shift", "P") || GetKeyState("LWin", "P")))
        Sleep(15)

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
SK_UriEncode(str) {
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
                   "Supervertaler Sidekick", "Icon!")
    }
}
