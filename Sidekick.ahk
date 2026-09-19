/*
====================================================
Information:

; The AI request handling began as https://github.com/kdalanon/ChatGPT-AutoHotkey-Utility
; and has since been rewritten as a provider-agnostic layer (see lib\ai.ahk).
; Info @ https://github.com/michaelbeijer/Beijer.bot
====================================================
*/
#Requires AutoHotkey v2.0



#SingleInstance
#Include "lib\jxon.ahk"
#Include "lib\sharedkeys.ahk"
#Include "lib\data.ahk"
#Include "lib\menu_builder.ahk"
#Include "lib\ai.ahk"
#Include "lib\clipboard.ahk"
#Include "lib\palette.ahk"
#Include "lib\mainwindow.ahk"
#Include "lib\quicktrans.ahk"
#Include "lib\scratchpad.ahk"
#Include "lib\langpair.ahk"
#Include "lib\packs.ahk"
#Include "lib\hotkeys.ahk"
#Include "lib\shortcuts.ahk"
#Include "lib\editor.ahk"
#Include "lib\providers.ahk"
#Include "lib\expander.ahk"
; Generated from data/expansions.json. Optional, because a fresh install has
; not written one yet and the script still has to start so the editor can
; create it.
;
; NOT quoted, and that is not a style choice. #Include accepts a quoted path,
; but #Include *i does not: it takes the quotes as part of the filename, finds
; nothing, and then — this being the whole point of *i — says nothing at all.
; Every expansion was silently dead for as long as the quotes were there.
#Include *i data\expansions.gen.ahk
Persistent
SyncTrayIcon()

; The tray sits on the taskbar, and the taskbar follows SystemUsesLightTheme
; - NOT AppsUseLightTheme, which governs application windows and is commonly
; set the other way round from it. The value is absent on builds that predate
; the setting, so a missing value is treated as light.
;
; Windows broadcasts WM_SETTINGCHANGE when the theme is switched, so the icon
; can follow it without a timer polling the registry. The static guard means
; the icon is only actually swapped when it changes - that message fires for
; every kind of setting change, not only this one.
SyncTrayIcon(*) {
    static showing := ""
    key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    want := RegRead(key, "SystemUsesLightTheme", 1) ? "Sidekick.ico" : "Sidekick-on-dark.ico"
    if (want = showing)
        return
    showing := want
    TraySetIcon(A_ScriptDir "\" want)
}
OnMessage(0x001A, SyncTrayIcon)   ; WM_SETTINGCHANGE

/*
====================================================
Dark mode menu

Not sure what this bit does. Doesn't seem to have any effect on my system.
====================================================
*/

Class DarkMode {
    Static __New(Mode := 1) => ( ; Mode: Dark = 1, Default (Light) = 0
        DllCall(DllCall("GetProcAddress", "ptr", DllCall("GetModuleHandle", "str", "uxtheme", "ptr"), "ptr", 135, "ptr"), "int", mode),
        DllCall(DllCall("GetProcAddress", "ptr", DllCall("GetModuleHandle", "str", "uxtheme", "ptr"), "ptr", 136, "ptr"))
    )
}

/*
====================================================
Variables

AI settings now live in settings.ini and are read by lib\ai.ahk.
====================================================
*/


/*
====================================================
Misc. functions
====================================================
*/


;  function to edit this file in VS Code
EditSidekick(*) {
    Static editor := EnvGet('PROGRAMFILES') '\Microsoft VS Code\Code.exe'
    Run editor ' "' A_ScriptFullPath '"'
   }

; Define a NOP (No Operation) function
NOP(*) {
}

; ---------------------------------------------------------------------------
; The menu is built at run time from data\menu.json.
;
; Nothing personal lives in this file any more — snippets, passwords,
; bookmarks, searches and prompts are all data. Edit them from the Library
; Editor (first item on the menu) or by hand in data\menu.json.
;
; See lib\menu_builder.ahk for the entry kinds a data file may use.
; ---------------------------------------------------------------------------

RegisterBuiltInActions()

; The expansions are compiled into an included script, so a change to the data
; can only take effect after a restart. Checking here means an edit made in
; another instance, or by hand, is picked up on the next start rather than
; silently ignored.
EX_EnsureFresh()

global SidekickData := LoadMenuData()
global MenuPopup     := BuildMenuFromData(PK_WithPacks(SidekickData["menu"]))
RegisterHotstrings(SidekickData["hotstrings"])

; Start watching the clipboard (see lib\clipboard.ahk).
CB_Init()

; The scratchpad saves itself a moment after typing stops, so an exit can
; still catch a sentence in flight - including the one a reload causes,
; which is the common way this script ends.
OnExit(SP_OnExit)

; Bindings come from settings.ini (see lib\hotkeys.ahk).
LP_Load()
RegisterConfiguredHotkeys()

; And the ones the user made themselves (see lib\shortcuts.ahk).
RegisterUserShortcuts()

; Rebuild anything that changes between openings, then show the menu.
ShowMainMenu(x := unset, y := unset) {
    global MenuPopup
    CB_RefreshSubMenu()
    if (IsSet(x) && IsSet(y))
        MenuPopup.Show(x, y)
    else
        MenuPopup.Show()
}

; Rebuild the menu after the data file changes, without restarting.
ReloadSidekickMenu() {
    global SidekickData, MenuPopup
    SidekickData := LoadMenuData()
    MenuPopup := BuildMenuFromData(PK_WithPacks(SidekickData["menu"]))
}

; Functions implemented in this script that data entries may call by name.
RegisterBuiltInActions() {
    RegisterAction("OpenLibraryEditor", OpenLibraryEditor)
    RegisterAction("OpenHotkeyEditor", OpenHotkeyEditor)
    RegisterAction("OpenClipboardManager", CB_Show)
    RegisterAction("OpenPalette", PAL_Show)
    RegisterAction("OpenLanguagePair", LP_Dialog)
    RegisterAction("SwapLanguages", LP_Swap)
    RegisterAction("OpenLanguagePacks", PK_Dialog)
    RegisterAction("OpenMainWindow", MW_Show)
    RegisterAction("OpenQuickTrans", MW_ShowQuickTrans)
    RegisterAction("OpenScratchpad", MW_ShowScratchpad)
    RegisterAction("OpenProviderSettings", OpenProviderSettings)
    RegisterAction("OpenExpansionEditor", OpenExpansionEditor)
    RegisterAction("ReloadSidekick", (*) => Reload())
    RegisterAction("ToggleClipboardCapture", CB_ToggleCapture)
    RegisterAction("BoldHtml", BoldHtml)
    RegisterAction("ItalicHtml", ItalicHtml)
    RegisterAction("UnderlineHtml", UnderlineHtml)
    RegisterAction("ClipboardPasteLowercase", ClipboardPasteLowercase)
    RegisterAction("ClipboardPasteSentenceCase", ClipboardPasteSentenceCase)
    RegisterAction("ClipboardPasteTitlecase", ClipboardPasteTitlecase)
    RegisterAction("ClipboardPasteUppercase", ClipboardPasteUppercase)
    RegisterAction("DoubleCurlyQuotes", DoubleCurlyQuotes)
    RegisterAction("DoubleToSingleQuotes", DoubleToSingleQuotes)
    RegisterAction("EditSidekick", EditSidekick)
    RegisterAction("GoogleSearch", GoogleSearch)
    RegisterAction("GWIT", GWIT)
    RegisterAction("Grammarly", Grammarly)
    RegisterAction("LogiTerm", LogiTerm)
    RegisterAction("MicrosoftTerminologySearch", MicrosoftTerminologySearch)
    RegisterAction("PutInRoundBrackets", PutInRoundBrackets)
    RegisterAction("PutInSquareBrackets", PutInSquareBrackets)
    RegisterAction("RemoveSoftHyphens", RemoveSoftHyphens)
    RegisterAction("SingleCurlyQuotes", SingleCurlyQuotes)
    RegisterAction("dtSearch", dtSearch)
}


/*
====================================================
Text actions (Uppercase, Lowercase, etc.)

This section defines several text manipulation functions:

====================================================
*/

ClipboardPasteUppercase(*)    {         ; Converts the selected text to uppercase and pastes it back.
    A_Clipboard:=""
    SendInput("^c")
    if (!ClipWait(1, 1))
        return
    str:=A_Clipboard
    if (str=="")
        return
    A_Clipboard:=format("{:U}",str)
    if (!ClipWait(0.5, 0))
        return
    SendInput("^v")
    Sleep(500)
}


ClipboardPasteLowercase(*)    {         ; Converts the selected text to lowercase and pastes it back.
    A_Clipboard:=""
    SendInput("^c")
    if (!ClipWait(1, 1))
        return
    str:=A_Clipboard
    if (str=="")
        return
    A_Clipboard:=format("{:l}",str)
    if (!ClipWait(0.5, 0))
        return
    SendInput("^v")
    Sleep(500)
}

ClipboardPasteTitlecase(*)    {         ; Converts the selected text to title case and pastes it back.
    A_Clipboard:=""
    SendInput("^c")
    if (!ClipWait(1, 1))
        return
    str:=A_Clipboard
    if (str=="")
        return
    A_Clipboard:=format("{:T}",str)
    if (!ClipWait(0.5, 0))
        return
    SendInput("^v")
    Sleep(500)
}

ClipboardPasteSentenceCase(*)    {      ; Converts the selected text to sentence case and pastes it back.
    A_Clipboard:=""
    SendInput("^c")
    if (!ClipWait(1, 1))
        return
    str:=A_Clipboard
    if (str=="")
        return
    A_Clipboard:=RegExReplace(str, "(?:^|\.|\R)[- 0-9\*\(]*\K(.)([^\.\r\n]*)", "$U1$L2")
    if (!ClipWait(0.5, 0))
        return
    SendInput("^v")
    Sleep(500)
}

^+'::SingleCurlyQuotes()

SingleCurlyQuotes(*) {                    ; Put single, curly quotes around the selection: ‘like this’
    SK_WrapSelection(Chr(0x2018), Chr(0x2019))
}
;^+2::
DoubleCurlyQuotes(*) {                    ; Put double, curly quotes around the selection: “like this”
    SK_WrapSelection(Chr(0x201C), Chr(0x201D))
}
PutInRoundBrackets(*) {                    ; Put round brackets around the selection.
    SK_WrapSelection("(", ")")
}
PutInSquareBrackets(*) {                    ; Put square brackets around the selection.
    SK_WrapSelection("[", "]")
}
RemoveSoftHyphens(*) {                                      ; Removes soft hyphens from the selected text.
    A_Clipboard := ""                                       ; Clear the clipboard
    Send("^c")                                              ; Copy the current selection
    ClipWait(1)                                             ; Wait for the clipboard to contain text
	A_Clipboard := StrReplace(A_Clipboard, Chr(173), "")    ; replace all occurrences of the soft hyphen character in the current clipboard contents with nothing
	Send("^v")
}

DoubleToSingleQuotes(*) {                                    ; Replaces double quotes with single quotes in the selected text.
    A_Clipboard := ""                                       ; Clear the clipboard
    Send("^c")                                              ; Copy the current selection
    ClipWait(1)                                             ; Wait for the clipboard to contain text
    A_Clipboard := StrReplace(A_Clipboard, '"', "'")       ; Replace all occurrences of double quotes with single quotes
    Send("^v")                                              ; Paste the modified text back
}

ItalicHtml(*) {                    ; Wrap the selection in HTML italic tags.
    SK_WrapSelection("<i>", "</i>")
}

UnderlineHtml(*) {                 ; Wrap the selection in HTML underline tags.
    SK_WrapSelection("<u>", "</u>")
}

BoldHtml(*) {                    ; Wrap the selection in HTML bold tags.
    SK_WrapSelection("<b>", "</b>")
}
/*
====================================================
Web searches
====================================================
*/
{

MicrosoftTerminologySearch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://msit.powerbi.com/view?r=eyJrIjoiODJmYjU4Y2YtM2M0ZC00YzYxLWE1YTktNzFjYmYxNTAxNjQ0IiwidCI6IjcyZjk4OGJmLTg2ZjEtNDFhZi05MWFiLTJkN2NkMDExZGI0NyIsImMiOjV9"
    Run('msedge.exe "' SearchURL '"')
}


; Look the selection up in UniLex Pro (GWIT). Brought over from a personal
; script: it copies the selection, brings UniLex forward or starts it, then
; replaces whatever is in its search box and searches.
GWIT(*) {
    static exe := "C:\Program Files (x86)\UniLexPro\UniLexPro19.exe"

    text := SK_CopySelection(1)
    if (text = "") {
        MsgBox("Select a term first.", "Supervertaler Sidekick", "Icon! T2")
        return
    }

    if WinExist("UniLex Pro") {
        WinActivate()
        WinWaitActive("UniLex Pro", , 2)
    } else {
        if !FileExist(exe) {
            MsgBox("UniLex Pro is not where Sidekick expects it:`n`n" exe,
                   "Supervertaler Sidekick", "Icon!")
            return
        }
        try Run(exe)
        catch Error as err {
            MsgBox("Could not start UniLex Pro:`n`n" err.Message,
                   "Supervertaler Sidekick", "Icon!")
            return
        }
        if !WinWait("Lookup", , 30)
            return
        Sleep(800)
    }

    Send("^a")
    Sleep(50)
    Send("^v")
    Send("{Enter}")
}

GoogleSearch(*) {
    ; SK_CopySelection rather than a copy of its own: this runs from Ctrl+/,
    ; so Ctrl is still held when the copy goes out, and only that helper
    ; waits for it to be released before sending Ctrl+C.
    text := SK_CopySelection(2)
    if (text = "") {
        MsgBox("Nothing was selected.", "Supervertaler Sidekick", "Icon!")
        return
    }

    SearchURL := "https://www.google.co.uk/search?hl=en&safe=off&q="
               . SK_UriEncode(text)
    Run('msedge.exe "' SearchURL '"')
}


}
/*
====================================================
Multi-searches (nl➜en + en➜nl)
====================================================
*/

; Multi-search is now a menu entry of kind "multisearch" - see lib/langpair.ahk
; and RunMultiSearch in lib/menu_builder.ahk. The URLs live in the menu, with
; {sl} and {tl} for the language pair, so one entry serves every direction.

; Keyboard shortcuts for triggering searches
;; ^+z::MultiSearch("NL-EN") ; Ctrl+Shift+M for Dutch-to-English search
;; ^+x::MultiSearch("EN-NL") ; Ctrl+Shift+N for English-to-Dutch search


/*
====================================================
Local searches
====================================================
*/
{
;; dtSearch
dtSearch(*) {
SendInput("^c")
if WinExist(" - dtSearch ")
{
	WinActivate()
	Sleep(500)
}
else
{
	Run("C:\Program Files (x86)\dtSearch\bin64\dtSearch64.exe")
	Sleep(400)
}
{
Sleep(1000)
A_Clipboard := "`"" . A_Clipboard . "`""
SendInput("^v")
;SendInput("{Enter}")
return
}
}

; LogiTerm start:
LogiTerm(*) {
SetTitleMatchMode("RegEx")

CheckKeysPressed() {
    while (GetKeyState("Ctrl", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P") || GetKeyState("Shift", "P") || GetKeyState("Alt", "P"))
        Sleep(25)
}

SelectToClip() {
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(0.5) {
        MsgBox("Failed to copy text to clipboard.")
        return false
    }
    return true
}

;; ^!l::
{
    CheckKeysPressed()
    if !SelectToClip()
        return

    originalText := A_Clipboard
    A_Clipboard := RegExReplace(A_Clipboard, "^\s+|\s+(?=\s)|\s+$") ; remove extra spaces

    if (A_Clipboard == "") {
        MsgBox("No text was selected or clipboard is empty after trimming.")
        return
    }

    if WinExist("^LogiTerm Pro ahk_exe ltwebclient.exe")
        WinActivate
    else
    {
        Run(A_ProgramFiles "\Terminotix\LogiTerm\ltwebclient.exe")
        if !WinWaitActive("^LogiTerm Pro ahk_exe ltwebclient.exe", , 5) {
            MsgBox("Failed to launch or activate LogiTerm.")
            return
        }
        Sleep(1000)
    }

    ControlFocus("Edit1", "^LogiTerm Pro ahk_exe ltwebclient.exe")
    if (!WinActive("^LogiTerm Pro ahk_exe ltwebclient.exe")) {
        MsgBox("Failed to activate LogiTerm window.")
        return
    }

    Sleep(100)  ; Give a moment for the control to get focus
    Send('"' . A_Clipboard . '"')
    Sleep(50)
    Send("{Enter}")


}
}
;; LogiTerm end

}

/*
====================================================
Bookmarks (web URLs)
====================================================
*/


Grammarly(*) {
    WinActivate("wkwkwk.checking - Grammarly - Google Chrome ahk_class Chrome_WidgetWin_1")
    Send("{LControl Down}")
    Sleep(203)
    Send("{a}")
    Sleep(141)
    Send("{LControl Up}")
    Persistent
    Sleep(1187)
    Send("{LControl Down}")
    Sleep(125)
    Send("{v}")
    Sleep(125)
    Send("{LControl Up}")
}


/*
====================================================
Snippets
====================================================
*/

; Special characters


⇄(*) {
    SendInput "⇄"
}


ë(*) {
    SendInput "ë"
}

▶(*) {
    SendInput "▶"
}

; Telephone numbers


/*
====================================================
Talon Voice (menu items)
====================================================
*/


;


/*
====================================================
Hotkeys /  Keyboard shortcuts
====================================================
*/


;`::^space


; The AI window handles Escape itself (see AI_HideWindow in lib\ai.ahk).


;^+n::MultiSearchNlEn()          ; Ctrl-Shift-Z hotkey
; ^+e::MultiSearchEnNl()          ; Ctrl-Shift-e hotkey


; Menu, clipboard, reload, Google and desktop search are bound from
; settings.ini [Hotkeys] — see lib\hotkeys.ahk.

; Hotkeys that used to sit inside the menu block
; A_AppData resolves per user, so this works on any machine - and
; keeps a Windows profile name out of a shareable script.
^+7::Run(A_AppData "\talon")   ; Talon config folder


;;^+d::dtSearch()                 ; Ctrl-Shift-d opens and searches in dtSearch

;^!+1::Send("{Raw}■")   									; black square: ■
;^!+4::Send("{U+00B0}")   								; degree symbol: C°
;^!+5::Send("{U+2212}")									; Minus sign ( − ) / _vocola.vcl

^+`::Send("{U+0060}") 									; back tick( ` )
^+3::Send("€") 			; Euro sign ( € )
^+-::Send("{U+2014}") 									; Em dash symbol ( — )
^+6::Send("{U+2013}") 									; En dash symbol ( – )
^+o::Send("{U+2022}{Space}") 							; Bullet point ( • )

^+9::Send("{U+2018}") 									; Single, curly, opening quotation mark (“)
^+0::Send("{U+2019}") 									; Right single closing quotation mark (”)


