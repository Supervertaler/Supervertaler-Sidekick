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
        Map("id", "openai",   "label", "OpenAI",    "group", "ai", "key", "openai")
    ]
    return engines
}

QT_Setting(key, default) {
    return AI_Ini(SettingsFile(), "QuickTrans", key, default)
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
    r["url"] := p["url"]
    r["headers"]["Content-Type"] := "application/json; charset=utf-8"
    r["headers"][p["auth_header"]] := p["auth_prefix"] key
    if (p["version_header"] != "")
        r["headers"][p["version_header"]] := p["version_value"]

    model := QT_Setting(id "_model", p["default_model"])
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

    if (pending = 0) {
        SetTimer(QT_Poll, 0)
        QT_Running := false
    }

    if (QT_OnUpdate != "") {
        try QT_OnUpdate.Call(pending = 0)
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
