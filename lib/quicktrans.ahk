#Requires AutoHotkey v2.0
; ===========================================================================
; lib/quicktrans.ahk — translate the selection with several engines at once.
;
; Select text anywhere, press the hotkey, and every configured engine is asked
; in parallel. Results arrive as they land, numbered; press the number to
; insert one where you were working.
;
; Ported from the Supervertaler Workbench's QuickTrans. Same idea, same
; keyboard model (1-9 insert, arrows navigate, Enter inserts, Esc closes),
; but the requests are AutoHotkey's async WinHttp with a single polling timer
; rather than a thread per engine.
;
; MyMemory needs no API key, so this does something useful before anything is
; configured. Everything else reads its key from settings.ini.
; ===========================================================================

global QT_Gui      := ""
global QT_Source   := ""      ; the editable source box
global QT_List     := ""
global QT_SrcLang  := ""
global QT_TgtLang  := ""
global QT_Status   := ""
global QT_Jobs     := []      ; one entry per engine currently in flight
global QT_Rows     := []      ; what the list is showing, in row order
global QT_Window   := 0       ; window to insert back into
global QT_Running  := false

; ---------------------------------------------------------------------------
; Languages. Names for the dropdowns, ISO codes for the engines.
; ---------------------------------------------------------------------------
QT_Languages() {
    static langs := Map(
        "Dutch", "nl",        "English", "en",       "German", "de",
        "French", "fr",       "Spanish", "es",       "Italian", "it",
        "Portuguese", "pt",   "Danish", "da",        "Swedish", "sv",
        "Norwegian", "no",    "Finnish", "fi",       "Polish", "pl",
        "Czech", "cs",        "Greek", "el",         "Turkish", "tr",
        "Russian", "ru",      "Ukrainian", "uk",     "Romanian", "ro",
        "Hungarian", "hu",    "Bulgarian", "bg",     "Croatian", "hr",
        "Slovak", "sk",       "Slovenian", "sl",     "Estonian", "et",
        "Latvian", "lv",      "Lithuanian", "lt",    "Japanese", "ja",
        "Chinese (Simplified)", "zh",                "Korean", "ko",
        "Arabic", "ar",       "Hebrew", "he",        "Hindi", "hi",
        "Indonesian", "id",   "Vietnamese", "vi"
    )
    return langs
}

QT_LangNames() {
    names := []
    for name, _ in QT_Languages()
        names.Push(name)
    return names
}

QT_Code(name) {
    langs := QT_Languages()
    return langs.Has(name) ? langs[name] : "en"
}

; ---------------------------------------------------------------------------
; Engines.
;
; "group" only decides which heading a row sits under. "key" names the entry
; in settings.ini [Keys]; an engine whose key is missing is skipped, except
; MyMemory which needs none.
; ---------------------------------------------------------------------------
QT_Engines() {
    static engines := [
        Map("id", "mymemory", "label", "MyMemory",  "group", "mt", "key", ""),
        Map("id", "deepl",    "label", "DeepL",     "group", "mt", "key", "deepl"),
        Map("id", "anthropic","label", "Claude",    "group", "ai", "key", "anthropic"),
        Map("id", "openai",   "label", "OpenAI",    "group", "ai", "key", "openai")
    ]
    return engines
}

QT_Setting(key, default) {
    return AI_Ini(SettingsFile(), "QuickTrans", key, default)
}

; Which engines are configured and switched on.
QT_ActiveEngines() {
    out := []
    for e in QT_Engines() {
        if (QT_Setting(e["id"], "1") = "0")
            continue
        if (e["key"] != "" && Trim(AI_Ini(SettingsFile(), "Keys", e["key"], "")) = "")
            continue
        out.Push(e)
    }
    return out
}

; ---------------------------------------------------------------------------
; Requests
;
; Each engine gets its own COM object opened asynchronously; one timer polls
; them all. Nothing blocks, so the rest of Text Commander stays live while six
; engines are thinking.
; ---------------------------------------------------------------------------
QT_BuildRequest(engine, text, srcCode, tgtCode) {
    id  := engine["id"]
    key := engine["key"] != ""
         ? Trim(AI_Ini(SettingsFile(), "Keys", engine["key"], ""))
         : ""

    r := Map("method", "POST", "headers", Map(), "body", "")

    if (id = "mymemory") {
        r["method"] := "GET"
        r["url"] := "https://api.mymemory.translated.net/get?q="
                  . BB_UriEncode(text) "&langpair="
                  . srcCode "|" tgtCode
        return r
    }

    if (id = "deepl") {
        ; The free tier lives on a different host from the paid one. A key
        ; ending in :fx is a free-tier key.
        host := InStr(key, ":fx") ? "https://api-free.deepl.com"
                                  : "https://api.deepl.com"
        r["url"] := host "/v2/translate"
        r["headers"]["Authorization"] := "DeepL-Auth-Key " key
        r["headers"]["Content-Type"]  := "application/json; charset=utf-8"
        body := Map()
        body["text"] := [text]
        body["target_lang"] := StrUpper(tgtCode)
        body["source_lang"] := StrUpper(srcCode)
        r["body"] := Jxon_Dump(body)
        return r
    }

    ; The LLMs: a plain instruction, and nothing but the translation back.
    prompt := "Translate the following text from " QT_LangName(srcCode)
            . " into " QT_LangName(tgtCode) ". "
            . "Reply with the translation only — no commentary, no quotes, "
            . "no explanation.`n`n" text

    providers := AI_Providers()
    p := providers[id]
    r["url"] := p["url"]
    r["headers"]["Content-Type"] := "application/json; charset=utf-8"
    r["headers"][p["auth_header"]] := p["auth_prefix"] key
    if (p["version_header"] != "")
        r["headers"][p["version_header"]] := p["version_value"]

    model := QT_Setting(id "_model", p["default_model"])
    opts := Map("maxtokens", QT_Setting("MaxTokens", "1000"),
                "effort", QT_Setting("Effort", "low"))
    cfg := Map("maxtokens", QT_Setting("MaxTokens", "1000"),
               "effort", QT_Setting("Effort", "low"))
    r["body"] := AI_BuildBody(id, model, prompt, opts, cfg)
    return r
}

QT_LangName(code) {
    for name, c in QT_Languages() {
        if (c = code)
            return name
    }
    return code
}

QT_ParseResponse(engine, raw) {
    id := engine["id"]
    try {
        data := Jxon_Load(&raw)
    } catch {
        return ""
    }

    if (id = "mymemory") {
        try return Trim(data["responseData"]["translatedText"])
        catch
            return ""
    }

    if (id = "deepl") {
        try return Trim(data["translations"][1]["text"])
        catch
            return ""
    }

    return Trim(AI_ExtractText(id, raw))
}

; ---------------------------------------------------------------------------
QT_Translate() {
    global QT_Jobs, QT_Running, QT_Source, QT_SrcLang, QT_TgtLang

    text := Trim(QT_Source.Value)
    if (text = "") {
        QT_SetStatus("Nothing to translate.")
        return
    }

    QT_Abort()

    srcCode := QT_Code(QT_SrcLang.Text)
    tgtCode := QT_Code(QT_TgtLang.Text)

    engines := QT_ActiveEngines()
    if (engines.Length = 0) {
        QT_SetStatus("No engines configured. MyMemory needs no key; add "
                   . "others under [Keys] in settings.ini.")
        return
    }

    QT_Jobs := []
    for e in engines {
        job := Map("engine", e, "state", "pending", "text", "", "req", "")
        try {
            spec := QT_BuildRequest(e, text, srcCode, tgtCode)
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(20000, 20000, 20000, 60000)
            req.Open(spec["method"], spec["url"], true)
            for h, v in spec["headers"]
                req.SetRequestHeader(h, v)
            req.Send(spec["body"])
            job["req"] := req
        } catch Error as err {
            job["state"] := "error"
            job["text"] := err.Message
        }
        QT_Jobs.Push(job)
    }

    QT_Running := true
    QT_RenderRows()
    SetTimer(QT_Poll, 120)
}

QT_Poll() {
    global QT_Jobs, QT_Running

    pending := 0
    for job in QT_Jobs {
        if (job["state"] != "pending")
            continue

        req := job["req"]
        if (req = "") {
            job["state"] := "error"
            job["text"] := "no request"
            continue
        }

        done := false
        try
            done := req.WaitForResponse(0)
        catch Error as err {
            job["state"] := "error"
            job["text"] := err.Message
            continue
        }

        if (!done) {
            pending++
            continue
        }

        try {
            status := req.Status
            raw := AI_ResponseText(req)
            if (status != 200) {
                job["state"] := "error"
                job["text"] := "HTTP " status
            } else {
                out := QT_ParseResponse(job["engine"], raw)
                job["state"] := (out != "") ? "done" : "error"
                job["text"] := (out != "") ? out : "no translation in reply"
            }
        } catch Error as err {
            job["state"] := "error"
            job["text"] := err.Message
        }
        job["req"] := ""
    }

    QT_RenderRows()

    if (pending = 0) {
        SetTimer(QT_Poll, 0)
        QT_Running := false
        QT_SetStatus("Done.  1-9 insert  ·  ↑↓ choose  ·  Enter insert  ·  "
                   . "Ctrl+Enter re-translate  ·  Esc close")
    }
}

QT_Abort() {
    global QT_Jobs, QT_Running
    SetTimer(QT_Poll, 0)
    for job in QT_Jobs {
        if (job["req"] != "") {
            try job["req"].Abort()
            job["req"] := ""
        }
    }
    QT_Running := false
}

; ---------------------------------------------------------------------------
; Display
; ---------------------------------------------------------------------------
QT_RenderRows() {
    global QT_List, QT_Jobs, QT_Rows

    QT_List.Opt("-Redraw")
    QT_List.Delete()
    QT_Rows := []

    ; Machine translation first, then the LLMs — same order as the Workbench,
    ; and it puts the fast deterministic engines at the top of the list.
    for group in ["mt", "ai"] {
        for job in QT_Jobs {
            e := job["engine"]
            if (e["group"] != group)
                continue

            n := QT_Rows.Length + 1
            switch job["state"] {
                case "pending": shown := "…"
                case "error":   shown := "(" job["text"] ")"
                default:        shown := job["text"]
            }
            QT_List.Add(, n, e["label"], StrReplace(shown, "`n", " "))
            QT_Rows.Push(job)
        }
    }

    QT_List.ModifyCol(1, 28)
    QT_List.ModifyCol(2, 110)
    QT_List.ModifyCol(3, 620)
    QT_List.Opt("+Redraw")

    if (QT_Rows.Length > 0 && QT_List.GetNext(0) = 0)
        QT_List.Modify(1, "Select Focus")
}

QT_SetStatus(text) {
    global QT_Status
    try QT_Status.Value := text
}

; ---------------------------------------------------------------------------
QT_Show(*) {
    global QT_Gui, QT_Window, QT_Source, QT_SrcLang, QT_TgtLang

    try QT_Window := WinGetID("A")
    catch
        QT_Window := 0

    ; Unlike the other windows this one genuinely needs the selection up
    ; front — there is nothing to translate without it.
    sel := BB_CopySelection(1)

    if (QT_Gui = "")
        QT_BuildGui()

    if (sel != "")
        QT_Source.Value := sel

    QT_Gui.Show()
    QT_List.Focus()

    if (Trim(QT_Source.Value) != "")
        QT_Translate()
    else
        QT_SetStatus("Select some text first, or type it above and press "
                   . "Ctrl+Enter.")
}

QT_BuildGui() {
    global QT_Gui, QT_Source, QT_List, QT_SrcLang, QT_TgtLang, QT_Status

    QT_Gui := Gui("+Resize +MinSize700x420", "Text Commander — QuickTrans")
    QT_Gui.SetFont("s9", "Segoe UI")
    QT_Gui.OnEvent("Close", QT_Hide)
    QT_Gui.OnEvent("Escape", QT_Hide)
    QT_Gui.OnEvent("Size", QT_OnSize)

    QT_Gui.Add("Text", "xm ym", "Source:")
    QT_Source := QT_Gui.Add("Edit", "xm y+4 w840 r3 Multi")

    QT_Gui.Add("Text", "xm y+8 yp+4 w62", "Languages:")
    QT_SrcLang := QT_Gui.Add("DropDownList", "x+4 yp-4 w150", QT_LangNames())
    QT_Gui.Add("Text", "x+6 yp+4 w14", "→")
    QT_TgtLang := QT_Gui.Add("DropDownList", "x+4 yp-4 w150", QT_LangNames())
    QT_Gui.Add("Button", "x+6 yp-1 w32", "⇄").OnEvent("Click", (*) => QT_Swap())
    QT_Gui.Add("Button", "x+14 yp w110", "Re-translate")
        .OnEvent("Click", (*) => QT_Translate())

    QT_SelectLang(QT_SrcLang, QT_Setting("SourceLang", "Dutch"))
    QT_SelectLang(QT_TgtLang, QT_Setting("TargetLang", "English"))

    QT_List := QT_Gui.Add("ListView", "xm y+10 w840 h300 -Multi",
                          ["#", "Engine", "Translation"])
    QT_List.OnEvent("DoubleClick", (*) => QT_InsertSelected())

    QT_Status := QT_Gui.Add("Text", "xm y+8 w840", "")

    QT_Keys()
    QT_Gui.Show("w880 h520")
}

QT_SelectLang(ctrl, name) {
    for i, n in QT_LangNames() {
        if (n = name) {
            ctrl.Choose(i)
            return
        }
    }
    ctrl.Choose(1)
}

QT_Swap() {
    global QT_SrcLang, QT_TgtLang
    a := QT_SrcLang.Text, b := QT_TgtLang.Text
    QT_SelectLang(QT_SrcLang, b)
    QT_SelectLang(QT_TgtLang, a)
    QT_Translate()
}

; ---------------------------------------------------------------------------
QT_Keys() {
    global QT_Gui
    HotIfWinActive("ahk_id " QT_Gui.Hwnd)

    Loop 9 {
        n := A_Index
        Hotkey(n "", QT_MakeInsert(n), "On")
    }
    Hotkey("Enter",       (*) => QT_InsertSelected(), "On")
    Hotkey("NumpadEnter", (*) => QT_InsertSelected(), "On")
    Hotkey("^Enter",      (*) => QT_Translate(), "On")
    Hotkey("Down",        (*) => QT_Move(1),  "On")
    Hotkey("Up",          (*) => QT_Move(-1), "On")

    HotIfWinActive()
}

QT_MakeInsert(n) {
    return (*) => QT_InsertRow(n)
}

; The number keys must reach the source box while it is being edited,
; otherwise typing "1" would insert a translation instead of a digit.
QT_EditingSource() {
    global QT_Gui, QT_Source
    try return ControlGetFocus("ahk_id " QT_Gui.Hwnd) = QT_Source.Hwnd
    catch
        return false
}

QT_Move(delta) {
    global QT_List, QT_Rows
    if QT_EditingSource() {
        Send(delta > 0 ? "{Down}" : "{Up}")
        return
    }
    if (QT_Rows.Length = 0)
        return
    row := QT_List.GetNext(0)
    if (row = 0)
        row := (delta > 0) ? 0 : QT_Rows.Length + 1
    target := row + delta
    if (target < 1)
        target := 1
    if (target > QT_Rows.Length)
        target := QT_Rows.Length
    QT_List.Modify(0, "-Select")
    QT_List.Modify(target, "Select Focus Vis")
}

QT_InsertRow(n) {
    global QT_Rows
    if QT_EditingSource() {
        Send(n "")
        return
    }
    if (n < 1 || n > QT_Rows.Length)
        return
    QT_Insert(QT_Rows[n])
}

QT_InsertSelected() {
    global QT_List, QT_Rows
    if QT_EditingSource() {
        QT_Translate()
        return
    }
    row := QT_List.GetNext(0)
    if (row = 0 || row > QT_Rows.Length)
        return
    QT_Insert(QT_Rows[row])
}

QT_Insert(job) {
    global QT_Window
    if (job["state"] != "done")
        return
    text := job["text"]

    QT_Hide()
    if (QT_Window && WinExist("ahk_id " QT_Window)) {
        try {
            WinActivate("ahk_id " QT_Window)
            WinWaitActive("ahk_id " QT_Window, , 1)
        }
    }
    Sleep(80)
    SendText(text)
}

QT_Hide(*) {
    global QT_Gui
    QT_Abort()
    try QT_Gui.Hide()
    return true
}

QT_OnSize(thisGui, minMax, width, height) {
    global QT_Source, QT_List, QT_Status
    if (minMax = -1)
        return
    w := width - 24
    h := height - 220
    if (h < 100)
        h := 100
    try {
        QT_Source.Move(, , w)
        QT_List.Move(, , w, h)
        QT_List.ModifyCol(3, w - 150)
        QT_Status.Move(, , w)
    }
}
