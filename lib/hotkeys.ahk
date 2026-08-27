#Requires AutoHotkey v2.0
; ===========================================================================
; lib/hotkeys.ahk — hotkeys read from settings.ini rather than hardcoded.
;
; The backtick that opens the menu is a poor default to impose on everyone:
; on US-International — a common layout for anyone typing Dutch, French or
; German — it is a dead key, waiting to compose à/è/ù. Claiming it globally
; breaks accented typing. On UK and other ISO layouts it also sits somewhere
; different. So every hotkey is configurable, with the current bindings as
; the defaults so nothing changes for an existing install.
; ===========================================================================

; Binding name -> what it does.
HK_Actions() {
    static actions := Map(
        "Menu",          () => ShowMainMenu(132, 164),
        "MenuCentred",   () => ShowMainMenu(),
        "Clipboard",     () => CB_Show(),
        "LibraryEditor", () => OpenLibraryEditor(),
        "GoogleSearch",  () => RunAction("GoogleSearch"),
        "DesktopSearch", () => RunAction("dtSearch"),
        "Reload",        () => Reload()
    )
    return actions
}

; Bindings used when settings.ini says nothing. A backtick has to be written
; as two here because it is AutoHotkey's own escape character.
HK_Defaults() {
    static defaults := Map(
        "Menu",          "``",
        "MenuCentred",   "^``",
        "Clipboard",     "^!c",
        "LibraryEditor", "",        ; off unless the user asks for it
        "GoogleSearch",  "^/",
        "DesktopSearch", "^+d",
        "Reload",        "^r"
    )
    return defaults
}

RegisterConfiguredHotkeys() {
    problems := ""

    for name, action in HK_Actions() {
        binding := Trim(AI_Ini(SettingsFile(), "Hotkeys", name,
                               HK_Defaults()[name]))

        ; An empty value disables the binding — a deliberate choice for
        ; someone whose layout makes the default unusable.
        if (binding = "")
            continue

        try {
            Hotkey(binding, HK_Wrap(action), "On")
        } catch Error as err {
            problems .= "`n  " name " = " binding "   (" err.Message ")"
        }
    }

    if (problems != "")
        MsgBox("These hotkeys in settings.ini could not be registered:"
               problems "`n`nCheck the [Hotkeys] section. The rest of "
               "Beijer.bot is running normally.",
               "Beijer.bot", "Icon!")
}

; Hotkey() hands the callback the hotkey name; the actions take no arguments.
HK_Wrap(action) {
    return (*) => action()
}
