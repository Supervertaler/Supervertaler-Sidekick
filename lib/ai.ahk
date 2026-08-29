#Requires AutoHotkey v2.0
; ===========================================================================
; lib/ai.ahk — provider-agnostic AI requests.
;
; Replaces the old OpenAI-only ProcessRequest(). Two things changed:
;
;   * The provider is configuration, not code. Claude is the default; OpenAI
;     still works. Adding another vendor means one entry in AI_Providers().
;
;   * Requests no longer block. The old code called WaitForResponse(), which
;     froze every hotkey in the script until the API replied — on a long
;     translation that meant a dead keyboard for half a minute. This opens the
;     request asynchronously and polls on a timer, so the app stays live.
;
; Prompts are data: see the "ai" entry kind in lib/menu_builder.ahk.
; ===========================================================================

global AI_Request     := ""      ; live COM object, "" when idle
global AI_Busy        := false
global AI_LastPrompt  := ""      ; for Retry
global AI_LastOptions := ""
global AI_Window      := ""
global AI_Output      := ""
global AI_Status      := ""
global AI_BtnRetry    := ""
global AI_BtnCopy     := ""
global AI_BtnInsert   := ""

; ---------------------------------------------------------------------------
; Providers.
;
; Each entry describes how to talk to one vendor. The request and response
; shapes differ enough between them that a fully generic JSON-path config
; would be harder to read than two small builder functions, so the shape
; lives in AI_BuildBody() / AI_ExtractText() keyed on the provider name.
; ---------------------------------------------------------------------------
global AI_ProviderCache := ""

; Every OpenAI-compatible service — Mistral, DeepSeek, OpenRouter, Ollama and
; whatever a user points the custom entry at — differs only in where it lives.
; One shape, several base URLs.
AI_OpenAIShaped(label, base, defaultModel, needsKey := true) {
    base := RTrim(Trim(base), "/")
    return Map(
        "label",          label,
        "base",           base,
        "url",            base "/chat/completions",
        "models_url",     base "/models",
        "auth_header",    "Authorization",
        "auth_prefix",    "Bearer ",
        "version_header", "",
        "version_value",  "",
        "default_model",  defaultModel,
        "needs_key",      needsKey
    )
}

AI_Providers() {
    global AI_ProviderCache
    if (AI_ProviderCache != "")
        return AI_ProviderCache

    ini := SettingsFile()

    ; Ollama and the custom entry are wherever the user put them. Ollama has
    ; a conventional home, so it gets a default; a custom endpoint does not,
    ; and stays switched off until someone fills one in.
    ollama := Trim(AI_Ini(ini, "QuickTrans", "ollama_url", ""))
    if (ollama = "")
        ollama := "http://localhost:11434/v1"
    custom := Trim(AI_Ini(ini, "QuickTrans", "custom_url", ""))

    providers := Map(
        "anthropic", Map(
            "label",        "Claude (Anthropic)",
            "base",         "https://api.anthropic.com/v1",
            "url",          "https://api.anthropic.com/v1/messages",
            "models_url",   "https://api.anthropic.com/v1/models",
            "auth_header",  "x-api-key",
            "auth_prefix",  "",
            "version_header", "anthropic-version",
            "version_value",  "2023-06-01",
            "default_model", "claude-opus-5",
            "needs_key",    true
        ),
        "openai", AI_OpenAIShaped("OpenAI",
                                  "https://api.openai.com/v1", "gpt-5"),
        ; Gemini names the model in the URL rather than the body, so its entry
        ; carries a {model} placeholder that the caller fills in.
        "gemini", Map(
            "label",        "Gemini",
            "base",         "https://generativelanguage.googleapis.com/v1beta",
            "url",          "https://generativelanguage.googleapis.com/v1beta/"
                          . "models/{model}:generateContent",
            "models_url",   "https://generativelanguage.googleapis.com/v1beta/"
                          . "models",
            "auth_header",  "x-goog-api-key",
            "auth_prefix",  "",
            "version_header", "",
            "version_value",  "",
            "default_model", "gemini-2.5-flash",
            "needs_key",    true
        ),
        "mistral",    AI_OpenAIShaped("Mistral",
                                      "https://api.mistral.ai/v1",
                                      "mistral-small-latest"),
        "deepseek",   AI_OpenAIShaped("DeepSeek",
                                      "https://api.deepseek.com/v1",
                                      "deepseek-chat"),
        "openrouter", AI_OpenAIShaped("OpenRouter",
                                      "https://openrouter.ai/api/v1",
                                      "anthropic/claude-sonnet-5"),
        ; Local models need no key, so the endpoint is the only gate.
        "ollama",     AI_OpenAIShaped("Ollama (local)", ollama,
                                      "llama3.1", false),
        "custom",     AI_OpenAIShaped("Custom (OpenAI-compatible)", custom,
                                      "", false)
    )

    AI_ProviderCache := providers
    return providers
}

; Called after settings change, so a new endpoint takes effect without a
; reload.
AI_ProvidersReload() {
    global AI_ProviderCache
    AI_ProviderCache := ""
}

SettingsFile() {
    return A_ScriptDir "\settings.ini"
}

; ---------------------------------------------------------------------------
; Configuration. Keys live in settings.ini, which is gitignored — they never
; enter the repository.
; ---------------------------------------------------------------------------
AI_Config() {
    cfg := Map()
    ini := SettingsFile()

    cfg["provider"]  := AI_Ini(ini, "AI", "Provider", "anthropic")
    cfg["model"]     := AI_Ini(ini, "AI", "Model", "")
    cfg["maxtokens"] := AI_Ini(ini, "AI", "MaxTokens", "16000")
    cfg["effort"]    := AI_Ini(ini, "AI", "Effort", "medium")

    providers := AI_Providers()
    if !providers.Has(cfg["provider"])
        cfg["provider"] := "anthropic"

    if (cfg["model"] = "")
        cfg["model"] := providers[cfg["provider"]]["default_model"]

    cfg["key"] := AI_Ini(ini, "Keys", cfg["provider"], "")

    ; Fall back to the old ChatGptAPI.ini so an existing install keeps working
    ; without the user having to move their key by hand.
    if (cfg["key"] = "" && cfg["provider"] = "openai")
        cfg["key"] := AI_Ini(A_ScriptDir "\ChatGptAPI.ini",
                             "ChatGptAPI", "API_Key", "")

    return cfg
}

AI_Ini(file, section, key, default) {
    try
        return IniRead(file, section, key, default)
    catch
        return default
}

; ---------------------------------------------------------------------------
; Public entry point. Called by "ai" menu entries.
;
; opts may carry: system, model, provider, maxtokens, effort, selection.
; ---------------------------------------------------------------------------
AI_Ask(promptText, opts := "") {
    global AI_Busy, AI_LastPrompt, AI_LastOptions

    if !(opts is Map)
        opts := Map()

    if (AI_Busy) {
        if (MsgBox("A request is already running.`n`nCancel it and start "
                   "this one?", "Supervertaler Sidekick AI", "YesNo Icon?") != "Yes")
            return
        AI_Abort()
    }

    ; Let the menu close and focus return to the underlying window before we
    ; send Ctrl+C, otherwise the copy lands on the menu instead of the text.
    Sleep(150)

    selection := ""
    if (GetKey(opts, "selection", "yes") != "no") {
        ; The palette captures the selection when it opens, since by the time
        ; the user has typed a query the focus has long since moved. It hands
        ; the text over in opts["text"] rather than making us copy again.
        selection := GetKey(opts, "text", "")
        if (selection = "")
            selection := SK_CopySelection(2)
        if (selection = "") {
            MsgBox("Select some text first.", "Supervertaler Sidekick AI", "Icon! T2")
            return
        }
    }

    full := promptText
    if (selection != "")
        full .= "`n`n" selection

    AI_LastPrompt  := full
    AI_LastOptions := opts

    AI_ShowWindow()
    AI_SetStatus("Thinking…")
    AI_Output.Value := ""
    AI_EnableButtons(false)
    AI_Start(full, opts)
}

AI_Retry(*) {
    global AI_LastPrompt, AI_LastOptions
    if (AI_LastPrompt = "")
        return
    AI_SetStatus("Retrying…")
    AI_Output.Value := ""
    AI_EnableButtons(false)
    AI_Start(AI_LastPrompt, AI_LastOptions)
}

; ---------------------------------------------------------------------------
AI_Start(promptText, opts) {
    global AI_Request, AI_Busy

    cfg := AI_Config()

    provider := GetKey(opts, "provider", cfg["provider"])
    providers := AI_Providers()
    if !providers.Has(provider)
        provider := cfg["provider"]
    p := providers[provider]

    model := GetKey(opts, "model", "")
    if (model = "")
        model := (provider = cfg["provider"]) ? cfg["model"] : p["default_model"]

    key := cfg["key"]
    if (provider != cfg["provider"])
        key := AI_Ini(SettingsFile(), "Keys", provider, "")

    if (key = "") {
        AI_Fail("No API key for " p["label"] ".`n`n"
                "Add one to settings.ini:`n`n"
                "[Keys]`n" provider "=your-key-here")
        return
    }

    body := AI_BuildBody(provider, model, promptText, opts, cfg)

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(30000, 30000, 30000, 180000)
        ; Gemini puts the model in the path; the others carry it in the body.
        req.Open("POST", StrReplace(p["url"], "{model}", model), true)          ; true = asynchronous
        req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        req.SetRequestHeader(p["auth_header"], p["auth_prefix"] key)
        if (p["version_header"] != "")
            req.SetRequestHeader(p["version_header"], p["version_value"])
        req.Send(body)
    } catch Error as err {
        AI_Fail("Could not send the request:`n`n" err.Message)
        return
    }

    AI_Request := req
    AI_Busy := true
    SetTimer(AI_Poll, 120)
}

; ---------------------------------------------------------------------------
; Poll the in-flight request. This is what keeps the script responsive: the
; timer returns immediately if the reply has not arrived yet, so every other
; hotkey keeps working while Claude thinks.
; ---------------------------------------------------------------------------
AI_Poll() {
    global AI_Request

    if (AI_Request = "") {
        SetTimer(AI_Poll, 0)
        return
    }

    done := false
    try {
        done := AI_Request.WaitForResponse(0)
    } catch Error as err {
        SetTimer(AI_Poll, 0)
        AI_Cleanup()
        AI_Fail("The request failed:`n`n" err.Message)
        return
    }

    if !done
        return

    SetTimer(AI_Poll, 0)
    AI_Finish()
}

AI_Finish() {
    global AI_Request

    req := AI_Request
    if (req = "")
        return

    try {
        status := req.Status
        raw    := AI_ResponseText(req)
    } catch Error as err {
        AI_Cleanup()
        AI_Fail("Could not read the reply:`n`n" err.Message)
        return
    }

    AI_Cleanup()

    if (status != 200) {
        AI_Fail("The API returned status " status ".`n`n" raw)
        return
    }

    provider := AI_ActiveProvider()
    text := AI_ExtractText(provider, raw)

    if (text = "") {
        AI_Fail("The reply contained no text.`n`n" raw)
        return
    }

    AI_SetStatus("Done.")
    AI_Output.Value := text
    AI_EnableButtons(true)
    try AI_Window.Flash()
}

AI_ActiveProvider() {
    global AI_LastOptions
    cfg := AI_Config()
    p := GetKey(AI_LastOptions, "provider", cfg["provider"])
    return AI_Providers().Has(p) ? p : cfg["provider"]
}

; ---------------------------------------------------------------------------
; Request bodies.
; ---------------------------------------------------------------------------
AI_BuildBody(provider, model, promptText, opts, cfg) {
    system := GetKey(opts, "system", "")
    maxTokens := GetKey(opts, "maxtokens", cfg["maxtokens"]) + 0

    if (provider = "anthropic") {
        payload := Map()
        payload["model"] := model
        payload["max_tokens"] := maxTokens
        if (system != "")
            payload["system"] := system
        payload["messages"] := [Map("role", "user", "content", promptText)]

        effort := GetKey(opts, "effort", cfg["effort"])
        if (effort != "")
            payload["output_config"] := Map("effort", effort)

        return Jxon_Dump(payload)
    }

    if (provider = "gemini") {
        parts := []
        if (system != "")
            parts.Push(Map("text", system))
        parts.Push(Map("text", promptText))
        payload := Map()
        payload["contents"] := [Map("parts", parts)]
        payload["generationConfig"] := Map("maxOutputTokens", maxTokens)
        return Jxon_Dump(payload)
    }

    ; OpenAI-shaped: the system prompt is a message, not a field.
    messages := []
    if (system != "")
        messages.Push(Map("role", "system", "content", system))
    messages.Push(Map("role", "user", "content", promptText))

    payload := Map()
    payload["model"] := model
    payload["messages"] := messages
    return Jxon_Dump(payload)
}

; ---------------------------------------------------------------------------
; Response parsing.
; ---------------------------------------------------------------------------
AI_ExtractText(provider, raw) {
    try {
        data := Jxon_Load(&raw)
    } catch {
        return ""
    }

    if (provider = "anthropic") {
        ; content is an array of blocks; take the text ones and join them.
        if !(data is Map) || !data.Has("content")
            return ""
        out := ""
        for block in data["content"] {
            if (block is Map && GetKey(block, "type", "") = "text")
                out .= (out = "" ? "" : "`n") . GetKey(block, "text", "")
        }
        return out
    }

    if (provider = "gemini") {
        try {
            out := ""
            for part in data["candidates"][1]["content"]["parts"] {
                if (part is Map && part.Has("text"))
                    out .= (out = "" ? "" : "`n") part["text"]
            }
            return out
        } catch
            return ""
    }

    ; OpenAI-shaped
    try
        return data["choices"][1]["message"]["content"]
    catch
        return ""
}

; Read the response body as UTF-8. WinHttp hands back a SafeArray of bytes;
; reading .ResponseText instead would mis-decode accented characters.
AI_ResponseText(req) {
    arr := req.ResponseBody
    pData := NumGet(ComObjValue(arr) + 8 + A_PtrSize, "Ptr")
    length := arr.MaxIndex() + 1
    return StrGet(pData, length, "UTF-8")
}

; ---------------------------------------------------------------------------
AI_Abort() {
    global AI_Request
    SetTimer(AI_Poll, 0)
    if (AI_Request != "") {
        try AI_Request.Abort()
    }
    AI_Cleanup()
}

AI_Cleanup() {
    global AI_Request, AI_Busy
    AI_Request := ""
    AI_Busy := false
}

AI_Fail(message) {
    AI_ShowWindow()
    AI_SetStatus("Failed.")
    AI_Output.Value := message
    AI_EnableButtons(true)
}

; ---------------------------------------------------------------------------
; Response window.
; ---------------------------------------------------------------------------
AI_ShowWindow() {
    global AI_Window, AI_Output, AI_Status
    global AI_BtnRetry, AI_BtnCopy, AI_BtnInsert

    if (AI_Window != "") {
        AI_Window.Show()
        return
    }

    AI_Window := Gui("+Resize +MinSize520x300", "Supervertaler Sidekick AI")
    AI_Window.SetFont("s11", "Calibri")
    AI_Window.OnEvent("Close", AI_HideWindow)
    AI_Window.OnEvent("Escape", AI_HideWindow)
    AI_Window.OnEvent("Size", AI_OnSize)

    AI_Status := AI_Window.Add("Text", "xm ym w700", "")
    AI_Output := AI_Window.Add("Edit", "xm y+6 w700 h380 Multi ReadOnly Wrap")

    AI_BtnCopy := AI_Window.Add("Button", "xm y+8 w110", "Copy")
    AI_BtnCopy.OnEvent("Click", AI_Copy)

    AI_BtnInsert := AI_Window.Add("Button", "x+8 w150", "Insert && close")
    AI_BtnInsert.OnEvent("Click", AI_Insert)

    AI_BtnRetry := AI_Window.Add("Button", "x+8 w110", "Retry")
    AI_BtnRetry.OnEvent("Click", AI_Retry)

    AI_Window.Add("Button", "x+8 w110", "Close").OnEvent("Click", AI_HideWindow)

    AI_Window.Show("w730 h480")
}

AI_SetStatus(text) {
    global AI_Status
    try AI_Status.Value := text
}

AI_EnableButtons(on) {
    global AI_BtnRetry, AI_BtnCopy, AI_BtnInsert
    state := on ? 1 : 0
    try {
        AI_BtnRetry.Enabled := state
        AI_BtnCopy.Enabled := state
        AI_BtnInsert.Enabled := state
    }
}

AI_Copy(*) {
    global AI_Output, AI_BtnCopy
    A_Clipboard := AI_Output.Value
    AI_BtnCopy.Text := "Copied"
    SetTimer(() => AI_ResetCopyLabel(), -1500)
}

AI_ResetCopyLabel() {
    global AI_BtnCopy
    try AI_BtnCopy.Text := "Copy"
}

; Put the answer back where the text came from.
AI_Insert(*) {
    global AI_Output
    text := AI_Output.Value
    AI_HideWindow()
    Sleep(120)                 ; let focus return to the original window
    SendText(text)
}

AI_HideWindow(*) {
    global AI_Window, AI_Busy
    if (AI_Busy)
        AI_Abort()
    try AI_Window.Hide()
    return true
}

AI_OnSize(thisGui, minMax, width, height) {
    global AI_Output, AI_Status
    if (minMax = -1)
        return
    w := width - 24
    h := height - 100
    if (h < 80)
        h := 80
    try {
        AI_Status.Move(, , w)
        AI_Output.Move(, , w, h)
    }
}
