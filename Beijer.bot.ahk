/*
====================================================
Information:

; Original code borrowed from: https://github.com/kdalanon/ChatGPT-AutoHotkey-Utility (“ChatGPT-AutoHotkey-Utility”)
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

This section declares and initializes several variables used in the script,
including the API key (read from an external file), API URL, status message,
response window status, and retry status.
====================================================
*/

;API_Key := "???" ; originally API key was in the script itself; moved to external file: ChatGptAPI.ini
API_Key := IniRead("ChatGptAPI.ini", "ChatGptAPI", "API_Key")
API_URL := "https://api.openai.com/v1/chat/completions"
Status_Message := ""
Response_Window_Status := "Closed"
Retry_Status := ""

HTTP_Request := ""
Previous_ChatGPT_Prompt := ""
Previous_Status_Message := ""
Previous_API_Model := ""
Request_In_Progress := false

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

; Rebuild the menu after the data file changes, without restarting.
ReloadBeijerBotMenu() {
    global BeijerBotData, MenuPopup
    BeijerBotData := LoadMenuData()
    MenuPopup := BuildMenuFromData(BeijerBotData["menu"])
}

; Functions implemented in this script that data entries may call by name.
RegisterBuiltInActions() {
    RegisterAction("OpenLibraryEditor", OpenLibraryEditor)
    RegisterAction("BoldHtml", BoldHtml)
    RegisterAction("ClipboardPasteLowercase", ClipboardPasteLowercase)
    RegisterAction("ClipboardPasteSentenceCase", ClipboardPasteSentenceCase)
    RegisterAction("ClipboardPasteTitlecase", ClipboardPasteTitlecase)
    RegisterAction("ClipboardPasteUppercase", ClipboardPasteUppercase)
    RegisterAction("DoubleCurlyQuotes", DoubleCurlyQuotes)
    RegisterAction("DoubleToSingleQuotes", DoubleToSingleQuotes)
    RegisterAction("EditBeijerBot", EditBeijerBot)
    RegisterAction("Expand", Expand)
    RegisterAction("Explain", Explain)
    RegisterAction("GenerateReply", GenerateReply)
    RegisterAction("Grammarly", Grammarly)
    RegisterAction("Localize", Localize)
    RegisterAction("LogiTerm", LogiTerm)
    RegisterAction("MakeItSoundBetter", MakeItSoundBetter)
    RegisterAction("MicrosoftTerminologySearch", MicrosoftTerminologySearch)
    RegisterAction("MultiSearch", MultiSearch)
    RegisterAction("ProofreadMulti", ProofreadMulti)
    RegisterAction("PutInRoundBrackets", PutInRoundBrackets)
    RegisterAction("PutInSquareBrackets", PutInSquareBrackets)
    RegisterAction("RemoveSoftHyphens", RemoveSoftHyphens)
    RegisterAction("Rephrase", Rephrase)
    RegisterAction("SingleCurlyQuotes", SingleCurlyQuotes)
    RegisterAction("Summarise", Summarise)
    RegisterAction("SummarizeGitHubIssue", SummarizeGitHubIssue)
    RegisterAction("TranslateCustom", TranslateCustom)
    RegisterAction("TranslateDutchEnglish", TranslateDutchEnglish)
    RegisterAction("TranslateEnglishDutch", TranslateEnglishDutch)
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
ChatGPT functions (Translate, Rephrase, etc.)
====================================================
*/

TranslateCustom(*) {
    ChatGPT_Prompt := "Translate the selection from Dutch to English or vice versa, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If the text is a single term, please treat it as a terminology translation/question. # Here is a summary of the complete text it has been extracted from for you to use as context: This is the operator’s manual for the TAFE 240S agricultural tractor, containing safety instructions, operating procedures, maintenance guidance, and technical specifications. # Provide me only with the Dutch or English translation, nothing else."
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

TranslateDutchEnglish(*) {
    ChatGPT_Prompt := "Please generate a numbered list of ten possible translations from Dutch to English, ensuring the translations accurately convey the intended meaning or idea without excessive deviation. Please also ensure you provide a range of different versions, ranging from technical to general. If the text is a single term, please treat it as a terminology translation/question, and also give some extra info in brackets behind each term."
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

Rephrase(*) {
    ChatGPT_Prompt := "Rephrase the following text or paragraph to ensure clarity, conciseness, and a natural flow. Give me 5 different versions. The revision should preserve the tone, style, and formatting of the original text. Additionally, correct any grammar and spelling errors you come across. If the text is Dutch, give me Dutch suggestions; if the text is English, give me English suggestions. Present the original above the revised versions, with the original and revised versions indicated like this: 'Original: …' and 'Revised versions: …'"
    Status_Message := "I’m rephrasing your text. Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

MakeItSoundBetter(*) {
    ChatGPT_Prompt := "can you please rewrite this so it sounds better?"
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

Localize(*) {
    ChatGPT_Prompt := "Localize the selected text from US English into UK English, making only basic changes, such as: change all z's to s's (organization ➜ organisation); o ➜ ou (color, etc); change all joined-up em dashes to spaced n dashes ('contribute—it's a fundamental' ➜ 'contribute – it's a fundamental'); change any specifically US words to British equivalents (truck ➜ lorry, toll free number ➜ freephone number); change Imperial units to metric; and anything else you can think of that falls within this remit. However, don't rewrite anything. Output: (1) Original text…, an empty line, (2) Edited text:…, an empty line, (3) Changes:… (in bullet points)."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

TranslateEnglishDutch(*) {
    ChatGPT_Prompt := "Please generate a numbered list of ten possible translations from English to Dutch, ensuring the translations accurately convey the intended meaning or idea without excessive deviation. Please also ensure you provide a range of different versions, ranging from technical to general. If the text is a single term, please treat it as a terminology translation/question, and also give some extra info in brackets behind each term."
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

ProofreadMulti(*) {

    ChatGPT_Prompt := "Please correct the text I provide. Your job is to identify and amend any typos, misspellings, missing words, etc., regardless of the language it's in. It's important that the language of the original text be maintained in the corrected version. You're allowed to change the word order where necessary for coherence, but remember to keep the original intent of the text intact. The output should be just the corrected text, with no additional comments or markings. Present the original above the proofread version, with the original and proofread versions indicated like this: 'Original: …' and 'Proofread: …' Please put 'Original: …' and 'Proofread: …' on their own lines, and the text itself on the lines directly below these words, so the text in question is aligned vis-à-vis the left margin. Please also separate the two with a line, so before 'Proofread: ', there should be a dashed line. If no changes are made, indicate this at the very bottom as follows: 'Yay, no changes were made.' Please provide a numbered list of each change you made at the very bottom, as follows: 1. het ➜ de (explain why here)`n2. onderneem ➜ onderneemt (explain why here)`n1. met één trage laadtij ➜ met een trage laadtijd (explain why here). // Please also put single asterisks around any changed bits in the Original section. // Please copy the proofread version to the clipboard, so just the original, with any changes, to the Windows clipboard!"
    Status_Message := "I’m checking your text. Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

Summarise(*) {
    ChatGPT_Prompt := "Summarise the following:"
    Status_Message := "I’m summarising your text. Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

Explain(*) {
    ChatGPT_Prompt := "Explain the following:"
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

Expand(*) {
    ChatGPT_Prompt := "Considering the original tone, style, and formatting, please help me express the following idea in a clearer and more articulate way. The style of the message could be formal, informal, casual, empathetic, assertive, or persuasive, depending on the context of the original message. The text should be divided into paragraphs for readability. No specific language complexities need to be avoided and the focus should be equally distributed throughout the message. There's no set minimum or maximum length. Here's what I’m trying to say:"
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

GenerateReply(*) {
    ChatGPT_Prompt := "Craft a response to any given message, regardless of the language it's in. The response should adhere to the original sender's tone, style, formatting, and cultural or regional context. Maintain the same level of formality and emotional tone as the original message. Responses may be of any length, provided they effectively communicate the response to the original sender:"
    Status_Message := "I’m working on it! Please be patient while I think..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
}

SummarizeGitHubIssue(*) {
    ChatGPT_Prompt := "Summarise the following GitHub issue into a GitHub issue title. If it is a feature request, preface it with '[Feature] ', if it is a bug, preface it with '[Bug] '. Please use sentence case, not title case. Also rewrite the text given, streamlining it and removing any errors. Use UK English. Your output should be the title followed by your corrected text:"
    Status_Message := "Summarising and tidying up your GitHub issue..."
    API_Model := "gpt-5"
    ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status)
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

/*
====================================================
Create Response Window
====================================================
*/

;Response_Window := Gui("-Caption +Resize", "Response")
;Response_Window.SetFont("s13 cBlack", "Georgia")
;Response := Response_Window.Add("Edit", "r20 ReadOnly -VScroll w1900 h950 Wrap Background333333", Status_Message)

Response_Window := Gui("+Caption +Resize +SysMenu +ToolWindow", "Response")
Response_Window.SetFont("s13 cBlack", "Calibri")
Response := Response_Window.Add("Edit", "r20 ReadOnly -VScroll w1400 h950 Wrap BackgroundWhite", Status_Message)

; Adjusting the position of the buttons
yPos := 460 ; Y-coordinate for the buttons, adjust as needed
RetryButton := Response_Window.Add("Button", "x20 y" yPos " Disabled", "Retry")
RetryButton.OnEvent("Click", Retry)
CopyButton := Response_Window.Add("Button", "x+20 y" yPos " w80 Disabled", "Copy")
CopyButton.OnEvent("Click", Copy)
CloseButton := Response_Window.Add("Button", "x+20 y" yPos, "Close")
CloseButton.OnEvent("Click", Close)






/*
====================================================
Buttons
====================================================
*/

Retry(*) {
    Retry_Status := "Retry"
    RetryButton.Enabled := 0
    CopyButton.Enabled := 0
    CopyButton.Text := "Copy"
    ProcessRequest(Previous_ChatGPT_Prompt, Previous_Status_Message, Previous_API_Model, Retry_Status)
}

Copy(*) {
    A_Clipboard := Response.Value
    CopyButton.Enabled := 0
    CopyButton.Text := "Copied!"

    DllCall("SetFocus", "Ptr", 0)
    Sleep 2000

    CopyButton.Enabled := 1
    CopyButton.Text := "Copy"
}

Close(*) {
    global HTTP_Request, Request_In_Progress

    ; Signal that we're aborting
    Request_In_Progress := false

    if (HTTP_Request != "") {
        try {
            HTTP_Request.Abort()
        }
        HTTP_Request := ""
    }

    ; Stop the loading cursor timer
    SetTimer LoadingCursor, 0
    OnMessage(0x200, WM_MOUSEHOVER, 0)

    Response_Window.Hide()
    global Response_Window_Status := "Closed"
}

/*
====================================================
Connect to ChatGPT API and process request
====================================================
*/

ProcessRequest(ChatGPT_Prompt, Status_Message, API_Model, Retry_Status) {
    global HTTP_Request, Request_In_Progress
    global Previous_ChatGPT_Prompt, Previous_Status_Message, Previous_API_Model
    global Response_Window_Status

    ; If a request is already running, abort it first
    if (Request_In_Progress) {
        if (HTTP_Request != "") {
            try {
                HTTP_Request.Abort()
            }
            HTTP_Request := ""
        }
        Sleep(200)
    }

    if (Retry_Status != "Retry") {
        Sleep(150)          ; ← ADD THIS LINE: let the menu close and focus return
        A_Clipboard := ""
        Send "^c"
        if !ClipWait(2) {
            MsgBox "The attempt to copy text onto the clipboard failed."
            return
        }
        CopiedText := A_Clipboard
        ChatGPT_Prompt := ChatGPT_Prompt "`n`n" CopiedText
        Previous_ChatGPT_Prompt := ChatGPT_Prompt
        Previous_Status_Message := Status_Message
        Previous_API_Model := API_Model
    }

    OnMessage 0x200, WM_MOUSEHOVER
    Response.Value := Status_Message
    if (Response_Window_Status = "Closed") {
        Response_Window.Show("AutoSize Center")
        Response_Window_Status := "Open"
        RetryButton.Enabled := 0
        CopyButton.Enabled := 0
    }
    DllCall("SetFocus", "Ptr", 0)

    ; Always create a FRESH COM object – never reuse a stale one
    if (HTTP_Request != "") {
        try {
            HTTP_Request.Abort()
        }
        HTTP_Request := ""
        Sleep(100)  ; Brief pause to let COM release fully
    }

    Request_In_Progress := true

    try {
        HTTP_Request := ComObject("WinHttp.WinHttpRequest.5.1")
        HTTP_Request.SetTimeouts(60000, 60000, 60000, 120000)

        HTTP_Request.open("POST", API_URL, true)
        HTTP_Request.SetRequestHeader("Content-Type", "application/json")
        HTTP_Request.SetRequestHeader("Authorization", "Bearer " API_Key)

        Messages := Map("role", "user", "content", ChatGPT_Prompt)
        JSON_Request := Map("model", API_Model, "messages", [Messages])
        JSON_Request := Jxon_Dump(JSON_Request)

        HTTP_Request.Send(JSON_Request)
        SetTimer LoadingCursor, 1
        if WinExist("Response") {
            WinActivate "Response"
        }
        HTTP_Request.WaitForResponse()

        ; Check if we were aborted while waiting (user closed the window)
        if (!Request_In_Progress) {
            HTTP_Request := ""
            SetTimer LoadingCursor, 0
            OnMessage 0x200, WM_MOUSEHOVER, 0
            Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32512)
            DllCall("SetCursor", "UPtr", Cursor)
            return
        }

        if (HTTP_Request.status == 200) {
            SafeArray := HTTP_Request.responseBody
            pData := NumGet(ComObjValue(SafeArray) + 8 + A_PtrSize, 'Ptr')
            length := SafeArray.MaxIndex() + 1
            JSON_Response := StrGet(pData, length, 'UTF-8')
            var := Jxon_Load(&JSON_Response)
            JSON_Response := var.Get("choices")[1].Get("message").Get("content")
            RetryButton.Enabled := 1
            CopyButton.Enabled := 1
            Response.Value := JSON_Response
            A_Clipboard := JSON_Response
        } else {
            RetryButton.Enabled := 1
            CopyButton.Enabled := 1
            Response.Value := "Status " HTTP_Request.status " " HTTP_Request.responseText
        }
    } catch Error as err {
        RetryButton.Enabled := 1
        CopyButton.Enabled := 1
        Response.Value := "Error: " err.Message "`n`nPlease try again or reload the script if the problem persists."
    }

    ; Unified cleanup – always runs regardless of success/failure
    Request_In_Progress := false
    HTTP_Request := ""  ; Always release the COM object after each request

    SetTimer LoadingCursor, 0
    OnMessage 0x200, WM_MOUSEHOVER, 0
    Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32512)
    DllCall("SetCursor", "UPtr", Cursor)

    Response_Window.Flash()
    DllCall("SetFocus", "Ptr", 0)
}

/*
====================================================
Cursors
====================================================
*/

WM_MOUSEHOVER(*) {
    Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32648) ; Unavailable cursor
    MouseGetPos ,,, &MousePosition
    if (CopyButton.Enabled = 0) & (MousePosition = "Button2") {
        DllCall("SetCursor", "UPtr", Cursor)
    } else if (RetryButton.Enabled = 0) & (MousePosition = "Button1") | (MousePosition = "Button2") {
        DllCall("SetCursor", "UPtr", Cursor)
    }
}

LoadingCursor() {
    MouseGetPos ,,, &MousePosition
    if (MousePosition = "Edit1") {
        Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32514) ; Loading cursor
        DllCall("SetCursor", "UPtr", Cursor)
    }
}

/*
====================================================
Hotkeys /  Keyboard shortcuts
====================================================
*/


;`::^space

^`::
{
;Reload
MenuPopup.Show()
}


`::MenuPopup.Show(132, 164)     ; Backtick (`) opens Beijer.bot
;; `::MenuPopup.Show()


#HotIf WinActive("Response ahk_exe AutoHotkey64.exe")
~Esc::Close()
#HotIf



;^+n::MultiSearchNlEn()          ; Ctrl-Shift-Z hotkey
; ^+e::MultiSearchEnNl()          ; Ctrl-Shift-e hotkey


^!e::Explain()                  ; ctrl-shift-; triggers ChatGPT “Explain” function

; Hotkeys that used to sit inside the menu block
^+7::Run("C:\Users\mbeijer\AppData\Roaming\talon")   ; Talon config folder
^+d::dtSearch()                 ; Ctrl+Shift+D searches the desktop

^r::Reload                      ; Reload this script when I press Ctrl+R

^/::GoogleSearch()              ; Ctrl+/ triggers GoogleSearch
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


; Close the response window when the Escape key is pressed; removed cuz not needed
;Escape::Close()







