#Requires AutoHotkey v2.0
; ===========================================================================
; lib/providers.ahk — API keys, endpoints and models, without editing an INI.
;
; One row per engine: on/off, its key, and its model. The model box is a combo
; you can type into or pick from, in two tiers, the way Supervertaler for
; Trados does it: the short list below — the few models worth recommending —
; and, with "Show all models" ticked, everything the provider says that key
; can use. A provider's own list runs to dozens of dated snapshots, previews
; and embedding models, which is no help to someone choosing a translator.
;
; Keys are masked by default. Not because the file is secret — settings.ini
; sits on the user's own disk and never enters the repository — but because a
; window full of API keys is awkward to screenshot, and screenshots of this
; app get shared.
; ===========================================================================

global PR_Gui      := ""
global PR_Rows     := Map()    ; engine id -> Map of that row's controls
global PR_Status   := ""
global PR_ShowKeys := ""
global PR_Ollama   := ""
global PR_Custom   := ""
global PR_Region   := ""
global PR_AutoAI   := ""
global PR_RawMT    := ""
global PR_AllModels := ""      ; the "Show all models" checkbox
global PR_Fetched  := Map()    ; engine id -> what its provider listed, this visit

; ---------------------------------------------------------------------------
; The short list.
;
; Supervertaler for Trados's own, copied from core/src/LlmModels.cs in the
; Supervertaler-Plugin-Core repository on 2026-10-17, so that the two products
; recommend the same models. It is a copy, not a link — Sidekick runs without
; either plugin installed — so when that list changes, change this one.
; Same order as there; the verdict shows on the status line when a model is
; picked.
; ---------------------------------------------------------------------------
PR_ShortList(id) {
    static lists := Map(
        "anthropic", [
            ["claude-sonnet-5-5", "Claude Sonnet 5.5 – recommended: near-Opus "
                . "quality at Sonnet cost ($2/$10 per 1M tokens)"],
            ["claude-opus-5-5", "Claude Opus 5.5 – premium ($4/$20): the top "
                . "choice for hard legal and technical work"],
            ["claude-fable-5-1", "Claude Fable 5.1 – Anthropic's most capable, "
                . "at double Opus pricing, for when cost is secondary"]
        ],
        "openai", [
            ["gpt-6-astra", "GPT-6 Astra – premium ($10/$50 per 1M tokens): "
                . "OpenAI's most capable"],
            ["gpt-6.1-sol", "GPT-6.1 Sol – recommended: close to Astra's "
                . "quality at a fifth of its price ($2/$10)"],
            ["gpt-6-luna", "GPT-6 Luna – budget ($0.10/$0.50): for "
                . "high-volume work where cost matters most"]
        ],
        "gemini", [
            ["gemini-3.8-flash", "Gemini 3.8 Flash – recommended: strong "
                . "quality at $0.75/$3.75 per 1M tokens"],
            ["gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite – budget "
                . "($0.30/$2.50): for high-volume work"],
            ["gemini-3.1-pro-preview", "Gemini 3.1 Pro – Google's most "
                . "capable ($2/$12); still a preview"]
        ],
        "mistral", [
            ["mistral-large-latest", "Mistral Large – flagship, best quality"],
            ["mistral-small-latest", "Mistral Small – fast and cheap"]
        ],
        "deepseek", [
            ["deepseek-v4-pro", "DeepSeek V4 Pro – flagship: strong "
                . "reasoning and multilingual quality"],
            ["deepseek-v4-flash", "DeepSeek V4 Flash – fast and cheap"]
        ],
        "openrouter", [
            ["anthropic/claude-sonnet-5.5", "Claude Sonnet 5.5 – recommended"],
            ["anthropic/claude-opus-5.5", "Claude Opus 5.5 – premium"],
            ["anthropic/claude-fable-5.1", "Claude Fable 5.1 – most capable, "
                . "at double Opus pricing"],
            ["openai/gpt-6-astra", "GPT-6 Astra – OpenAI's most capable"],
            ["openai/gpt-6.1-sol", "GPT-6.1 Sol – close to Astra at a fifth "
                . "of the price"],
            ["openai/gpt-6-luna", "GPT-6 Luna – OpenAI's cheapest"],
            ["google/gemini-3.8-flash", "Gemini 3.8 Flash – strong quality at "
                . "low cost"],
            ["google/gemini-3.1-pro-preview", "Gemini 3.1 Pro – Google's most "
                . "capable; still a preview"],
            ["google/gemma-4-31b-it", "Gemma 4 31B – open weights, strong "
                . "multilingual quality"],
            ["google/gemma-4-26b-a4b-it", "Gemma 4 26B MoE – near-31B quality "
                . "for less"],
            ["mistralai/mistral-small-2603", "Mistral Small 4 – very fast and "
                . "cheap"],
            ["qwen/qwen3.8-27b:free", "Qwen 3.8 27B (free) – rate-limited, "
                . "and free providers may keep what you send: not for "
                . "confidential work"],
            ["deepseek/deepseek-v4-pro", "DeepSeek V4 Pro – flagship"],
            ["deepseek/deepseek-v4-flash", "DeepSeek V4 Flash – fast and "
                . "cheap"]
        ],
        ; Suggestions only: a local server can run what has been pulled onto
        ; it and nothing else, so its own list is the one that counts there.
        "ollama", [
            ["translategemma:12b", "TranslateGemma 12B – best translation "
                . "quality for its size (12 GB RAM)"],
            ["translategemma:4b", "TranslateGemma 4B – lightweight (6 GB RAM)"],
            ["qwen3:14b", "Qwen 3 14B – general-purpose, 100+ languages "
                . "(10 GB RAM)"],
            ["aya-expanse:8b", "Aya Expanse 8B – strong Dutch (8 GB RAM)"]
        ]
    )
    return lists.Has(id) ? lists[id] : []
}

OpenProviderSettings(*) {
    global PR_Gui, PR_Rows, PR_Status, PR_ShowKeys
    global PR_Ollama, PR_Custom, PR_Region, PR_AutoAI, PR_RawMT, PR_AllModels

    if (PR_Gui != "") {
        PR_Gui.Show()
        return
    }

    PR_Gui := Gui("+Resize +MinSize700x520", "Supervertaler Sidekick — AI providers")
    PR_Gui.SetFont("s9", "Segoe UI")
    PR_Gui.OnEvent("Close", PR_Close)
    PR_Gui.OnEvent("Escape", PR_Close)

    PR_Gui.Add("Text", "xm ym w660",
               "Engines QuickTrans asks for a translation. Leave a model "
               "blank to use the provider's default.")

    ; Column widths, shared by the heading row and every engine row.
    cw := Map("name", 104, "key", 268, "model", 178, "btn", 62)
    y  := 40

    PR_Gui.SetFont("s9 Bold")
    PR_Gui.Add("Text", "xm y" y " w" cw["name"], "Engine")
    PR_Gui.Add("Text", "x+6 yp w" cw["key"], "API key")
    PR_Gui.Add("Text", "x+6 yp w" cw["model"], "Model")
    PR_Gui.SetFont("s9 Norm")
    y += 20

    PR_Rows := Map()
    group := ""

    for e in QT_Engines() {
        if (e["group"] != group) {
            group := e["group"]
            PR_Gui.SetFont("s9 Bold")
            PR_Gui.Add("Text", "xm y" (y + 4) " w300",
                       group = "mt" ? "Machine translation" : "AI models")
            PR_Gui.SetFont("s9 Norm")
            y += 24
        }
        PR_Rows[e["id"]] := PR_AddRow(e, y, cw)
        y += 29
    }

    ; ---- endpoints and other odds and ends -------------------------------
    y += 10
    PR_Gui.SetFont("s9 Bold")
    PR_Gui.Add("Text", "xm y" y " w300", "Endpoints")
    PR_Gui.SetFont("s9 Norm")
    y += 22

    ini := SettingsFile()

    PR_Gui.Add("Text", "xm y" (y + 4) " w" cw["name"], "Ollama")
    PR_Ollama := PR_Gui.Add("Edit", "x+6 y" y " w" (cw["key"] + cw["model"])
                                    . " h22",
                            AI_Ini(ini, "QuickTrans", "ollama_url", ""))
    PR_SetCue(PR_Ollama, "http://localhost:11434/v1")
    y += 26

    PR_Gui.Add("Text", "xm y" (y + 4) " w" cw["name"], "Custom")
    PR_Custom := PR_Gui.Add("Edit", "x+6 y" y " w" (cw["key"] + cw["model"])
                                    . " h22",
                            AI_Ini(ini, "QuickTrans", "custom_url", ""))
    PR_SetCue(PR_Custom, "OpenAI-compatible base URL, e.g. "
                       . "http://127.0.0.1:1234/v1")
    y += 26

    PR_Gui.Add("Text", "xm y" (y + 4) " w" cw["name"], "Azure region")
    PR_Region := PR_Gui.Add("Edit", "x+6 y" y " w" cw["key"] " h22",
                            AI_Ini(ini, "QuickTrans", "microsoft_region", ""))
    PR_SetCue(PR_Region, "global")
    y += 26

    PR_RawMT := PR_Gui.Add("CheckBox", "xm y" y " w520",
                           "Send the custom endpoint raw text only "
                           "(it is an MT proxy, not an LLM)")
    PR_RawMT.Value := (AI_Ini(ini, "QuickTrans", "custom_raw", "1") != "0")
    y += 30

    ; ---- behaviour --------------------------------------------------------
    PR_AutoAI := PR_Gui.Add("CheckBox", "xm y" y " w520",
                            "Ask the AI engines automatically "
                            "(otherwise they wait for Ctrl+Shift+Enter)")
    PR_AutoAI.Value := (AI_Ini(ini, "QuickTrans", "AutoFetchAI", "1") != "0")
    y += 30

    PR_ShowKeys := PR_Gui.Add("CheckBox", "xm y" y " w110", "Show keys")
    PR_ShowKeys.OnEvent("Click", (*) => PR_ToggleKeys())

    ; Where "Fetch all models" was: ticking it does exactly that, and then
    ; shows the result, which is all the button was ever for.
    PR_AllModels := PR_Gui.Add("CheckBox", "x+6 yp w140", "Show all models")
    PR_AllModels.OnEvent("Click", (*) => PR_OnShowAll())
    PR_Gui.Add("Button", "x+80 yp-4 w90 h26 Default", "Save")
        .OnEvent("Click", (*) => PR_Save())
    PR_Gui.Add("Button", "x+6 yp w80 h26", "Close")
        .OnEvent("Click", (*) => PR_Close())

    PR_Status := PR_Gui.Add("Text", "xm y+14 w660",
                            "Each model list starts with the few worth "
                            "recommending. Models, or Show all models, adds "
                            "everything your key can use.")
    PR_Gui.Show("w700 h" (y + 90))
}

; One engine's row. Returns the Map of its controls, which also records what
; kind of row it is: whether it has a key field decides how it is read back.
PR_AddRow(e, y, cw) {
    global PR_Gui

    id  := e["id"]
    row := Map()

    row["on"] := PR_Gui.Add("CheckBox", "xm y" (y + 4) " w" cw["name"],
                            e["label"])
    row["on"].Value := (QT_Setting(id, QT_EngineDefault(e)) != "0") ? 1 : 0

    providers := AI_Providers()
    isAI := providers.Has(id)
    ; The keyless engines: MyMemory asks nothing of anyone, Ollama and the
    ; custom endpoint are identified by their URL instead.
    needsKey := (e["key"] != "") || (isAI && providers[id]["needs_key"])

    ; Every Edit gets an explicit height. Left to itself AutoHotkey gives an
    ; Edit three rows, and a column of them then overlaps the rows below —
    ; which, with a masked and an unmasked field stacked, put keys on screen
    ; in plain text.
    if (id = "mymemory") {
        PR_Gui.Add("Text", "x+6 y" (y + 4) " w" cw["key"] " cGray",
                   "free, no key needed")
    } else {
        key := SK_Key(id)   ; shared key file first, settings.ini after
        ; Two fields, one masked and one not; the checkbox swaps them.
        row["masked"] := PR_Gui.Add("Edit", "x+6 y" y " w" cw["key"]
                                          . " h22 Password", key)
        row["plain"]  := PR_Gui.Add("Edit", "xp yp w" cw["key"] " h22", key)
        row["plain"].Visible := false
        if !needsKey
            PR_SetCue(row["masked"], "optional")
    }

    if (isAI) {
        row["model"] := PR_Gui.Add("ComboBox", "x+6 y" (y - 1) " w"
                                             . cw["model"])
        row["model"].Add(PR_Ids(PR_ShortList(id)))
        row["model"].Text := Trim(QT_Setting(id "_model", ""))
        row["model"].OnEvent("Change", PR_MakeDescribe(id))
        row["default"] := providers[id]["default_model"]
        PR_Gui.Add("Button", "x+4 y" (y - 1) " w" cw["btn"] " h23", "Models")
            .OnEvent("Click", PR_MakeFetch(id))
    }

    return row
}

; Grey placeholder text inside an empty field. EM_SETCUEBANNER is 0x1501.
PR_SetCue(ctrl, text) {
    try SendMessage(0x1501, 1, StrPtr(text), ctrl)
}

; ---------------------------------------------------------------------------
PR_ToggleKeys() {
    global PR_Rows, PR_ShowKeys
    show := PR_ShowKeys.Value

    for id, row in PR_Rows {
        if !row.Has("masked")
            continue
        ; Carry whatever was typed across to the field about to be shown.
        if (show) {
            row["plain"].Value := row["masked"].Value
            row["masked"].Visible := false
            row["plain"].Visible := true
        } else {
            row["masked"].Value := row["plain"].Value
            row["plain"].Visible := false
            row["masked"].Visible := true
        }
    }
}

; Whichever of the two key fields is currently in use.
PR_KeyValue(row) {
    global PR_ShowKeys
    if !row.Has("masked")
        return ""
    return PR_ShowKeys.Value ? row["plain"].Value : row["masked"].Value
}

; ---------------------------------------------------------------------------
PR_MakeFetch(id) {
    return (*) => PR_Fetch(id)
}

; The Models button: ask, and show the answer — so it ticks Show all models
; when there is anything beyond the short list, as the Trados plugin's Fetch
; list does. Ticking it in code raises no Click, so this asks one provider,
; not all of them.
PR_Fetch(id) {
    global PR_Rows, PR_Status, PR_AllModels

    row := PR_Rows[id]
    if !row.Has("model")
        return

    ; Ask against whatever is typed in the boxes right now, not what is saved,
    ; so a freshly pasted key or endpoint can be tried before committing.
    PR_ApplyEndpoints()

    p := AI_Providers()[id]
    why := PR_CannotAsk(id)
    if (why != "") {
        PR_Status.Value := why
        return
    }

    PR_Status.Value := "Asking " p["label"] " what it has…"
    r := PR_Ask(id)
    if !r["ok"] {
        PR_Status.Value := p["label"] ": " r["error"]
        return
    }

    extra := PR_ExtraCount(id)
    if (extra > 0 && !PR_AllModels.Value) {
        PR_AllModels.Value := 1
        PR_FillAll()
    } else
        PR_FillModels(id)

    PR_Status.Value := p["label"] ": " r["models"].Length " models"
        . (extra > 0 ? ", " extra " beyond the short list – shown with Show "
                     . "all models ticked."
                     : ", none beyond the short list.")
        . " Blank uses the default"
        . (row["default"] != "" ? " (" row["default"] ")" : "") "."
}

; Why a row cannot be asked yet, in words; "" when it can.
PR_CannotAsk(id) {
    global PR_Rows
    p := AI_Providers()[id]
    if (p["needs_key"] && Trim(PR_KeyValue(PR_Rows[id])) = "")
        return "Enter a key for " p["label"] " first."
    if (p["base"] = "")
        return p["label"] " has no endpoint set."
    return ""
}

; Ask one provider and remember the answer for as long as the window is open.
; Not longer: a list kept across visits would be a list that has gone stale,
; and asking again is one click.
PR_Ask(id) {
    global PR_Rows, PR_Fetched
    r := PR_FetchWithKey(id, Trim(PR_KeyValue(PR_Rows[id])))
    if r["ok"]
        PR_Fetched[id] := r["models"]
    return r
}

; Fill one row's list: the short list, then — when Show all models is ticked
; and the provider has been asked — whatever else it listed, without
; repeating a model the short list already has.
PR_FillModels(id) {
    global PR_Rows, PR_Fetched, PR_AllModels

    row := PR_Rows[id]
    if !row.Has("model")
        return

    items := PR_Ids(PR_ShortList(id))
    if (PR_AllModels != "" && PR_AllModels.Value && PR_Fetched.Has(id)) {
        seen := Map()
        seen.CaseSense := false
        for m in items
            seen[m] := true
        for m in PR_Fetched[id] {
            if !seen.Has(m) {
                seen[m] := true
                items.Push(m)
            }
        }
    }

    keep := row["model"].Text
    row["model"].Delete()
    if (items.Length > 0)
        row["model"].Add(items)
    row["model"].Text := keep          ; do not lose what was typed
}

PR_FillAll() {
    global PR_Rows
    for id, row in PR_Rows
        PR_FillModels(id)
}

; How many of what a provider listed are not on the short list.
PR_ExtraCount(id) {
    global PR_Fetched
    if !PR_Fetched.Has(id)
        return 0
    short := Map()
    short.CaseSense := false
    for m in PR_Ids(PR_ShortList(id))
        short[m] := true
    n := 0
    for m in PR_Fetched[id] {
        if !short.Has(m)
            n++
    }
    return n
}

PR_Ids(list) {
    out := []
    for m in list
        out.Push(m[1])
    return out
}

; The verdict for a short-list model, on the status line as it is picked.
; Typing fires this too, so a name that is not on the list says nothing.
PR_MakeDescribe(id) {
    return (*) => PR_Describe(id)
}

PR_Describe(id) {
    global PR_Rows, PR_Status
    text := Trim(PR_Rows[id]["model"].Text)
    for m in PR_ShortList(id) {
        if (m[1] = text) {
            PR_Status.Value := m[2]
            return
        }
    }
}

; QT_FetchModels reads the saved key; this variant is handed one, so the
; window can test a key that has not been saved yet.
PR_FetchWithKey(id, key) {
    out := Map("ok", false, "models", [], "error", "")

    url := QT_ModelEndpoint(id)
    if (url = "") {
        out["error"] := "no model list"
        return out
    }

    p := AI_Providers()[id]
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 25000)
        req.Open("GET", url, true)
        if (key != "")
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
        ; One line, in words: Show all models reports several engines on the
        ; one status line, and WinHttp's own wording runs to three.
        out["error"] := QT_ErrorText(err)
        return out
    }

    ids := []
    try {
        if (id = "gemini") {
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
        out["error"] := "unexpected reply"
        return out
    }

    out["ok"] := true
    out["models"] := ids
    return out
}

; Show all models. Ticking it asks every engine that can be asked and has not
; been this visit — which is what "Fetch all models" used to do — and then
; shows the lot; unticking it goes back to the short lists. One question at a
; time and each waits for its answer, so a provider that does not answer
; holds the window for up to its 25-second timeout. Engines with no key or no
; endpoint are left out rather than reported as failures.
PR_OnShowAll() {
    global PR_Rows, PR_Status, PR_AllModels, PR_Fetched

    if !PR_AllModels.Value {
        PR_FillAll()
        PR_Status.Value := "Showing the short lists: the few models worth "
                         . "recommending for each engine."
        return
    }

    PR_ApplyEndpoints()
    failed := ""
    for id, row in PR_Rows {
        if !row.Has("model") || PR_Fetched.Has(id) || PR_CannotAsk(id) != ""
            continue
        p := AI_Providers()[id]
        PR_Status.Value := "Asking " p["label"] " what it has…"
        r := PR_Ask(id)
        if !r["ok"]
            failed .= (failed = "" ? "" : "; ") p["label"] ": " r["error"]
    }
    PR_FillAll()

    if (PR_Fetched.Count = 0 && failed = "")
        PR_Status.Value := "No keys entered yet, so there is nothing more "
                         . "to list."
    else
        PR_Status.Value := "Showing every model each engine listed"
                         . (failed != "" ? ", except — " failed : ".")
}

; ---------------------------------------------------------------------------
; The endpoint fields feed AI_Providers(), so write them out and drop the
; cache before anything reads a provider's URL back.
PR_ApplyEndpoints() {
    global PR_Ollama, PR_Custom, PR_Region

    ini := SettingsFile()
    try {
        IniWrite(Trim(PR_Ollama.Value), ini, "QuickTrans", "ollama_url")
        IniWrite(Trim(PR_Custom.Value), ini, "QuickTrans", "custom_url")
        IniWrite(Trim(PR_Region.Value), ini, "QuickTrans", "microsoft_region")
    }
    AI_ProvidersReload()
}

PR_Save() {
    global PR_Rows, PR_Status, PR_AutoAI, PR_RawMT

    ini := SettingsFile()

    try {
        PR_ApplyEndpoints()
        IniWrite(PR_AutoAI.Value ? "1" : "0", ini, "QuickTrans", "AutoFetchAI")
        IniWrite(PR_RawMT.Value ? "1" : "0", ini, "QuickTrans", "custom_raw")

        for id, row in PR_Rows {
            IniWrite(row["on"].Value ? "1" : "0", ini, "QuickTrans", id)
            if row.Has("masked") {
                IniWrite(Trim(PR_KeyValue(row)), ini, "Keys", id)
                ; ... and to the file the Supervertaler plugins read, so a key
                ; pasted here is a key pasted everywhere.
                SK_KeySet(id, PR_KeyValue(row))
            }
            if row.Has("model")
                IniWrite(Trim(row["model"].Text), ini, "QuickTrans",
                         id "_model")
        }
    } catch Error as err {
        PR_Status.Value := "Could not save: " err.Message
        return
    }

    active := QT_ActiveEngines().Length
    PR_Status.Value := "Saved. " active " engine"
                     . (active = 1 ? "" : "s") " will be asked."
}

PR_Close(*) {
    global PR_Gui, PR_Rows, PR_AllModels, PR_Fetched
    try PR_Gui.Destroy()
    PR_Gui := ""
    PR_Rows := Map()
    PR_AllModels := ""
    PR_Fetched := Map()
    return true
}
