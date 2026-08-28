/*
====================================================
Information:

; The AI request handling began as https://github.com/kdalanon/ChatGPT-AutoHotkey-Utility
; and has since been rewritten as a provider-agnostic layer (see lib\ai.ahk).
; Info @ https://github.com/michaelbeijer/Beijer.bot
====================================================
*/
#Requires AutoHotkey v2.0
if !A_IsAdmin {
    try {
        Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    }
    ExitApp
}


#SingleInstance
#Include "lib\jxon.ahk"
#Include "lib\data.ahk"
#Include "lib\menu_builder.ahk"
#Include "lib\ai.ahk"
#Include "lib\clipboard.ahk"
#Include "lib\palette.ahk"
#Include "lib\mainwindow.ahk"
#Include "lib\hotkeys.ahk"
#Include "lib\editor.ahk"
Persistent
TraySetIcon(A_ScriptDir "\B.ico")

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
EditBeijerBot(*) {
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

global BeijerBotData := LoadMenuData()
global MenuPopup     := BuildMenuFromData(BeijerBotData["menu"])
RegisterHotstrings(BeijerBotData["hotstrings"])

; Start watching the clipboard (see lib\clipboard.ahk).
CB_Init()

; Bindings come from settings.ini (see lib\hotkeys.ahk).
RegisterConfiguredHotkeys()

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
ReloadBeijerBotMenu() {
    global BeijerBotData, MenuPopup
    BeijerBotData := LoadMenuData()
    MenuPopup := BuildMenuFromData(BeijerBotData["menu"])
}

; Functions implemented in this script that data entries may call by name.
RegisterBuiltInActions() {
    RegisterAction("OpenLibraryEditor", OpenLibraryEditor)
    RegisterAction("OpenHotkeyEditor", OpenHotkeyEditor)
    RegisterAction("OpenClipboardManager", CB_Show)
    RegisterAction("OpenPalette", PAL_Show)
    RegisterAction("OpenMainWindow", MW_Show)
    RegisterAction("ReloadBeijerBot", (*) => Reload())
    RegisterAction("ToggleClipboardCapture", CB_ToggleCapture)
    RegisterAction("BoldHtml", BoldHtml)
    RegisterAction("ClipboardPasteLowercase", ClipboardPasteLowercase)
    RegisterAction("ClipboardPasteSentenceCase", ClipboardPasteSentenceCase)
    RegisterAction("ClipboardPasteTitlecase", ClipboardPasteTitlecase)
    RegisterAction("ClipboardPasteUppercase", ClipboardPasteUppercase)
    RegisterAction("DoubleCurlyQuotes", DoubleCurlyQuotes)
    RegisterAction("DoubleToSingleQuotes", DoubleToSingleQuotes)
    RegisterAction("EditBeijerBot", EditBeijerBot)
    RegisterAction("Grammarly", Grammarly)
    RegisterAction("LogiTerm", LogiTerm)
    RegisterAction("MicrosoftTerminologySearch", MicrosoftTerminologySearch)
    RegisterAction("MultiSearch", MultiSearch)
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

^+'::
SingleCurlyQuotes(*)    {                    ; Put single, curly quotes around selection: ‘This is an example.’
Send("^c")
Sleep(300)
A_Clipboard := "‘" . A_Clipboard . "’"
Sleep(600)
Send("^v")
}

;^+2::
DoubleCurlyQuotes(*)    {                    ; Surround selection with double, curly quotes “text”
Send("^c")
Sleep(300)
A_Clipboard := "“" . A_Clipboard . "”"
Sleep(300)
Send("^v")
}

PutInRoundBrackets(*)    {                  ; Surrounds the selected text with round brackets.
Send("^c")
Sleep(300)
A_Clipboard := "(" . A_Clipboard . ")"
Sleep(600)
Send("^v")
}

PutInSquareBrackets(*)    {                 ; Surrounds the selected text with square brackets.
Send("^c")
Sleep(300)
A_Clipboard := "[" . A_Clipboard . "]"
Sleep(600)
Send("^v")
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

BoldHtml(*)    {                            ; Surrounds the selected text with HTML bold tags (<b>).
    Send("^c")
    Sleep(300)
    A_Clipboard := "<b>" . A_Clipboard . "</b>"
    Sleep(600)
    Send("^v")
    }


/*
====================================================
Web searches
====================================================
*/
{

UriEncode(Uri) {
    Uri := StrReplace(Uri, " ", "%20") ; Replace spaces with '%20'
    ; Add other characters you want to replace here, if necessary`
    return Uri
}

AcronymFinder(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://www.acronymfinder.com/~/search/af.aspx?string=exact&Acronym=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

Beijerterm(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://beijerterm.com/?q=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}


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

VanDaleDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://zoeken.vandale.nl/?dictionaryId=gne&query=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

VanDaleEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://zoeken.vandale.nl/?dictionaryId=gen&query=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

GoogleSearch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "http://www.google.co.uk/search?hl=en&safe=off&q=" UriEncode(CopiedText)

    ; Run Microsoft Edge with the search URL
    Run('msedge.exe "' SearchURL '"')
}

GooglePatents(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := 'https://patents.google.com/?q="' UriEncode(CopiedText) '"'
    Run('msedge.exe "' SearchURL '"')
}

FELOnline(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "http://www.felonline.nl/felo/?keywords=" UriEncode(CopiedText) "&action=user_translate&lexiconSearch=Vertaal"
    Run('msedge.exe "' SearchURL '"')
}

Linguee(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://www.linguee.com/dutch-english/search?source=auto&query=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

Oxforddictionaries(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://premium.oxforddictionaries.com/definition/english/" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

BabelNetDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://babelnet.org/search?word=" UriEncode(CopiedText) "&lang=NL&transLang=EN"
    Run('msedge.exe "' SearchURL '"')
}

BabelNetEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://babelnet.org/search?word=" UriEncode(CopiedText) "&lang=EN&transLang=NL"
    Run('msedge.exe "' SearchURL '"')
}

JuremyDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://juremy.com/search?src=nld&dst=eng&q=" UriEncode(CopiedText) "&opts=ia&tool=iws"
    Run('msedge.exe "' SearchURL '"')
}

JuremyEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://juremy.com/search?src=eng&dst=nld&q=" UriEncode(CopiedText) "&opts=ia&tool=iws"
    Run('msedge.exe "' SearchURL '"')
}

IATESearchNlEn(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://iate.europa.eu/search/byUrl?term=" UriEncode(CopiedText) "&sl=nl&tl=en"
    Run('msedge.exe "' SearchURL '"')
}

IATESearchEnNl(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://iate.europa.eu/search/byUrl?term=" UriEncode(CopiedText) "&sl=en&tl=nl"
    Run('msedge.exe "' SearchURL '"')
}

JurLexDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://www.lexicons.nl/lemma?searchterm=" UriEncode(CopiedText) "&SESSIONdictionary=jel_nlen"
    Run('msedge.exe "' SearchURL '"')
}

JurLexEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://www.lexicons.nl/lemma?searchterm=" UriEncode(CopiedText) "&SESSIONdictionary=jel_ennl"
    Run('msedge.exe "' SearchURL '"')
}

ReversoDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://context.reverso.net/translation/dutch-english/" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

ReversoEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://context.reverso.net/translation/english-dutch/" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

ProzDutchEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://www.proz.com/search/?term=" UriEncode(CopiedText) "&from=dut&to=eng&results_per_page=25&es=1"
    Run('msedge.exe "' SearchURL '"')
}

ProzEnglishDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    Run SearchURL := "https://www.proz.com/search/?term=" UriEncode(CopiedText) "&from=eng&to=dut&results_per_page=25&es=1"
    Run('msedge.exe "' SearchURL '"')
}

WikipediaDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    Run SearchURL := "https://nl.wikipedia.org/w/index.php?search=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

WikipediaEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    Run SearchURL := "https://en.wikipedia.org/w/index.php?search=" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

WiktionaryDutch(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://nl.wiktionary.org/wiki/" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

WiktionaryEnglish(*) {
    A_Clipboard := "" ; Clear clipboard variable
    Send "^c" ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox "Failed to copy text to clipboard."
        return
    }
    CopiedText := A_Clipboard
    SearchURL := "https://en.wiktionary.org/wiki/" UriEncode(CopiedText)
    Run('msedge.exe "' SearchURL '"')
}

}
/*
====================================================
Multi-searches (nl➜en + en➜nl)
====================================================
*/

; Multi-search function (generalized)
MultiSearch(SearchDirection) {
    A_Clipboard := "" ; Clear clipboard variable
    Send("^c") ; Copy selected text to clipboard
    if !ClipWait(2) {
        MsgBox("Failed to copy text to clipboard.")
        return
    }
    CopiedText := A_Clipboard

    ; Open a new browser window
    BrowserPath := "C:/Program Files/Google/Chrome/Application/chrome.exe" ; Update this if needed for your browser
    Run('"' BrowserPath '" --new-window') ; Open a new Chrome window
    Sleep(1000) ; Allow time for the new window to open

    ; Define search URLs based on direction
    SearchURLs := []
    if (SearchDirection = "NL-EN") {
        SearchURLs := [
            "https://patents.google.com/?q={phrase}",
            "https://zoeken.vandale.nl/?dictionaryId=gne&query={phrase}",
            "https://iate.europa.eu/search/byUrl?term={phrase}&sl=nl&tl=en",
            "https://www.proz.com/?sp=ksearch&submit=1&term={phrase}&from=dut&to=eng",
            "https://beijerterm.com/?q={phrase}&from=nl&to=en",
            "https://context.reverso.net/translation/dutch-english/{phrase}",
            "https://juremy.com/search?src=nld&dst=eng&q={phrase}",
            "http://nl.wikipedia.org/w/index.php?search={phrase}",
            "https://nl.wiktionary.org/wiki/{phrase}",
            "http://www.acronymfinder.com/~/search/af.aspx?Acronym={phrase}",
            "https://babelnet.org/search?word={phrase}&lang=NL&transLang=EN"
        ]
    } else if (SearchDirection = "EN-NL") {
        SearchURLs := [
            "https://patents.google.com/?q={phrase}",
            "https://zoeken.vandale.nl/?dictionaryId=gne&query={phrase}",
            "https://iate.europa.eu/search/byUrl?term={phrase}&sl=en&tl=nl",
            "https://www.proz.com/?sp=ksearch&submit=1&term={phrase}&from=eng&to=dut",
            "https://beijerterm.com/?q={phrase}&from=en&to=nl",
            "https://context.reverso.net/translation/english-dutch/{phrase}",
            "https://juremy.com/search?src=eng&dst=nld&q={phrase}",
            "http://en.wikipedia.org/w/index.php?search={phrase}",
            "https://www.acronymfinder.com/~/search/af.aspx?Acronym={phrase}",
            "https://babelnet.org/search?word={phrase}&lang=EN&transLang=NL"
        ]
    }

    ; Loop through the URLs and replace {phrase} with the encoded text
    for Index, URL in SearchURLs {
        SearchURL := StrReplace(URL, "{phrase}", UriEncode(CopiedText))
        Run('"' BrowserPath '" ' SearchURL) ; Open each search URL in the new window
        Sleep(500) ; Optional: small delay to stagger tab opening
    }
}

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

RunWikipediaLinkFinder(*) {
    Run("D:\Software\Python\Wikipedia Interlanguage Link Finder\WikipediaInterlanguageLinkFinder.py")
    return
}
}

/*
====================================================
Bookmarks (web URLs)
====================================================
*/

AutoHotkeyHelpURL(*) {
    Run "https://www.autohotkey.com/docs/v2/"
}

Gmail(*) {
    Run "https://mail.google.com/mail/u/0/#inbox"
}

BeijertermURL(*) {
    Run "https://michaelbeijer.co.uk/"
}

BeijerbotURL(*) {
    Run "https://beijer.bot/"
}

BeijerbotEditURL(*) {
    Run "https://business27.web-hosting.com:2083/cpsess9102004596/frontend/jupiter/filemanager/editors/html_editor.html?file=index.html&fileop=&dir=%2Fhome%2Fwbymlrtq%2Fbeijer.bot&dirop=&charset=utf-8&file_charset=&baseurl=http%3A%2F%2Fbeijer.bot.beijer.uk&basedir=%2Fhome%2Fwbymlrtq%2Fbeijer.bot"
}


BeijerUkEditURL(*) {
    Run "https://business27.web-hosting.com:2083/cpsess3455211569/frontend/jupiter/sitebuilder/index.live.php"
}

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

MiscSpecialChars(*) {
    SendInput "▣ ■ □ ▢ ◯ ▲ ▶ ► ▼ ◆ ◢ ◣ ◤ ◥ ✪ ✺ ❋ ⁂ ∰ ⋰ ⋱ ∶ ∷ ∴ ∵ ⋘ ⋙ ✈ ✿ ☺ ☻ ☹ ☼ ☂ ☃ ⌇ ⚛ ⌨ ✆ ☎  ⌘ ⌥ ⇧ ↩ ✞ ✡ ☭ ← → ↑ ↓ ➫ ⬇ ⬆ ☜ ☞ ☝ ☟ ✍ ✎ ✌ ☮ ✔ ★ ☆ ♺ ⚑ ⚐ ✉ ✄ ⌲ ✈ ♦ ♣ ♠ ♥ ❤ ♡ ♪ ♩ ♫ ♬ ♯ ♀ ♂ ⚢ ⚣ ❑ ❒ ◈ ◐ ◑ ✖ ∞ « » ‹ › “ ” “ ” „ ‚ – — | ⁄ \ [ ] { } § ¶ ¡ ¿ ‽ ⁂ ※ ± × ~ ≈ ÷ ≠ π † ‡ ¥ € $ ¢ £ ß © ® @ ™ ° ‰ … · • ● ⌨"
}

⇄(*) {
    SendInput "⇄"
}

PrimeSymbols(*) {
    SendInput "′ ″ ‴ ⁗"
}

ë(*) {
    SendInput "ë"
}

▶(*) {
    SendInput "▶"
}

; Telephone numbers

MyMobile(*) {
    SendInput "07475771720"
}


/*
====================================================
Talon Voice (menu items)
====================================================
*/

BeijerTalon(*) {
    Run "C:\Users\mbeijer\AppData\Roaming\talon\user\my_talon\beijer.talon"
}

memoQTalon(*) {
    Run "C:\Users\mbeijer\AppData\Roaming\talon\user\my_talon\memoQ.talon"
}


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
^+7::Run("C:\Users\mbeijer\AppData\Roaming\talon")   ; Talon config folder


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




