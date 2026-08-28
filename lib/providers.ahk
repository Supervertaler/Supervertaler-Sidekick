#Requires AutoHotkey v2.0
; ===========================================================================
; lib/providers.ahk — API keys, endpoints and models, without editing an INI.
;
; One row per engine: on/off, its key, and its model. The model box is a combo
; you can type into or pick from, filled by asking the provider what that key
; can actually use — availability differs by account, so a list baked into the
; app would be wrong for somebody.
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

OpenProviderSettings(*) {
    global PR_Gui, PR_Rows, PR_Status, PR_ShowKeys
    global PR_Ollama, PR_Custom, PR_Region, PR_AutoAI, PR_RawMT

    if (PR_Gui != "") {
        PR_Gui.Show()
        return
    }

    PR_Gui := Gui("+Resize +MinSize700x520", "Text Commander — AI providers")
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

    PR_Gui.Add("Button", "x+6 yp-4 w130 h26", "Fetch all models")
        .OnEvent("Click", (*) => PR_FetchAll())
    PR_Gui.Add("Button", "x+90 yp w90 h26 Default", "Save")
        .OnEvent("Click", (*) => PR_Save())
    PR_Gui.Add("Button", "x+6 yp w80 h26", "Close")
        .OnEvent("Click", (*) => PR_Close())

    PR_Status := PR_Gui.Add("Text", "xm y+14 w660",
                            "Click Models beside an engine to list what your "
                            "key can actually use.")
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
        key := AI_Ini(SettingsFile(), "Keys", id, "")
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
        row["model"].Text := Trim(QT_Setting(id "_model", ""))
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

PR_Fetch(id) {
    global PR_Rows, PR_Status

    row := PR_Rows[id]
    if !row.Has("model")
        return

    ; Ask against whatever is typed in the boxes right now, not what is saved,
    ; so a freshly pasted key or endpoint can be tried before committing.
    PR_ApplyEndpoints()

    p := AI_Providers()[id]
    key := Trim(PR_KeyValue(row))
    if (key = "" && p["needs_key"]) {
        PR_Status.Value := "Enter a key for " p["label"] " first."
        return
    }
    if (p["base"] = "") {
        PR_Status.Value := p["label"] " has no endpoint set."
        return
    }

    PR_Status.Value := "Asking " p["label"] " what it has…"
    r := PR_FetchWithKey(id, key)

    if !r["ok"] {
        PR_Status.Value := p["label"] ": " r["error"]
        return
    }

    keep := row["model"].Text
    row["model"].Delete()
    row["model"].Add(r["models"])
    row["model"].Text := keep          ; do not lose what was typed
    PR_Status.Value := p["label"] ": " r["models"].Length " models. "
                     . "Blank uses the default"
                     . (row["default"] != "" ? " (" row["default"] ")" : "") "."
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
        out["error"] := err.Message
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

PR_FetchAll() {
    global PR_Rows, PR_Status
    done := 0
    for id, row in PR_Rows {
        if !row.Has("model")
            continue
        p := AI_Providers()[id]
        if (p["needs_key"] && Trim(PR_KeyValue(row)) = "")
            continue
        PR_Fetch(id)
        done++
    }
    if (done = 0)
        PR_Status.Value := "No keys entered yet."
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
            if row.Has("masked")
                IniWrite(Trim(PR_KeyValue(row)), ini, "Keys", id)
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
    global PR_Gui, PR_Rows
    try PR_Gui.Destroy()
    PR_Gui := ""
    PR_Rows := Map()
    return true
}
