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
        Map("id", "google",   "label", "Google",    "group", "mt", "key", "google"),
        Map("id", "microsoft","label", "Microsoft", "group", "mt", "key", "microsoft"),
        Map("id", "modernmt", "label", "ModernMT",  "group", "mt", "key", "modernmt"),
        Map("id", "deepl",    "label", "DeepL",     "group", "mt", "key", "deepl"),
        Map("id", "anthropic","label", "Claude",    "group", "ai", "key", "anthropic"),
        Map("id", "openai",   "label", "OpenAI",    "group", "ai", "key", "openai"),
        Map("id", "gemini",   "label", "Gemini",    "group", "ai", "key", "gemini"),
        Map("id", "mistral",  "label", "Mistral",   "group", "ai", "key", "mistral"),
        Map("id", "deepseek", "label", "DeepSeek",  "group", "ai", "key", "deepseek"),
        Map("id", "openrouter", "label", "OpenRouter", "group", "ai", "key", "openrouter"),
        ; Ollama and the custom endpoint authenticate with nothing, so there
        ; is no missing key to gate them and they would otherwise be asked on
        ; every translation. Both start switched off and are turned on in
        ; Settings once there is actually something listening.
        Map("id", "ollama", "label", "Ollama", "group", "ai", "key", "",
            "default", "0"),
        Map("id", "custom", "label", "Custom", "group", "ai", "key", "",
            "default", "0")
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

; Engines are on unless said otherwise; the keyless ones start off, since
; nothing else would stop them being asked.
QT_EngineDefault(e) {
    return e.Has("default") ? e["default"] : "1"
}

QT_ActiveEngines() {
    out := []
    for e in QT_Engines() {
        if (QT_Setting(e["id"], QT_EngineDefault(e)) = "0")
            continue
        if (e["key"] != "" && Trim(AI_Ini(SettingsFile(), "Keys", e["key"], "")) = "")
            continue
        ; Ollama and the custom endpoint carry no key, so an empty base URL
        ; is what tells us they were never set up. Without this they would be
        ; queried on every translation and fail every time.
        if (e["id"] = "ollama" || e["id"] = "custom") {
            if (AI_Providers()[e["id"]]["base"] = "")
                continue
        }
        out.Push(e)
    }
    return out
}

; ---------------------------------------------------------------------------
; Requests
; ---------------------------------------------------------------------------
QT_BuildRequest(engine, text, srcCode, tgtCode) {
    id  := engine["id"]
    ; Engines with no required key can still take an optional one — a custom
    ; endpoint behind a gateway, say — so look one up under the engine's own
    ; name and simply carry on if there is none.
    key := Trim(AI_Ini(SettingsFile(), "Keys",
                       engine["key"] != "" ? engine["key"] : id, ""))

    r := Map("method", "POST", "headers", Map(), "body", "")

    if (id = "mymemory") {
        r["method"] := "GET"
        r["url"] := "https://api.mymemory.translated.net/get?q="
                  . BB_UriEncode(text) "&langpair="
                  . srcCode "|" tgtCode
        return r
    }

    if (id = "google") {
        ; Google Cloud Translation v2. The key rides in the query string
        ; because that is the only place this endpoint accepts one.
        r["url"] := "https://translation.googleapis.com/language/translate/v2"
                  . "?key=" BB_UriEncode(key)
        r["headers"]["Content-Type"] := "application/json; charset=utf-8"
        body := Map()
        body["q"] := text
        body["source"] := srcCode
        body["target"] := tgtCode
        body["format"] := "text"
        r["body"] := Jxon_Dump(body)
        return r
    }

    if (id = "microsoft") {
        ; Azure Translator wants the resource's region alongside the key;
        ; "global" resources are the common case and the default.
        region := Trim(QT_Setting("microsoft_region", ""))
        if (region = "")
            region := "global"
        r["url"] := "https://api.cognitive.microsofttranslator.com/translate"
                  . "?api-version=3.0&from=" srcCode "&to=" tgtCode
        r["headers"]["Ocp-Apim-Subscription-Key"] := key
        r["headers"]["Ocp-Apim-Subscription-Region"] := region
        r["headers"]["Content-Type"] := "application/json; charset=utf-8"
        r["body"] := Jxon_Dump([Map("text", text)])
        return r
    }

    if (id = "modernmt") {
        r["url"] := "https://api.modernmt.com/translate"
        r["headers"]["MMT-ApiKey"] := key
        r["headers"]["Content-Type"] := "application/json; charset=utf-8"
        body := Map()
        body["q"] := text
        body["source"] := srcCode
        body["target"] := tgtCode
        r["body"] := Jxon_Dump(body)
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
    ; A custom endpoint has no default worth guessing at, so say so rather
    ; than sending an empty model name and getting a puzzling error back.
    if (model = "")
        throw Error("no model set — choose one under Settings, AI providers")
    r["url"] := StrReplace(p["url"], "{model}", model)
    r["headers"]["Content-Type"] := "application/json; charset=utf-8"
    ; A local Ollama has no key; sending "Bearer " with nothing after it is
    ; worse than sending no header at all.
    if (key != "")
        r["headers"][p["auth_header"]] := p["auth_prefix"] key
    if (p["version_header"] != "")
        r["headers"][p["version_header"]] := p["version_value"]

    cfg := Map("maxtokens", QT_Setting("MaxTokens", "1000"),
               "effort", QT_Setting("Effort", "low"))

    ; A custom endpoint is usually a plain MT proxy rather than an
    ; instruction-following model: it translates whatever you send it, so a
    ; wrapped prompt comes back with the instructions translated too. Send
    ; the bare text and put the direction in the system message instead.
    ; Turn this off for an endpoint that really is an LLM.
    opts := Map()
    if (id = "custom" && QT_Setting("custom_raw", "1") != "0") {
        opts["system"] := "Translate from " QT_LangName(srcCode) " into "
                        . QT_LangName(tgtCode)
                        . ". Output only the translated text."
        prompt := text
    }

    r["body"] := AI_BuildBody(id, model, prompt, opts, cfg)
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

    if (id = "google") {
        ; Google returns the translation HTML-escaped whatever format you
        ; ask for, so an apostrophe comes back as &#39;.
        try return QT_HtmlUnescape(Trim(
            data["data"]["translations"][1]["translatedText"]))
        catch
            return ""
    }

    if (id = "microsoft") {
        try return Trim(data[1]["translations"][1]["text"])
        catch
            return ""
    }

    if (id = "modernmt") {
        try return Trim(data["data"]["translation"])
        catch
            return ""
    }

    return Trim(AI_ExtractText(id, raw))
}

QT_HtmlUnescape(t) {
    for pair in [["&#39;", "'"], ["&quot;", '"'], ["&lt;", "<"],
                 ["&gt;", ">"], ["&nbsp;", " "], ["&amp;", "&"]]
        t := StrReplace(t, pair[1], pair[2])
    return t
}

; ---------------------------------------------------------------------------
; Fetch
;
; Returns immediately. QT_Jobs fills in as replies land; QT_OnUpdate is
; called after each poll so the view can redraw.
; ---------------------------------------------------------------------------
QT_Start(text, srcCode, tgtCode, groups := "") {
    global QT_Jobs

    QT_Abort()
    QT_Jobs := []
    return QT_Launch(text, srcCode, tgtCode, groups)
}

; Add engines to a run that has already started. This is what makes holding
; the LLMs back possible: the machine-translation engines answer immediately
; and for nothing, and the paid ones only join in when asked.
QT_StartMore(text, srcCode, tgtCode, groups) {
    return QT_Launch(text, srcCode, tgtCode, groups)
}

; groups is "" for every engine, or an array of group names ("mt", "ai").
QT_Launch(text, srcCode, tgtCode, groups) {
    global QT_Jobs, QT_Running

    added := 0
    for e in QT_ActiveEngines() {
        if (groups != "" && !QT_InGroups(e["group"], groups))
            continue
        if QT_HasJob(e["id"])
            continue

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
            job["text"] := QT_ErrorText(err)
        }
        QT_Jobs.Push(job)
        added++
    }

    if (added > 0) {
        QT_Running := true
        SetTimer(QT_Poll, 120)
    }
    return added
}

QT_InGroups(group, groups) {
    for g in groups {
        if (g = group)
            return true
    }
    return false
}

QT_HasJob(id) {
    global QT_Jobs
    for job in QT_Jobs {
        if (job["engine"]["id"] = id)
            return true
    }
    return false
}

; How many engines a run would still have to ask. Lets a caller offer "fetch
; the LLMs" only when there is something left to fetch.
QT_PendingCount(groups) {
    n := 0
    for e in QT_ActiveEngines() {
        if (groups != "" && !QT_InGroups(e["group"], groups))
            continue
        if !QT_HasJob(e["id"])
            n++
    }
    return n
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
            job["text"] := QT_ErrorText(err)
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
            job["text"] := QT_ErrorText(err)
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

; The same idea for the errors WinHttp raises before there is any HTTP status
; at all. Its own wording runs to three lines of COM boilerplate, which is
; how a local Ollama that simply is not running ends up looking like a crash.
QT_ErrorText(err) {
    msg := err.Message
    for pair in [["0x80072EFD", "nothing listening at that address"],
                 ["0x80072EE7", "server not found"],
                 ["0x80072EE2", "timed out"],
                 ["0x80072F7D", "secure connection failed"],
                 ["0x80072F0D", "certificate rejected"]] {
        if InStr(msg, pair[1])
            return pair[2]
    }
    ; Anything unrecognised: first line only, so one row stays one row.
    return Trim(StrSplit(StrReplace(msg, "`r`n", "`n"), "`n")[1])
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
    providers := AI_Providers()
    if !providers.Has(id)
        return ""
    return providers[id]["base"] = "" ? "" : providers[id]["models_url"]
}
