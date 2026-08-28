#Requires AutoHotkey v2.0
; ===========================================================================
; lib/quicktrans.ahk — the translation engines.
;
; Engines only: requests, parsing, language codes, and the parallel fetch.
; The presentation lives in lib/mainwindow.ahk as the QuickTrans tab, so the
; menu tree stays on screen beside the translations — translate something,
; insert it, then run a menu action without changing windows.
;
; Every engine is asked at once through async WinHttp driven by one polling
; timer, so nothing blocks while four engines think. Whoever is showing the
; results sets QT_OnUpdate and gets called each time a result lands.
;
; MyMemory needs no API key, so this does something useful before anything is
; configured. Everything else reads its key from settings.ini.
; ===========================================================================

global QT_Jobs     := []      ; one entry per engine currently in flight
global QT_Running  := false
global QT_OnUpdate := ""      ; called whenever a result arrives

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

QT_LangName(code) {
    for name, c in QT_Languages() {
        if (c = code)
            return name
    }
    return code
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
        Map("id", "openai",   "label", "OpenAI",    "group", "ai", "key", "openai"),
        Map("id", "gemini",   "label", "Gemini",    "group", "ai", "key", "gemini")
    ]
    return engines
}

QT_Setting(key, default) {
    return AI_Ini(SettingsFile(), "QuickTrans", key, default)
}

; Which model an engine should use.
;
; IniRead returns the empty string for a key that is present but blank, not
; the default — so "anthropic_model=" with nothing after it would otherwise
; send an empty model name and fail every request. Blank means "the
; provider's default", which is what someone writing that line intends.
QT_Model(id, default) {
    v := Trim(QT_Setting(id "_model", ""))
    return (v = "") ? default : v
}

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
    ; Per-engine model override lives in [QuickTrans], e.g. openai_model=.
    model := QT_Model(id, p["default_model"])
    r["url"] := StrReplace(p["url"], "{model}", model)
    r["headers"]["Content-Type"] := "application/json; charset=utf-8"
    r["headers"][p["auth_header"]] := p["auth_prefix"] key
    if (p["version_header"] != "")
        r["headers"][p["version_header"]] := p["version_value"]

    cfg := Map("maxtokens", QT_Setting("MaxTokens", "1000"),
               "effort", QT_Setting("Effort", "low"))
    r["body"] := AI_BuildBody(id, model, prompt, Map(), cfg)
    return r
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
; Fetch
;
; Returns immediately. QT_Jobs fills in as replies land; QT_OnUpdate is
; called after each poll so the view can redraw.
; ---------------------------------------------------------------------------
QT_Start(text, srcCode, tgtCode) {
    global QT_Jobs, QT_Running

    QT_Abort()

    engines := QT_ActiveEngines()
    QT_Jobs := []
    if (engines.Length = 0)
        return 0

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
    SetTimer(QT_Poll, 120)
    return QT_Jobs.Length
}

QT_Poll() {
    global QT_Jobs, QT_Running, QT_OnUpdate

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
                job["text"] := QT_StatusText(status)
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

    if (pending = 0) {
        SetTimer(QT_Poll, 0)
        QT_Running := false
    }

    if (QT_OnUpdate != "") {
        try QT_OnUpdate.Call(pending = 0)
    }
}

; What went wrong, in words. A bare "HTTP 401" tells you a number; "key
; rejected" tells you where to go and fix it.
QT_StatusText(status) {
    switch status {
        case 400: return "bad request"
        case 401: return "key rejected"
        case 403: return "access denied"
        case 404: return "not found"
        case 413: return "text too long"
        case 429: return "rate limited"
        default:
            if (status >= 500)
                return "engine unavailable (" status ")"
            return "HTTP " status
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

; Jobs in display order: machine translation first, then the LLMs.
QT_Ordered() {
    global QT_Jobs
    out := []
    for group in ["mt", "ai"] {
        for job in QT_Jobs {
            if (job["engine"]["group"] = group)
                out.Push(job)
        }
    }
    return out
}


; ===========================================================================
; "Which model can I use?"
;
; Every provider publishes a models endpoint. Asking it beats reciting a list
; that goes stale, and it answers for THIS account rather than in general —
; model availability differs by account and tier.
; ===========================================================================
QT_ModelEndpoint(id) {
    switch id {
        case "anthropic": return "https://api.anthropic.com/v1/models"
        case "openai":    return "https://api.openai.com/v1/models"
        case "gemini":
            return "https://generativelanguage.googleapis.com/v1beta/models"
    }
    return ""
}

; Returns a Map: "ok" (bool), "models" (array of ids), "error" (text).
QT_FetchModels(id) {
    out := Map("ok", false, "models", [], "error", "")

    url := QT_ModelEndpoint(id)
    if (url = "") {
        out["error"] := "no model list for this engine"
        return out
    }

    key := Trim(AI_Ini(SettingsFile(), "Keys", id, ""))
    if (key = "") {
        out["error"] := "no API key set"
        return out
    }

    providers := AI_Providers()
    p := providers[id]

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 25000)
        req.Open("GET", url, true)
        req.SetRequestHeader(p["auth_header"], p["auth_prefix"] key)
        if (p["version_header"] != "")
            req.SetRequestHeader(p["version_header"], p["version_value"])
        req.Send()
        req.WaitForResponse(25)

        if (req.Status != 200) {
            out["error"] := QT_StatusText(req.Status)
            return out
        }
        raw := AI_ResponseText(req)
        data := Jxon_Load(&raw)
    } catch Error as err {
        out["error"] := err.Message
        return out
    }

    ids := []
    try {
        if (id = "gemini") {
            ; Gemini names them "models/x" and lists what each one can do.
            for m in data["models"] {
                name := StrReplace(m["name"], "models/", "")
                usable := !m.Has("supportedGenerationMethods")
                if !usable {
                    for meth in m["supportedGenerationMethods"] {
                        if (meth = "generateContent")
                            usable := true
                    }
                }
                if usable
                    ids.Push(name)
            }
        } else {
            for m in data["data"] {
                mid := m["id"]
                ; OpenAI lists embeddings, audio and image models too; only
                ; the chat families are any use here.
                if (id = "openai" && !RegExMatch(mid, "^(gpt|o[0-9]|chatgpt)"))
                    continue
                ids.Push(mid)
            }
        }
    } catch Error as err {
        out["error"] := "unexpected reply: " err.Message
        return out
    }

    out["ok"] := true
    out["models"] := ids
    return out
}

; ---------------------------------------------------------------------------
global QTM_Gui := ""

OpenModelList(*) {
    global QTM_Gui

    if (QTM_Gui != "") {
        try QTM_Gui.Destroy()
        QTM_Gui := ""
    }

    QTM_Gui := Gui("+Resize +MinSize520x420", "Text Commander — Available models")
    QTM_Gui.SetFont("s9", "Segoe UI")
    QTM_Gui.OnEvent("Close", (*) => QTM_Close())
    QTM_Gui.OnEvent("Escape", (*) => QTM_Close())

    QTM_Gui.Add("Text", "xm ym w620",
                "Models your API keys can actually use. Put one in "
                "settings.ini under [QuickTrans], e.g. openai_model=gpt-5-mini")

    lv := QTM_Gui.Add("ListView", "xm y+8 w620 h420 -Multi",
                      ["Engine", "Model", "In use"])
    status := QTM_Gui.Add("Text", "xm y+8 w620", "Asking each provider…")
    QTM_Gui.Show("w660 h520")

    providers := AI_Providers()
    total := 0
    for id, p in providers {
        r := QT_FetchModels(id)
        current := QT_Model(id, p["default_model"])

        if !r["ok"] {
            lv.Add(, p["label"], "(" r["error"] ")", "")
            continue
        }
        for m in r["models"] {
            lv.Add(, p["label"], m, (m = current) ? "yes" : "")
            total++
        }
    }

    lv.ModifyCol(1, 130)
    lv.ModifyCol(2, 330)
    lv.ModifyCol(3, 60)
    status.Value := total " models available."
             . "  Double-click one to copy its name."

    lv.OnEvent("DoubleClick", QTM_Copy)

    QTM_Copy(ctrl, row) {
        if (row = 0)
            return
        name := ctrl.GetText(row, 2)
        if (SubStr(name, 1, 1) = "(")
            return
        A_Clipboard := name
        status.Value := "Copied: " name
    }
}

QTM_Close() {
    global QTM_Gui
    try QTM_Gui.Destroy()
    QTM_Gui := ""
    return true
}
