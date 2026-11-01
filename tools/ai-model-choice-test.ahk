; tools/ai-model-choice-test.ahk — offline tests for "AI menu actions use:"
; in Settings → AI providers & keys… (lib\providers.ahk, lib\ai.ahk).
;
; Not run on its own. tools\ai-model-choice-test.ps1 points APPDATA - and with
; it the data root (config.json) and the locked key file - at a scratch
; folder, writes a small script there that includes Sidekick's lib files and
; this one, and runs one phase of it at a time, in 64-bit and 32-bit
; AutoHotkey. settings.ini is the scratch folder's too: Sidekick keeps it
; beside the script. The providers window is built but never shown, and the
; AI window is a stand-in that shows nothing. The "send" phase asks a fake
; provider the runner serves on 127.0.0.1, never a real one: every provider's
; address is checked before each request.
;
; Results go to run\results-<phase>-<bits>.txt as PASS / FAIL / INFO lines.
; They never contain a key: keys are compared, not printed.

global T_Root    := A_Args.Length >= 1 ? A_Args[1] : ""
global T_Phase   := A_Args.Length >= 2 ? A_Args[2] : ""
global T_Results := A_ScriptDir "\results-" T_Phase "-" (A_PtrSize * 8) ".txt"
global T_Fails   := 0
global T_FakeUrl := ""

; The test keys. Made up, in the shapes the providers use; the runner checks
; that none of them turns up anywhere but the files meant to hold them.
global KA := "sk-ant-test-Choice-PROJ-001"
global KO := "sk-test-Choice-O-PROJ-001"
global KG := "AIza-test-Choice-PROJ-001"
global KM := "mistral-test-Choice-PROJ-001"
global KR := "sk-or-test-Choice-PROJ-001"
global KL := "sk-test-Choice-Legacy-PROJ-001"

T_Main()

T_Main() {
    DirCreate(A_ScriptDir "\data")          ; for SK_Log's sidekick.log
    T_Guard()
    switch T_Phase, false {
        case "window": T_WindowPhase()
        case "send":   T_SendPhase()
        default:
            T_Line("FAIL  unknown phase '" T_Phase "'")
            ExitApp(2)
    }
    ExitApp(T_Fails ? 1 : 0)
}

; Before anything else: the key files and settings.ini must be in the
; scratch folder, never the user's own. Stops the run otherwise.
T_Guard() {
    plain := SK_File(), locked := SK_LockedFile(), ini := SettingsFile()
    ok := T_Root != "" && StrLen(T_Root) > 10
       && InStr(plain, T_Root "\") = 1 && InStr(locked, T_Root "\") = 1
       && InStr(ini, T_Root "\") = 1 && InStr(DataDir() "\", T_Root "\") = 1
    if !ok {
        T_Line("ABORT  not redirected to the scratch folder: plain=" plain " locked=" locked " ini=" ini)
        ExitApp(2)
    }
    T_Line("INFO  " (A_PtrSize * 8) "-bit AutoHotkey " A_AhkVersion "; settings.ini " ini)
}

; ---------------------------------------------------------------------------
; Phase "window": the providers window, built but never shown.
; ---------------------------------------------------------------------------
T_WindowPhase() {
    FileAppend(KA "`n" KO "`n" KG "`n" KM "`n" KR "`n" KL "`n", T_Root "\keys.txt", "UTF-8")
    T_Shows()
    T_Unknown()
    T_Lists()
    T_Save()
    T_NoKey()
    T_Unreadable()
    T_Legacy()
    T_Layout()
    T_Scale()
}

; Opening the window shows what AI actions use now.
T_Shows() {
    T_Reset()
    T_WritePlain(Map("claude", KA))
    IniWrite("anthropic", SettingsFile(), "AI", "Provider")
    IniWrite("claude-sonnet-5", SettingsFile(), "AI", "Model")
    PR_Build()
    T_Eq(PR_AIUse.Text, "Claude (Anthropic)", "shows: the provider settings.ini names")
    T_Eq(PR_AIModel.Text, "claude-sonnet-5", "shows: a model typed by hand, on no list, as it is - not the list's claude-sonnet-5-5")
    T_Eq(T_Items(PR_AIUse), "Claude (Anthropic)|OpenAI|Gemini|Mistral|DeepSeek|OpenRouter", "shows: the six providers that answer with a key")
    T_Eq(T_Items(PR_AIModel), T_Items(PR_Rows["anthropic"]["model"]), "shows: the same model list as the Claude row")
    T_Eq(PR_Status.Value, "Each model list starts with the few worth recommending. Models, or Show all models, adds "
        . "everything your key can use.", "shows: nothing to say when all is well")
    PR_Close()

    IniWrite("", SettingsFile(), "AI", "Model")
    PR_Build()
    T_Eq(PR_AIModel.Text, "", "shows: a blank model as blank")
    T_Eq(T_Cue(PR_AIModel), "default: claude-opus-5", "shows: the empty box says which default blank means")
    T_Eq(AI_Config()["model"], "claude-opus-5", "shows: which is the one AI actions use")
    PR_Close()

    T_Reset()
    T_WritePlain(Map("claude", KA))
    PR_Build()
    T_Check(PR_AIUse.Text = "Claude (Anthropic)" && PR_AIModel.Text = "", "shows: no [AI] section at all - Claude, its default model")
    PR_Close()

    ; Ollama and the custom endpoint are not offered, but one already chosen
    ; is shown rather than replaced.
    IniWrite("ollama", SettingsFile(), "AI", "Provider")
    PR_Build()
    T_Eq(PR_AIUse.Text, "Ollama (local)", "shows: Ollama, chosen in settings.ini by hand, as it is")
    T_Eq(ControlGetItems(PR_AIUse).Length, 7, "shows: added to the list for this visit only")
    PR_Close()
}

; A provider settings.ini names that Sidekick doesn't know: AI actions use
; Claude, and so does the window, and says why.
T_Unknown() {
    T_Reset()
    T_WritePlain(Map("claude", KA))
    IniWrite("acme-ai", SettingsFile(), "AI", "Provider")
    IniWrite("acme-model-1", SettingsFile(), "AI", "Model")
    PR_Build()
    T_Eq(PR_AIUse.Text, "Claude (Anthropic)", "unknown provider: shows the one in effect")
    T_Eq(PR_AIModel.Text, "acme-model-1", "unknown provider: with the model settings.ini gives")
    cfg := AI_Config()
    T_Check(cfg["provider"] = "anthropic" && cfg["model"] == "acme-model-1", "unknown provider: exactly what AI actions use")
    T_Eq(PR_Status.Value, "settings.ini names a provider Sidekick doesn't know (acme-ai), so AI menu actions use "
        . "Claude (Anthropic).", "unknown provider: and says so")
    PR_Save()
    T_Eq(IniRead(SettingsFile(), "AI", "Provider"), "anthropic", "unknown provider: Save writes the one in effect")
    PR_Close()
}

; The model lists are the rows' own: short list, and what Models or Show all
; models fetched.
T_Lists() {
    global PR_Fetched
    T_Reset()
    T_WritePlain(Map("claude", KA, "gemini", KG))
    PR_Build()
    T_Choose("gemini")
    T_Eq(PR_AIModel.Text, "", "lists: another provider starts blank, at its default")
    T_Eq(T_Cue(PR_AIModel), "default: gemini-2.5-flash", "lists: and the box says which")
    short := "gemini-3.8-flash|gemini-3.5-flash-lite|gemini-3.1-pro-preview"
    T_Eq(T_Items(PR_AIModel), short, "lists: that provider's short list")
    T_Eq(PR_Status.Value, "Click Save to use Gemini for AI menu actions.", "lists: says what Save will do")

    PR_Fetched["gemini"] := ["gemini-3.8-flash", "gemini-4-argon", "GEMINI-3.1-PRO-PREVIEW", "gemini-2.5-flash"]
    PR_AIModel.Text := "acme-tuned-gemini"
    PR_AllModels.Value := 1
    PR_FillAll()
    T_Eq(T_Items(PR_AIModel), short "|gemini-4-argon|gemini-2.5-flash", "lists: Show all models adds what the provider listed, once each")
    T_Eq(T_Items(PR_AIModel), T_Items(PR_Rows["gemini"]["model"]), "lists: the same as the Gemini row's")
    T_Eq(PR_AIModel.Text, "acme-tuned-gemini", "lists: and keeps what was typed")
    PR_AllModels.Value := 0
    PR_FillAll()
    T_Eq(T_Items(PR_AIModel), short, "lists: unticked, the short list again")

    T_Choose("anthropic")
    T_Eq(T_Items(PR_AIModel), "claude-sonnet-5-5|claude-opus-5-5|claude-fable-5-1", "lists: back to Claude, Claude's list")
    PR_AIModel.Text := "claude-opus-5-5"
    PR_Describe(PR_AIChosen(), PR_AIModel)
    T_Check(InStr(PR_Status.Value, "Claude Opus 5.5 " Chr(0x2013) " premium") = 1, "lists: a short-list model's verdict on the status line, as in the rows")
    PR_Close()
}

; Save writes [AI] Provider and Model and nothing else of settings.ini's
; changes; AI actions use it at once.
T_Save() {
    T_Reset()
    example := T_Repo() "\settings.example.ini"
    FileCopy(example, SettingsFile(), true)
    T_WritePlain(Map("claude", KA))
    before := T_Lines(example)

    PR_Build()
    T_Choose("openai")
    T_Eq(PR_Status.Value, "AI menu actions can't use OpenAI yet. There is no OpenAI key " Chr(0x2013) " paste one into the "
        . "OpenAI row below.", "save: no key, said as soon as it is picked")
    PR_Rows["openai"]["masked"].Value := KO
    PR_AIModel.Text := "gpt-6.1-sol"
    PR_Save()
    T_Check(InStr(PR_Status.Value, " AI menu actions now use OpenAI, gpt-6.1-sol."), "save: says what AI menu actions now use", PR_Status.Value)
    T_Eq(IniRead(SettingsFile(), "AI", "Provider"), "openai", "save: [AI] Provider")
    T_Eq(IniRead(SettingsFile(), "AI", "Model"), "gpt-6.1-sol", "save: [AI] Model")
    cfg := AI_Config()
    T_Check(cfg["provider"] = "openai" && cfg["model"] == "gpt-6.1-sol", "save: AI actions use it at once - no reload")
    T_Same(cfg["key"], KO, "save: with the key pasted in the same visit")

    after := T_Lines(SettingsFile())
    T_Eq(T_Comments(after), T_Comments(before), "save: every comment in settings.ini kept, in order, accented and dashed ones too")
    T_Eq(T_Changed(before, after, "AI"), "Model|Provider", "save: in [AI], only Provider and Model changed")
    T_Check(IniRead(SettingsFile(), "AI", "MaxTokens") = "16000" && IniRead(SettingsFile(), "AI", "Effort") = "medium",
        "save: MaxTokens and Effort left as they were")
    b := T_Bytes(SettingsFile())
    T_Check(b.Size > 3 && NumGet(b, 0, "UChar") = 0xEF && NumGet(b, 1, "UChar") = 0xBB && NumGet(b, 2, "UChar") = 0xBF,
        "save: the file still starts with its UTF-8 mark")
    PR_Close()

    ; Blank: the provider's default.
    PR_Build()
    T_Eq(PR_AIModel.Text, "gpt-6.1-sol", "save: shown again next time")
    PR_AIModel.Text := ""
    PR_Save()
    T_Check(InStr(PR_Status.Value, " AI menu actions now use OpenAI, its default model, gpt-5."), "save: blank, said as the default", PR_Status.Value)
    T_Eq(IniRead(SettingsFile(), "AI", "Model"), "", "save: written blank")
    T_Eq(AI_Config()["model"], "gpt-5", "save: AI actions use the default")
    PR_Close()

    ; Nothing changed: nothing said, [AI] not written.
    PR_Build()
    before := T_Lines(SettingsFile())
    PR_Save()
    T_Check(!InStr(PR_Status.Value, "AI menu actions"), "save: with the choice untouched, nothing said about it")
    T_Eq(T_Changed(before, T_Lines(SettingsFile()), "AI"), "", "save: and [AI] left alone")
    PR_Close()
}

; A switch to a provider with no key is not saved; the rest of the window is.
T_NoKey() {
    T_Reset()
    T_WritePlain(Map("openai", KO))
    IniWrite("openai", SettingsFile(), "AI", "Provider")
    IniWrite("gpt-6.1-sol", SettingsFile(), "AI", "Model")
    PR_Build()
    T_Choose("gemini")
    PR_AIModel.Text := "gemini-3.8-flash"
    PR_Rows["mymemory"]["on"].Value := 0
    PR_Save()
    T_Check(InStr(PR_Status.Value, " AI menu actions still use OpenAI, not Gemini. There is no Gemini key " Chr(0x2013)
        . " paste one into the Gemini row below."), "no key: not saved, and says why", PR_Status.Value)
    T_Check(IniRead(SettingsFile(), "AI", "Provider") = "openai" && IniRead(SettingsFile(), "AI", "Model") = "gpt-6.1-sol",
        "no key: settings.ini keeps OpenAI")
    T_Eq(AI_Config()["provider"], "openai", "no key: AI actions still use OpenAI")
    T_Eq(IniRead(SettingsFile(), "QuickTrans", "mymemory"), "0", "no key: the rest of the window is saved")
    T_Eq(PR_AIUse.Text, "Gemini", "no key: the pick stays in the window, to paste the key and save again")

    PR_Rows["gemini"]["masked"].Value := KG
    PR_Save()
    T_Check(IniRead(SettingsFile(), "AI", "Provider") = "gemini" && IniRead(SettingsFile(), "AI", "Model") = "gemini-3.8-flash",
        "no key: with the key pasted, saved")
    T_Check(T_PlainHas("gemini", KG) && T_LockedUnlocks("gemini", KG), "no key: the key saved in both key files, as any key")
    PR_Close()

    ; The provider in effect has no key: said when the window opens.
    T_Reset()
    IniWrite("mistral", SettingsFile(), "AI", "Provider")
    PR_Build()
    T_Eq(PR_Status.Value, "AI menu actions can't use Mistral yet. There is no Mistral key " Chr(0x2013) " paste one into the "
        . "Mistral row below.", "no key: said when the window opens")
    ; A new model for the same provider changes nothing about its key.
    PR_AIModel.Text := "mistral-large-latest"
    PR_Save()
    T_Eq(IniRead(SettingsFile(), "AI", "Model"), "mistral-large-latest", "no key: a new model for the same provider is saved")
    T_Check(InStr(PR_Status.Value, " AI menu actions now use Mistral, mistral-large-latest. There is no Mistral key"),
        "no key: and the key is still asked for", PR_Status.Value)
    PR_Close()
}

; A stored key this account can't unlock (M1) counts as no key, in M1's words.
T_Unreadable() {
    T_Reset()
    T_WritePlain(Map("openai", KO))
    blob := T_LockWithEntropy(KG)
    T_WriteLocked(Map("gemini", blob))
    IniWrite("openai", SettingsFile(), "AI", "Provider")
    PR_Build()
    T_Choose("gemini")
    T_Eq(PR_Status.Value, "AI menu actions can't use Gemini yet. " T_M1("Gemini"), "can't be read: M1, word for word, when picked")
    PR_Save()
    T_Check(InStr(PR_Status.Value, " AI menu actions still use OpenAI, not Gemini. " T_M1("Gemini")), "can't be read: not saved", PR_Status.Value)
    T_Eq(IniRead(SettingsFile(), "AI", "Provider"), "openai", "can't be read: settings.ini keeps OpenAI")
    T_Check(T_LockedRaw()["gemini"] == blob, "can't be read: the stored key is kept")
    PR_Close()

    IniWrite("gemini", SettingsFile(), "AI", "Provider")
    PR_Build()
    T_Eq(PR_Status.Value, "AI menu actions can't use Gemini yet. " T_M1("Gemini"), "can't be read: said when the window opens")
    T_Eq(AI_Config()["keyproblem"], T_M2("Gemini"), "can't be read: and an AI action says M2 instead of asking")
    PR_Close()
}

; ChatGptAPI.ini's old OpenAI key counts, as it does for AI actions - but not
; past an OpenAI key that can't be read.
T_Legacy() {
    T_Reset()
    T_WritePlain(Map("claude", KA))
    IniWrite(KL, A_ScriptDir "\ChatGptAPI.ini", "ChatGptAPI", "API_Key")
    PR_Build()
    T_Choose("openai")
    T_Eq(PR_Status.Value, "Click Save to use OpenAI for AI menu actions.", "old key: ChatGptAPI.ini's OpenAI key counts")
    PR_Save()
    T_Eq(IniRead(SettingsFile(), "AI", "Provider"), "openai", "old key: saved")
    T_Same(AI_Config()["key"], KL, "old key: and AI actions use it")
    PR_Close()

    IniWrite("anthropic", SettingsFile(), "AI", "Provider")
    T_WriteLocked(Map("openai", T_LockWithEntropy(KO)))
    PR_Build()
    T_Choose("openai")
    PR_Save()
    T_Eq(IniRead(SettingsFile(), "AI", "Provider"), "anthropic", "old key: not past an OpenAI key that can't be read")
    PR_Close()
    FileDelete(A_ScriptDir "\ChatGptAPI.ini")
}

; One row, above everything else, overlapping nothing; and the window still
; fits this computer's main screen.
T_Layout() {
    T_Reset()
    h := PR_Build()
    PR_AIUse.GetPos(, &uy, , &uh)
    PR_AIModel.GetPos(, &my, , &mh)
    bottom := Max(uy + uh, my + mh)
    over := ""
    for hwnd, ctl in PR_Gui {
        if (ctl = PR_AIUse || ctl = PR_AIModel || ctl.Text == "AI menu actions use:")
            continue
        ctl.GetPos(, &cy)
        if (cy < bottom)
            over .= ctl.Type ": " ctl.Text "; "
    }
    T_Eq(over, "", "layout: one row at the top, with everything else below it")
    PR_Gui.Show("Hide w700 h" h)            ; sized, not shown
    DetectHiddenWindows(true)
    WinGetPos(, , , &outer, PR_Gui.Hwnd)
    DetectHiddenWindows(false)
    ; The window opens on the main screen but may be dragged to any: the
    ; lowest one is the one that counts.
    lowest := 100000
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, , &top, , &bot)
        lowest := Min(lowest, bot - top)
    }
    T_Info("window " h " high inside, " outer " px outside at " A_ScreenDPI " dpi; the lowest screen's work area is "
        . lowest " px")
    T_Check(outer <= lowest, "layout: the window fits the height of every screen on this computer")
    PR_Close()
}

; Long fetched lists: OpenRouter lists a few hundred models.
T_Scale() {
    global PR_Fetched
    T_Reset()
    T_WritePlain(Map("openrouter", KR))
    IniWrite("openrouter", SettingsFile(), "AI", "Provider")
    for n in [400, 4000] {
        PR_Build()
        big := []
        Loop n
            big.Push("acme/model-" A_Index)
        PR_Fetched["openrouter"] := big
        PR_AllModels.Value := 1
        t := T_Clock()
        PR_FillAll()
        ms := T_Clock() - t
        T_Eq(ControlGetItems(PR_AIModel).Length, PR_ShortList("openrouter").Length + n,
            "scale: " n " listed models all reach the AI menu actions list")
        t := T_Clock()
        PR_FillAIModels()
        mine := T_Clock() - t
        T_Info("filling every list with " n " OpenRouter models: " Round(ms) " ms, of which the AI menu actions list "
            . Round(mine) " ms")
        if (n = 400)
            T_Check(ms < 1000, "scale: a real-sized list (" n ") fills in under a second")
        PR_Close()
    }
}

; ---------------------------------------------------------------------------
; Phase "send": AI actions ask a fake provider on 127.0.0.1, which answers
; with what it was sent: "fake <provider> #<n> | model <m> | <auth header> <length>".
; ---------------------------------------------------------------------------
T_SendPhase() {
    global T_FakeUrl
    T_FakeUrl := "http://127.0.0.1:" Trim(FileRead(T_Root "\fake-port.txt"))
    T_QuietAIWindow()
    T_Reset()
    T_WritePlain(Map("claude", KA, "openai", KO))
    IniWrite("anthropic", SettingsFile(), "AI", "Provider")
    IniWrite("claude-sonnet-5", SettingsFile(), "AI", "Model")
    ask := () => AI_Ask("Check PROJ-001 for Acme.", Map("selection", "no"))

    T_Eq(T_Send(ask), "fake anthropic #1 | model claude-sonnet-5 | x-api-key " StrLen(KA),
        "send: settings.ini's provider and hand-typed model, with its key")

    PR_Build()
    T_Choose("openai")
    PR_AIModel.Text := "gpt-6.1-sol"
    PR_Save()
    PR_Close()
    T_Eq(T_Send(ask), "fake openai #2 | model gpt-6.1-sol | authorization " StrLen("Bearer " KO),
        "send: the provider and model picked in the window, at once")

    entry := Map("kind", "ai", "label", "Acme", "prompt", "Check PROJ-001.", "selection", "no")
    entry["provider"] := "anthropic", entry["model"] := "claude-opus-5-5"
    T_Eq(T_Send(HandlerAI(entry)), "fake anthropic #3 | model claude-opus-5-5 | x-api-key " StrLen(KA),
        "send: a menu entry's own provider and model still win")
    entry.Delete("provider"), entry["model"] := "gpt-6-luna"
    T_Eq(T_Send(HandlerAI(entry)), "fake openai #4 | model gpt-6-luna | authorization " StrLen("Bearer " KO),
        "send: an entry's own model, with the provider picked in the window")
    entry.Delete("model"), entry["provider"] := "anthropic"
    T_Eq(T_Send(HandlerAI(entry)), "fake anthropic #5 | model claude-opus-5 | x-api-key " StrLen(KA),
        "send: an entry's own provider, with that provider's default model")

    PR_Build()
    PR_AIModel.Text := ""
    PR_Save()
    PR_Close()
    T_Eq(T_Send(ask), "fake openai #6 | model gpt-5 | authorization " StrLen("Bearer " KO),
        "send: blank in the window, the provider's default")

    ; Past the window, by hand: a provider with no key, then one whose key
    ; can't be read. Neither sends anything - the next request is #7.
    IniWrite("gemini", SettingsFile(), "AI", "Provider")
    T_Eq(T_Send(ask), "No API key for Gemini.`n`nAdd one to settings.ini:`n`n[Keys]`ngemini=your-key-here",
        "send: no key, no request - AI_Start says so")
    T_WriteLocked(Map("gemini", T_LockWithEntropy(KG)))
    T_Eq(T_Send(ask), T_M2("Gemini"), "send: a key that can't be read, no request - M2")
    T_WritePlain(Map("claude", KA, "openai", KO, "gemini", KG))
    T_Eq(T_Send(ask), "fake gemini #7 | model gemini-2.5-flash | x-goog-api-key " StrLen(KG),
        "send: with a key, Gemini - and nothing was sent in between")

    log := FileExist(T_Root "\fake-requests.txt") ? FileRead(T_Root "\fake-requests.txt", "UTF-8") : ""
    StrReplace(log, "`n", , , &lines)
    T_Eq(lines, 7, "send: the fake provider was asked exactly 7 times")
}

; Every provider points at the fake one. AI_ProvidersReload (Save does it)
; drops this, so it is set again before each request, and checked.
T_FakeProviders() {
    AI_ProvidersReload()
    for id, p in AI_Providers() {
        p["base"] := T_FakeUrl "/" id
        p["url"] := T_FakeUrl "/" id (id = "anthropic" ? "/messages"
                  : id = "gemini" ? "/models/{model}:generateContent" : "/chat/completions")
        p["models_url"] := T_FakeUrl "/" id "/models"
    }
}

; One AI action, start to finish: what the AI window would show.
T_Send(action) {
    global AI_Busy, AI_Answer
    T_FakeProviders()
    for id, p in AI_Providers() {
        for k in ["base", "url", "models_url"] {
            if (InStr(p[k], T_FakeUrl "/") != 1) {
                T_Line("ABORT  " id " " k " is not the fake provider: " p[k])
                ExitApp(2)
            }
        }
    }
    action.Call()
    deadline := A_TickCount + 20000
    while (AI_Busy && A_TickCount < deadline)
        Sleep(20)
    if AI_Busy {
        AI_Abort()
        return "(no answer within 20 s)"
    }
    return AI_Answer["raw"]
}

; The AI window's parts, as stand-ins that show nothing - but for the answer
; box, which is a real one, in a window that is never shown.
T_QuietAIWindow() {
    global AI_Window, AI_Output, AI_Status, AI_BtnRetry, AI_BtnCopy, AI_BtnInsert
    static hidden := Gui()
    AI_Window := {Show: (*) => 0, Hide: (*) => 0, Flash: (*) => 0}
    AI_Output := AI_AddAnswerBox(hidden, "w700 h380")
    AI_Status := {Value: ""}
    AI_BtnRetry := {Enabled: 0}, AI_BtnCopy := {Enabled: 0}, AI_BtnInsert := {Enabled: 0}
}

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; Pick a provider in "AI menu actions use:" as a click would.
T_Choose(id) {
    for i, have in PR_AIIds {
        if (have = id) {
            PR_AIUse.Choose(i)
            PR_OnAIProvider()
            return
        }
    }
    T_Check(false, "pick " id ": not on the list")
}

T_Items(ctrl) {
    out := ""
    for item in ControlGetItems(ctrl)
        out .= (out = "" ? "" : "|") item
    return out
}

; The grey text an empty combo box shows. CB_GETCUEBANNER is 0x1704.
T_Cue(box) {
    buf := Buffer(512, 0)
    SendMessage(0x1704, buf.Ptr, 256, box)
    return StrGet(buf)
}

T_Repo() {
    SplitPath(A_LineFile, , &dir)
    SplitPath(dir, , &repo)
    return repo
}

T_Lines(path) => StrSplit(StrReplace(T_Text(path), "`r`n", "`n"), "`n")

T_Comments(lines) {
    out := ""
    for l in lines {
        if (SubStr(LTrim(l, " `t" Chr(0xFEFF)), 1, 1) = ";")
            out .= l "`n"
    }
    return out
}

; The keys of one section whose lines differ, sorted, |-separated.
T_Changed(before, after, section) {
    a := T_Section(before, section), b := T_Section(after, section)
    names := Map()
    for k, v in a {
        if (!b.Has(k) || b[k] !== v)
            names[k] := true
    }
    for k, v in b {
        if !a.Has(k)
            names[k] := true
    }
    out := ""
    for k in names
        out .= (out = "" ? "" : "|") k
    return out
}

T_Section(lines, section) {
    m := Map(), inside := false
    for l in lines {
        t := Trim(l)
        if (SubStr(t, 1, 1) = "[") {
            inside := (t = "[" section "]")
            continue
        }
        if (inside && SubStr(t, 1, 1) != ";" && (i := InStr(t, "=")))
            m[Trim(SubStr(t, 1, i - 1))] := Trim(SubStr(t, i + 1))
    }
    return m
}

; Back to nothing: no key files, an empty settings.ini, no fetched lists.
; Locked files are moved to scan\, where the runner checks that no key text
; is in any of them.
T_Reset() {
    global PR_Fetched
    static n := 0
    Loop Files, T_Dir(SK_File()) "\api-keys*"
        FileDelete(A_LoopFileFullPath)
    DirCreate(T_Root "\scan")
    Loop Files, T_Dir(SK_LockedFile()) "\api-keys*"
        FileMove(A_LoopFileFullPath, T_Root "\scan\" T_Phase "-" (A_PtrSize * 8) "-" (++n) "-" A_LoopFileName)
    try FileDelete(SettingsFile())
    try FileDelete(A_ScriptDir "\ChatGptAPI.ini")
    PR_Fetched := Map()
    AI_ProvidersReload()
}

T_Line(s) {
    global T_Results
    FileAppend(s "`n", T_Results, "UTF-8")
}

T_Check(cond, name, detail := "") {
    global T_Fails
    if !cond
        T_Fails++
    T_Line((cond ? "PASS  " : "FAIL  ") name (detail != "" && !cond ? "  -- " detail : ""))
}

; For sentences, names and counts - never for keys.
T_Eq(actual, expected, name) {
    T_Check(actual == expected, name, "got: " actual " | expected: " expected)
}

; For keys: says whether they match, never what they are.
T_Same(actual, expected, name) {
    T_Check(actual == expected, name, actual = "" ? "got none" : "got a different key")
}

T_Info(s) => T_Line("INFO  " s)

T_Dir(path) {
    SplitPath(path, , &dir)
    return dir
}

T_Bytes(path) => FileExist(path) ? FileRead(path, "RAW") : Buffer(0)
T_Text(path) => SK_Decode(T_Bytes(path))

T_WriteText(path, text) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

T_WritePlain(m) => T_WriteText(SK_File(), Jxon_Dump(m, 2))
T_WriteLocked(m) => T_WriteText(SK_LockedFile(), SK_RenderLocked(m))

T_PlainHas(id, key) {
    text := T_Text(SK_File())
    try m := Jxon_Load(&text)
    catch
        return false
    return m.Has(id) && m[id] == key
}

T_LockedRaw() => SK_ParseLocked(T_Text(SK_LockedFile()), &e) ? e : SK_NewMap()

T_LockedUnlocks(id, key) {
    m := T_LockedRaw()
    return m.Has(id) && SK_Unlock(m[id], &k, &e) && k == key
}

T_M1(name) => "Your " name " key can't be read on this computer " Chr(0x2013) " it was saved under another Windows sign-in, "
            . "or your Windows password was reset. Paste the key in again; nothing else is affected."
T_M2(name) => "Can't use your " name " key " Chr(0x2013) " it can't be read on this computer (saved under another Windows sign-in, "
            . "or your Windows password was reset). Paste it in again in Settings " Chr(0x2192) " AI providers."

T_Clock() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &now := 0)
    return now * 1000 / freq
}

; A key locked the way no product locks one - with an entropy - so the
; contract's call refuses it, as it would one from another Windows account.
T_LockWithEntropy(key) {
    size := StrPut(key, "UTF-8") - 1
    plain := Buffer(size + 1)
    StrPut(key, plain, "UTF-8")
    entropy := Buffer(8)
    StrPut("PROJ-001", entropy, 8, "CP0")
    out := SK_Blob()
    DllCall("crypt32\CryptProtectData", "Ptr", SK_Blob(plain.Ptr, size), "Ptr", 0, "Ptr", SK_Blob(entropy.Ptr, 8),
            "Ptr", 0, "Ptr", 0, "UInt", 0x1, "Ptr", out, "Int")
    p := NumGet(out, A_PtrSize, "Ptr")
    try return SK_Base64(p, NumGet(out, 0, "UInt"))
    finally DllCall("LocalFree", "Ptr", p, "Ptr")
}
