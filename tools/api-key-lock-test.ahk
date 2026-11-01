; tools/api-key-lock-test.ahk — offline tests for step 1 of "API keys locked
; to the computer" (lib\sharedkeys.ahk; Plugin Core,
; docs/design/api-key-protection.md).
;
; Not run on its own. tools\api-key-lock-test.ps1 points APPDATA - and with it
; the data root (config.json) and the locked key file - at a scratch folder,
; writes a small script there that includes Sidekick's lib files and this one,
; and runs one phase of it at a time, in 64-bit and 32-bit AutoHotkey. The
; phases between them check against Plugin Core itself, hold files open, and
; kill a save half-way. Nothing here starts Sidekick, registers a hotkey or
; shows a window.
;
; Results go to run\results-<phase>-<bits>.txt as PASS / FAIL / INFO lines.
; They never contain a key: keys are compared, not printed.

global T_Root    := A_Args.Length >= 1 ? A_Args[1] : ""
global T_Phase   := A_Args.Length >= 2 ? A_Args[2] : ""
global T_Results := A_ScriptDir "\results-" T_Phase "-" (A_PtrSize * 8) ".txt"
global T_Fails   := 0

; The test keys. Made up, in the shapes the providers use; the runner checks
; that none of them turns up anywhere but the plain files.
global K1  := "sk-ant-test-K1-PROJ-001"
global K2  := "sk-ant-test-K2-PROJ-001"
global O1  := "sk-test-O1-PROJ-001"
global O2  := "sk-test-O2-PROJ-001"
global DL  := "deepl-test-Acme-PROJ-001:fx"
global GT  := "gt-test-Acme-PROJ-001"
global GEM := "AIza-test-Acme-PROJ-001"
global MI  := "mistral-test-Acme-PROJ-001"
global UNI := "sk-test-Acm" Chr(0xE9) "-" Chr(0xDC) "ber-PROJ-001"
global KEY_OLD := "sk-ant-test-Old-PROJ-001"
global KEY_ELSE := "sk-ant-test-Elsewhere-PROJ-001"
global KEY_LEGACY := "sk-test-Legacy-PROJ-001"
global KEY_ACME := "sk-test-AcmeServer-PROJ-001"
global KEY_WB  := "sk-test-Workbench-PROJ-001"

T_Main()

T_Main() {
    global T_Fails
    DirCreate(A_ScriptDir "\data")          ; for SK_Log's sidekick.log
    T_Guard()
    switch T_Phase, false {
        case "unit":        T_Unit()
        case "cross-lock":  T_CrossLock()
        case "cross-read":  T_CrossRead()
        case "render":      T_Render()
        case "messages":    T_Messages()
        case "held-setup":  T_HeldSetup()
        case "held-locked": T_HeldLocked()
        case "after-held":  T_AfterHeld()
        case "held-plain":  T_HeldPlain()
        case "race":        T_Race()
        case "kill-loop":   T_KillLoop()
        default:
            T_Line("FAIL  unknown phase '" T_Phase "'")
            ExitApp(2)
    }
    ExitApp(T_Fails ? 1 : 0)
}

; Before anything else: both files Sidekick writes must be in the scratch
; folder, never the user's own. Stops the run otherwise.
T_Guard() {
    plain := SK_File(), locked := SK_LockedFile()
    ok := T_Root != "" && StrLen(T_Root) > 10
       && InStr(plain, T_Root "\") = 1 && InStr(locked, T_Root "\") = 1
       && InStr(A_ScriptDir "\", T_Root "\") = 1
    if !ok {
        T_Line("ABORT  key files not redirected to the scratch folder: plain=" plain " locked=" locked)
        ExitApp(2)
    }
    if (T_Phase = "unit")
        T_Line("INFO  " (A_PtrSize * 8) "-bit AutoHotkey " A_AhkVersion "; plain " plain "; locked " locked)
}

; ---------------------------------------------------------------------------
; Phase "unit": everything that needs no other process.
; ---------------------------------------------------------------------------
T_Unit() {
    FileAppend(T_KeyList(), T_Root "\keys.txt", "UTF-8")
    T_Contract()
    T_RoundTrip()
    T_ReadOrder()
    T_Unreadable()
    T_Tampered()
    T_Damaged()
    T_ParseStrict()
    T_Missing()
    T_Sync()
    T_Unknown()
    T_NoBlankKey()
    T_Window()
    T_Sweep()
    T_Timing()
}

T_KeyList() {
    out := ""
    for k in [K1, K2, O1, O2, DL, GT, GEM, MI, UNI, KEY_OLD, KEY_ELSE, KEY_LEGACY, KEY_ACME, KEY_WB]
        out .= k "`n"
    return out
}

; The contract every product keeps: the key's UTF-8 bytes, no terminating
; zero; CryptProtectData, current user, no entropy; base64 on one line.
T_Contract() {
    blob := SK_Lock(K1)
    T_Check(RegExMatch(blob, "^[A-Za-z0-9+/]+={0,2}$"), "contract: standard base64, padded, on one line")
    T_Check(SubStr(blob, 1, 28) == "AQAAANCMnd8BFdERjHoAwE/Cl+sB", "contract: a Windows DPAPI blob")
    T_Check(SK_Unlock(blob, &k, &e) && k == K1, "contract: unlocks to the same key")
    u := SK_Lock(UNI)
    T_Check(SK_Unlock(u, &k, &e) && k == UNI, "contract: a key that is not plain ASCII round-trips")
    T_Eq(T_RawUnlockSize(u), StrPut(UNI, "UTF-8") - 1, "contract: exactly the key's UTF-8 bytes, no terminating zero")
    T_Eq(SK_Lock(""), "", "contract: nothing locked for an empty key")
    T_Check(!SK_Unlock("not base64 at all!", &k, &e) && e = 0, "contract: not base64 is refused, with no Windows code")
    T_Check(!SK_Unlock(T_LockWithEntropy(K1), &k, &e) && e != 0 && k = "", "contract: a value locked with an entropy is refused, with Windows' code")
    T_Info(Format("Windows refuses another account's value with 0x{:08X}", e))
    T_Check(!SK_Unlock(T_Flip(blob), &k, &e) && e != 0, "contract: a flipped byte is refused")
}

T_RoundTrip() {
    T_Reset()
    T_Check(SK_KeySet("anthropic", K1), "round trip: the save succeeds")
    T_Check(T_PlainHas("claude", K1), "round trip: in the plain file under the plugins' id")
    T_Check(T_LockedUnlocks("claude", K1), "round trip: in the locked file, locked")
    raw := T_Bytes(SK_LockedFile())
    T_Check(NumGet(raw, 0, "UChar") = 0x7B, "round trip: the locked file has no byte-order mark")
    text := T_Text(SK_LockedFile())
    T_Check(!InStr(text, K1, true), "round trip: the key's text is not in the locked file")
    T_Check(InStr(text, "`r`n") && InStr(text, '"_comment": "Supervertaler API keys, locked by Windows'), "round trip: CRLF, and the comment saying what the file is")
    T_Eq(T_Count(T_Dir(SK_LockedFile()) "\*.tmp"), 0, "round trip: no temporary file left")

    before := T_Bytes(SK_LockedFile())
    T_Check(SK_KeySet("anthropic", K1), "round trip: saving the same key again succeeds")
    T_Check(T_SameBytes(before, T_Bytes(SK_LockedFile())), "round trip: and writes nothing")

    FileDelete(SK_File())
    T_Same(SK_Key("anthropic"), K1, "round trip: with the plain file gone, read from the locked file")
    T_Eq(SK_Find("anthropic")["status"], "present", "round trip: present")
    T_Eq(SK_Problem(SK_Find("anthropic"), "anthropic"), "", "round trip: nothing to say")

    T_Check(SK_KeySet("anthropic", K1), "round trip: saved again, which writes the plain file back")
    T_Check(SK_KeySet("anthropic", ""), "removal: succeeds")
    T_Check(!T_PlainRaw().Has("claude"), "removal: gone from the plain file")
    T_Check(!T_LockedRaw().Has("claude"), "removal: gone from the locked file")
    T_Eq(SK_Find("anthropic")["status"], "absent", "removal: absent")
}

; Step 1: the plain file first, then the locked one, then settings.ini.
T_ReadOrder() {
    T_Reset()
    T_WritePlain(Map("claude", K1))
    T_WriteLocked(Map("claude", SK_Lock(K2)))
    T_Same(SK_Key("anthropic"), K1, "read order: the plain file decides when it has the key")
    T_WritePlain(Map("openai", O1))
    T_Same(SK_Key("anthropic"), K2, "read order: else the locked file")
    FileDelete(SK_LockedFile())
    IniWrite(KEY_OLD, SettingsFile(), "Keys", "anthropic")
    T_Same(SK_Key("anthropic"), KEY_OLD, "read order: else settings.ini [Keys], as before")
    T_WriteLocked(Map("claude", T_LockWithEntropy(K2)))
    T_Eq(SK_Find("anthropic")["status"], "unreadable", "read order: a locked key that can't be read ends the search")
    T_Same(SK_Key("anthropic"), "", "read order: and settings.ini's older copy is not handed out")
}

; A key locked under another account, made for real: locked with an entropy,
; so the contract's call without one is refused.
T_Unreadable() {
    T_Reset()
    elsewhere := T_LockWithEntropy(KEY_ELSE)
    T_WriteLocked(Map("claude", elsewhere, "openai", SK_Lock(O1)))
    before := T_Bytes(SK_LockedFile())

    found := SK_Find("anthropic")
    T_Eq(found["status"], "unreadable", "unreadable: reported as such, not absent")
    T_Eq(found["why"], "refused", "unreadable: Windows refused the entry")
    T_Same(SK_KeyFor("anthropic", &problem), "", "unreadable: no key handed out")
    T_Eq(problem, T_M2("Anthropic"), "unreadable: M2 when an action needs it")
    T_Eq(SK_Note(found, "anthropic"), T_M1("Anthropic"), "unreadable: M1 under the key box")
    log := T_LogText()
    T_Check(InStr(log, "claude key cannot be unlocked") && InStr(log, "Windows error 0x"), "unreadable: Windows' code is logged")
    T_Check(T_SameBytes(before, T_Bytes(SK_LockedFile())), "unreadable: reading changes nothing")

    T_Check(SK_KeySet("openai", O2), "unreadable: another provider's key saved")
    T_Check(T_LockedRaw()["claude"] == elsewhere, "unreadable: the entry is kept through another save")
    T_Check(SK_KeySet("anthropic", ""), "unreadable: an empty save - the box left empty - succeeds")
    T_Check(T_LockedRaw()["claude"] == elsewhere, "unreadable: and keeps the entry")
    T_Eq(SK_Find("anthropic")["status"], "unreadable", "unreadable: still reported")
    T_Check(SK_KeySet("anthropic", K2), "unreadable: a new key saved")
    T_Check(T_LockedUnlocks("claude", K2), "unreadable: the new key replaced it")
    FileDelete(SK_File())
    T_Same(SK_Key("anthropic"), K2, "unreadable: and reads from the locked file")
}

; A flipped byte, or a value that is not base64: unreadable, never absent. A
; blank value is no key.
T_Tampered() {
    T_Reset()
    T_WriteLocked(Map("claude", T_Flip(SK_Lock(K1)), "openai", "not base64 at all!", "gemini", ""))
    T_Eq(SK_Find("anthropic")["status"], "unreadable", "tampered: a flipped byte is unreadable")
    T_Eq(SK_Find("openai")["status"], "unreadable", "tampered: not base64 is unreadable")
    T_Check(InStr(T_LogText(), "openai key cannot be unlocked by this Windows account (not base64)"), "tampered: said so in the log")
    T_Eq(SK_Find("gemini")["status"], "absent", "tampered: a blank value is no key")
}

; A truncated locked file: every lookup that reaches it is unreadable; the
; next write copies it aside byte for byte, then replaces it.
T_Damaged() {
    T_Reset()
    SK_KeySet("anthropic", K1)
    full := T_Text(SK_LockedFile())
    T_WriteText(SK_LockedFile(), SubStr(full, 1, StrLen(full) - 20))
    FileDelete(SK_File())
    path := SK_LockedFile()

    found := SK_Find("anthropic")
    T_Eq(found["status"] "/" found["why"], "unreadable/damaged", "damaged: every key in it unreadable")
    T_Eq(SK_Problem(found, "anthropic"), "Can't use your Anthropic key " Chr(0x2013) " the file holding your locked API keys is damaged: "
        . path ". Paste the key in again in Settings " Chr(0x2192) " AI providers.", "damaged: M2 names the file")
    T_Eq(SK_Note(found, "anthropic"), "Your Anthropic key can't be read " Chr(0x2013) " the file holding your locked API keys is damaged: "
        . path ". Paste the key in again; the damaged file will be set aside, not deleted.", "damaged: M1 names the file")

    T_WritePlain(Map("claude", K1, "openai", O1))
    damaged := T_Bytes(path)
    r := SK_SyncLocked()
    asides := T_Asides()
    T_Eq(asides.Length, 1, "damaged: the sync sets it aside")
    if (asides.Length = 1) {
        T_Check(RegExMatch(asides[1], "\\api-keys\.locked\.damaged-\d{8}-\d{6}\.json$"), "damaged: as api-keys.locked.damaged-<stamp>.json")
        T_Check(T_SameBytes(damaged, T_Bytes(asides[1])), "damaged: byte for byte")
        T_Eq(r["notice"], T_M6(asides[1]), "damaged: the notice is M6, naming the copy")
    }
    T_Eq(SK_SyncNotice, r["notice"], "damaged: kept for the providers window")
    T_Eq(r["locked"], 2, "damaged: both plain keys locked afresh")
    T_Check(T_LockedUnlocks("claude", K1) && T_LockedUnlocks("openai", O1), "damaged: the new file holds them")

    T_WriteText(path, "{ garbage")
    T_Check(SK_KeySet("gemini", GEM), "damaged: a save over a damaged file succeeds")
    T_Eq(T_Asides().Length, 2, "damaged: and sets it aside too, beside the first (never deleted)")
    T_Check(T_LockedUnlocks("gemini", GEM), "damaged: the save is in the new file")
}

; The locked file must be read strictly: truncated or garbled means damaged.
T_ParseStrict() {
    good := Map(
        "", 0, "  `r`n ", 0, "{}", 0, "{ }", 0,
        '{"_comment":"x","claude":"AQ"}', 1,
        '{"a":{"b":[1,2,{"c":null}]},"claude":"AQ","n":-1.5e3,"t":true,"f":false,"z":null,"e":[]}', 1,
        '{"tr\u0061dos:x":"A\/Q","deepl":"B"}', 2,
        "{`r`n  `"claude`": `"AQ`"`r`n}`r`n", 1)
    for text, n in good {
        ok := SK_ParseLocked(text, &entries)
        T_Check(ok && entries.Count = n, "strict: valid " T_Show(text) " -> " n " entr" (n = 1 ? "y" : "ies"))
    }
    SK_ParseLocked('{"tr\u0061dos:x":"A\/Q"}', &entries)
    T_Check(entries.Has("trados:x") && entries["trados:x"] == "A/Q", "strict: escapes undone in ids and values")
    SK_ParseLocked('{"\ud83d\ude00 Acme":"x"}', &entries)
    T_Check(entries.Has(Chr(0x1F600) " Acme"), "strict: a \u pair beyond U+FFFF, as Python writes it")
    SK_ParseLocked('{"Claude":"AQ"}', &entries)
    T_Check(entries.Has("claude"), "strict: ids are case-insensitive")

    bad := ['{"claude": "AQ",', '{"claude": "AQ"', '{"claude": "AQ"} x', '["claude"]', '"claude"',
            '{"claude": AQ}', '{"claude" "AQ"}', '{claude: "AQ"}', "{'claude': 'AQ'}", '{"claude": "A',
            '{"claude": "AQ",}', '{"a":"b"}}', '{"a":[1,2}', '{"a":"b`nc"}', '{"a":"\q"}',
            '{"claude": "AQ"}' Chr(0) "}", "garbage", "{"]
    for text in bad
        T_Check(!SK_ParseLocked(text, &entries), "strict: damaged " T_Show(text))

    ; What a power cut can leave: a file of zero bytes' worth of zeros.
    zeros := Buffer(64, 0)
    T_Check(!SK_ParseLocked(SK_Decode(zeros), &entries), "strict: damaged - a file full of zero bytes")

    ; A byte-order mark is allowed, as core allows it.
    bom := Buffer(3 + 2)
    NumPut("UChar", 0xEF, "UChar", 0xBB, "UChar", 0xBF, "UChar", 0x7B, "UChar", 0x7D, bom)
    T_Check(SK_ParseLocked(SK_Decode(bom), &entries), "strict: a UTF-8 byte-order mark is fine")
}

T_Missing() {
    T_Reset()
    T_Eq(SK_Find("anthropic")["status"], "absent", "missing: no file at all is absent")
    r := SK_SyncLocked()
    T_Check(r["locked"] = 0 && !r["failed"], "missing: a sync with no plain file does nothing, and is no failure")
    T_Check(!FileExist(SK_LockedFile()), "missing: and creates no locked file")
    T_Check(SK_KeySet("anthropic", ""), "missing: removing a key from no files succeeds")
    T_Check(!FileExist(SK_LockedFile()) && !FileExist(SK_File()), "missing: and leaves no empty file behind")

    cfg := EnvGet("APPDATA") "\Supervertaler\config.json"
    FileMove(cfg, cfg ".off")
    try {
        T_Eq(SK_File(), "", "missing: no data root")
        T_Check(!SK_KeySet("anthropic", K1), "missing: a save without a data root says false, as before")
        T_Check(!FileExist(SK_LockedFile()), "missing: and locks nothing")
        T_Check(SK_SyncLocked()["locked"] = 0, "missing: the sync has nothing to do")
        T_WriteLocked(Map("claude", SK_Lock(K2)))
        T_Same(SK_Key("anthropic"), K2, "missing: the locked file is read without a data root")
    } finally {
        FileMove(cfg ".off", cfg)
    }
}

; The start-up sync adds and replaces, never removes.
T_Sync() {
    T_Reset()
    T_WritePlain(Map("_comment", "x", "claude", K1, "openai", O1, "deepl", DL, "google", GT, "n", 5, "blank", "  "))
    r := SK_SyncLocked()
    T_Eq(r["locked"] "/" r["failed"], "4/0", "sync: the four keys locked, the comment, a number and a blank left out")
    T_Check(T_LockedUnlocks("claude", K1) && T_LockedUnlocks("openai", O1) && T_LockedUnlocks("deepl", DL) && T_LockedUnlocks("google", GT), "sync: each one unlocks to its key")
    T_Check(InStr(T_LogText(), "API keys: 4 locked to this computer."), "sync: logged")

    before := T_Bytes(SK_LockedFile())
    r := SK_SyncLocked()
    T_Eq(r["locked"], 0, "sync: nothing to change")
    T_Check(T_SameBytes(before, T_Bytes(SK_LockedFile())), "sync: and nothing written")

    T_WritePlain(Map("claude", K2))
    T_Eq(SK_SyncLocked()["locked"], 1, "sync: a different plain key replaces the locked one")
    T_Check(T_LockedUnlocks("claude", K2) && T_LockedUnlocks("openai", O1), "sync: and the others stay")

    T_WriteLocked(Map("claude", T_LockWithEntropy(K1), "openai", SK_Lock(O1)))
    T_Eq(SK_SyncLocked()["locked"], 1, "sync: an entry that can't be read is replaced by the plain key")
    T_Check(T_LockedUnlocks("claude", K2), "sync: which now unlocks")

    before := T_Bytes(SK_LockedFile())
    T_WriteText(SK_File(), "{}")
    T_Check(SK_SyncLocked()["locked"] = 0 && T_SameBytes(before, T_Bytes(SK_LockedFile())), "sync: an empty plain file removes nothing")
    T_WriteText(SK_File(), '{"claude": "sk-ant-')
    r := SK_SyncLocked()
    T_Check(r["failed"] && T_SameBytes(before, T_Bytes(SK_LockedFile())), "sync: a damaged plain file removes nothing, and is reported")
    T_Check(T_LockedUnlocks("claude", K2), "sync: the locked key is still there")
}

; Entries Sidekick does not know survive its writes - in both files.
T_Unknown() {
    T_Reset()
    acme := "trados:custom_openai:Acme server"
    T_WriteLocked(Map(acme, SK_Lock(KEY_ACME), "workbench:custom_openai:PROJ-001", SK_Lock(KEY_WB), "deepl", SK_Lock(DL)))
    T_WritePlain(Map("grok", "xai-test-PROJ-001", "custom_openai", "sk-test-co-PROJ-001"))
    before := T_LockedRaw()
    T_Check(SK_KeySet("openai", O1), "unknown: a save")
    after := T_LockedRaw()
    kept := true
    for id, blob in before
        kept := kept && after.Has(id) && after[id] == blob
    T_Check(kept, "unknown: every entry Sidekick does not know is kept, unchanged")
    T_Check(InStr(T_Text(SK_LockedFile()), '"' acme '"', true), "unknown: ids kept as spelt")
    plain := T_PlainRaw()
    T_Check(plain.Has("grok") && plain.Has("custom_openai") && plain.Has("openai"), "unknown: and in the plain file")
}

; Nothing goes to a provider in place of a key that can't be read.
T_NoBlankKey() {
    T_Reset()
    T_WriteLocked(Map("claude", T_LockWithEntropy(K1), "openai", T_LockWithEntropy(O1), "deepl", T_LockWithEntropy(DL)))
    IniWrite(KEY_LEGACY, A_ScriptDir "\ChatGptAPI.ini", "ChatGptAPI", "API_Key")
    IniWrite(KEY_OLD, SettingsFile(), "Keys", "anthropic")
    AI_ProvidersReload()

    IniWrite("anthropic", SettingsFile(), "AI", "Provider")
    cfg := AI_Config()
    T_Same(cfg["key"], "", "AI action: no key for Anthropic, not settings.ini's older one")
    T_Eq(cfg["keyproblem"], T_M2("Anthropic"), "AI action: M2 instead of a request")

    IniWrite("openai", SettingsFile(), "AI", "Provider")
    cfg := AI_Config()
    T_Same(cfg["key"], "", "AI action: no fall-back to ChatGptAPI.ini past an OpenAI key that can't be read")
    T_Eq(cfg["keyproblem"], T_M2("OpenAI"), "AI action: M2 for OpenAI")

    T_WriteLocked(Map("claude", T_LockWithEntropy(K1), "deepl", T_LockWithEntropy(DL)))
    cfg := AI_Config()
    T_Same(cfg["key"], KEY_LEGACY, "AI action: control - with no OpenAI key at all, ChatGptAPI.ini still works")
    T_Eq(cfg["keyproblem"], "", "AI action: control - nothing to say")

    active := Map()
    for e in QT_ActiveEngines()
        active[e["id"]] := e
    T_Check(active.Has("deepl"), "QuickTrans: an engine whose key can't be read stays in, to say so")
    T_Check(!active.Has("microsoft"), "QuickTrans: an engine with no key at all is left out, as before")
    try {
        QT_BuildRequest(active["deepl"], "Acme", "en", "nl")
        T_Check(false, "QuickTrans: no DeepL request is built")
    } catch Error as err {
        T_Eq(err.Message, T_M2("DeepL"), "QuickTrans: no DeepL request; its row says M2")
    }

    ollama := T_Engine("ollama")
    T_WriteText(SK_LockedFile(), "{ damaged")
    r := QT_BuildRequest(ollama, "Acme", "en", "nl")
    T_Check(!r["headers"].Has("Authorization"), "QuickTrans: Ollama needs no key, so a damaged key file does not stop it")
    T_WriteLocked(Map("ollama", T_LockWithEntropy("ollama-test-PROJ-001")))
    try {
        QT_BuildRequest(ollama, "Acme", "en", "nl")
        T_Check(false, "QuickTrans: no Ollama request without its stored key")
    } catch Error as err {
        T_Eq(err.Message, T_M2("Ollama"), "QuickTrans: but its own key that can't be read does")
    }
    try FileDelete(A_ScriptDir "\ChatGptAPI.ini")
}

; The providers window, built but never shown: M1 under the box, nothing over
; it, Models refuses, Save keeps the key, a pasted key replaces it.
T_Window() {
    global SK_SyncNotice
    T_Reset()
    elsewhere := T_LockWithEntropy(K1)
    T_WritePlain(Map("openai", O1))
    T_WriteLocked(Map("claude", elsewhere))
    IniWrite(KEY_OLD, SettingsFile(), "Keys", "anthropic")
    SK_SyncNotice := T_M6(SK_LockedFile() ".damaged-20261101-120000.json")
    AI_ProvidersReload()

    PR_Build()
    row := PR_Rows["anthropic"]
    T_Eq(row["note"], T_M1("Anthropic"), "window: M1 for the key that can't be read")
    T_Check(row.Has("noteCtl") && row["noteCtl"].Text == T_M1("Anthropic"), "window: shown, in full")
    row["masked"].GetPos(, &ky, , &kh)
    row["noteCtl"].GetPos(, &ny, , &nh)
    PR_Rows["openai"]["on"].GetPos(, &oy)
    T_Check(ny >= ky + kh, "window: under the key box")
    T_Check(nh > 20 && oy >= ny + nh, "window: wrapped, with the next row below it, not over it")
    T_Eq(PR_KeyValue(row), "", "window: the box is empty - settings.ini's older key is not shown")
    T_Eq(GetKey(PR_Rows["openai"], "note", ""), "", "window: no note for a key that reads")
    T_Eq(PR_CannotAsk("anthropic"), T_M1("Anthropic"), "window: Models asks nothing, and says why")
    shown := false
    for hwnd, ctl in PR_Gui
        shown := shown || (ctl.Type = "Text" && ctl.Text == SK_SyncNotice)
    T_Check(shown, "window: the start-up notice (M6) is shown")

    PR_Save()
    T_Check(InStr(PR_Status.Value, "Saved."), "window: Save")
    T_Check(T_LockedRaw()["claude"] == elsewhere, "window: Save with the box empty keeps the locked entry")
    T_Eq(IniRead(SettingsFile(), "Keys", "anthropic", ""), KEY_OLD, "window: and leaves settings.ini's copy alone")
    T_Check(!T_PlainRaw().Has("claude"), "window: and writes no empty key to the plain file")
    T_Check(T_LockedUnlocks("openai", O1), "window: the keys that read are saved as before")

    row["masked"].Value := K2
    PR_Save()
    T_Check(T_PlainHas("claude", K2) && T_LockedUnlocks("claude", K2), "window: a pasted key replaces it, in both files")
    T_Check(!row["noteCtl"].Visible && row["note"] = "", "window: and the note goes")
    PR_Close()
    SK_SyncNotice := ""
}

; Temporary files left by a killed write are swept once old; a fresh one is
; somebody's write in progress and stays.
T_Sweep() {
    T_Reset()
    SK_KeySet("anthropic", K1)
    old := SK_LockedFile() ".0123456789abcdef0123456789abcdef.tmp"
    fresh := SK_LockedFile() ".fedcba9876543210fedcba9876543210.tmp"
    FileAppend("x", old)
    FileSetTime(DateAdd(A_Now, -10, "Minutes"), old, "M")
    FileAppend("y", fresh)
    SK_KeySet("openai", O1)
    T_Check(!FileExist(old), "sweep: an abandoned temporary file is removed")
    T_Check(FileExist(fresh), "sweep: a fresh one is left alone")
    T_Check(T_LockedUnlocks("claude", K1), "sweep: the real file is intact")
    FileDelete(fresh)
}

; What it costs, for the hand-off: one lookup, one sync, at today's size and
; at 100 times it.
T_Timing() {
    for n in [15, 1500] {
        T_Reset()
        entries := Map(), plain := Map()
        Loop n {
            id := (A_Index = 1) ? "claude" : "provider" A_Index
            key := "sk-test-" A_Index "-" StrReplace(Format("{:100}", ""), " ", "k")
            entries[id] := SK_Lock(key)
            plain[id] := key
        }
        T_WriteLocked(entries)
        t := T_Clock(), runs := (n > 100) ? 5 : 50
        Loop runs
            SK_Key("anthropic")
        perLookup := (T_Clock() - t) / runs
        T_WritePlain(plain)
        SK_SyncLocked()                     ; settles anything left over
        t := T_Clock()
        r := SK_SyncLocked()
        perSync := T_Clock() - t
        T_Check(r["locked"] = 0 && !r["failed"], "timing: a sync of " n " keys with nothing to change writes nothing")
        T_Info(Format("{} entries: a lookup from the locked file {:.1f} ms; a start-up sync with nothing to change {:.0f} ms", n, perLookup, perSync))
    }
    t := T_Clock(), blob := SK_Lock(K1)
    Loop 200
        SK_Unlock(blob, &k, &e)
    T_Info(Format("one unlock {:.2f} ms", (T_Clock() - t) / 200))
    T_Reset()
}

; ---------------------------------------------------------------------------
; Phases run between Plugin Core steps (the runner does those).
; ---------------------------------------------------------------------------

; Sidekick locks; core then reads them with the plain file gone.
T_CrossLock() {
    T_Reset()
    T_Check(SK_KeySet("anthropic", K1) && SK_KeySet("openai", UNI) && SK_KeySet("deepl", DL) && SK_KeySet("google", GT),
        "cross: Sidekick saves four keys, one not plain ASCII")
    FileDelete(SK_File())
}

; Core has locked gemini and a Trados profile key; Sidekick reads them, and its
; own save keeps core's entries.
T_CrossRead() {
    acme := "trados:custom_openai:Acme & <PROJ-001>'s server"
    T_Same(SK_Key("gemini"), GEM, "cross: Sidekick reads a key core locked")
    T_Same(SK_Key("anthropic"), K1, "cross: and its own, after core rewrote the file")
    T_Same(SK_Key("openai"), UNI, "cross: the key that is not plain ASCII too")
    T_Check(T_LockedUnlocks(acme, KEY_ACME), "cross: and core's Trados profile key, under its private id")
    before := T_LockedRaw()[acme]
    T_Check(SK_KeySet("mistral", MI), "cross: Sidekick saves another")
    T_Check(T_LockedRaw()[acme] == before, "cross: core's private entry survives Sidekick's rewrite")
    FileDelete(SK_File())
}

; Re-renders the locked file core wrote, for the runner to compare byte for
; byte with core's own.
T_Render() {
    if !SK_ParseLocked(T_Text(SK_LockedFile()), &entries) {
        T_Check(false, "render: core's file parses")
        return
    }
    out := SK_RenderLocked(entries)
    f := FileOpen(T_Root "\sidekick-render.json", "w", "UTF-8-RAW")
    f.Write(out)
    f.Close()
    T_Check(true, "render: " entries.Count " entries written for comparison")
}

; Sidekick's sentences for a key that can't be read and for a damaged file,
; for the runner to compare with core's.
T_Messages() {
    T_Reset()
    ids := ["anthropic", "openai", "gemini", "mistral", "deepseek", "openrouter"]
    m := Map()
    for id in ids
        m[SK_Id(id)] := T_LockWithEntropy("sk-test-" id "-PROJ-001")
    T_WriteLocked(m)
    out := ""
    for id in ids {
        found := SK_Find(id)
        out .= "refused`t" SK_Id(id) "`tM1`t" SK_Note(found, id) "`n"
        out .= "refused`t" SK_Id(id) "`tM2`t" SK_Problem(found, id) "`n"
    }
    T_WriteText(SK_LockedFile(), "{ damaged")
    for id in ids {
        found := SK_Find(id)
        out .= "damaged`t" SK_Id(id) "`tM1`t" SK_Note(found, id) "`n"
        out .= "damaged`t" SK_Id(id) "`tM2`t" SK_Problem(found, id) "`n"
    }
    FileAppend(out, T_Root "\sidekick-messages.txt", "UTF-8-RAW")
    T_Check(StrSplit(Trim(out, "`n"), "`n").Length = 24, "messages: 24 sentences written for comparison")
    T_Reset()
}

T_HeldSetup() {
    T_Reset()
    T_Check(SK_KeySet("anthropic", K1), "held: set-up - a key locked, the plain file then removed")
    FileDelete(SK_File())
}

; The runner holds the locked file the whole time.
T_HeldLocked() {
    path := SK_LockedFile()
    t := A_TickCount
    found := SK_Find("anthropic")
    waited := A_TickCount - t
    T_Eq(found["status"] "/" found["why"], "unreadable/unavailable", "held: a held locked file is unreadable, not absent")
    T_Check(waited >= 900, "held: after waiting out a writer for about a second (" waited " ms)")
    T_Eq(SK_Problem(found, "anthropic"), "Can't use your Anthropic key " Chr(0x2013) " the file holding your locked API keys could not be opened: "
        . path ". Try again in a moment.", "held: M2 says so")
    T_Eq(SK_Note(found, "anthropic"), "Your Anthropic key can't be read just now " Chr(0x2013) " the file holding your locked API keys could not be opened: "
        . path ".", "held: M1 says so")
    T_Check(SK_KeySet("openai", O1), "held: a save still counts - the plain file decides")
    T_Check(InStr(T_LogText(), "openai key is saved in api-keys.json but not yet locked"), "held: and the gap is logged")
    T_Same(SK_Key("openai"), O1, "held: the saved key reads")
    T_Check(!SK_KeySet("anthropic", ""), "held: a removal does not count - the locked key would still be read")
}

T_AfterHeld() {
    r := SK_SyncLocked()
    T_Eq(r["locked"], 1, "held: the next start's sync catches up")
    T_Check(T_LockedUnlocks("openai", O1), "held: the key saved meanwhile is locked now")
    T_Same(SK_Key("anthropic"), K1, "held: the key whose removal failed is still there, as reported")
}

; The runner holds the plain file the whole time.
T_HeldPlain() {
    before := T_Bytes(SK_LockedFile())
    T_Check(!SK_KeySet("gemini", GEM), "held plain: the save does not take")
    T_Check(T_SameBytes(before, T_Bytes(SK_LockedFile())), "held plain: and the locked file is not touched")
    r := SK_SyncLocked()
    T_Check(r["failed"] && T_SameBytes(before, T_Bytes(SK_LockedFile())), "held plain: the sync reports it and changes nothing")
}

; 40 saves while Plugin Core saves 40 others, started together.
T_Race() {
    FileAppend("ready", T_Root "\race.ready")
    t := A_TickCount
    while !FileExist(T_Root "\race.go") && A_TickCount - t < 10000
        Sleep(5)
    ok := 0
    Loop 40
        ok += SK_KeySet("race-sk-" A_Index, "sk-race-" A_Index "-PROJ-001")
    T_Eq(ok, 40, "race: every one of Sidekick's 40 saves reports success")
}

; Saves for ever; the runner kills it part-way, again and again.
T_KillLoop() {
    FileAppend("ready", T_Root "\kill.ready")
    Loop
        SK_KeySet("anthropic", "sk-ant-test-Kill-" Mod(A_Index, 1000) "-PROJ-001")
}

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

T_M1(name) => "Your " name " key can't be read on this computer " Chr(0x2013) " it was saved under another Windows sign-in, "
            . "or your Windows password was reset. Paste the key in again; nothing else is affected."
T_M2(name) => "Can't use your " name " key " Chr(0x2013) " it can't be read on this computer (saved under another Windows sign-in, "
            . "or your Windows password was reset). Paste it in again in Settings " Chr(0x2192) " AI providers."
T_M6(path) => "The file holding your locked API keys was damaged and has been set aside as " path ". Please paste your keys in again."

T_Engine(id) {
    for e in QT_Engines()
        if (e["id"] = id)
            return e
}

; Back to nothing: no key files, a settings.ini with the debug log on. Locked
; files and set-aside copies are moved to scan\, where the runner checks that
; no key text is in any of them.
T_Reset() {
    global SK_SyncNotice, SK_Debug
    static n := 0
    SK_SyncNotice := ""
    Loop Files, T_Dir(SK_File()) "\api-keys*"
        FileDelete(A_LoopFileFullPath)
    DirCreate(T_Root "\scan")
    Loop Files, T_Dir(SK_LockedFile()) "\api-keys*"
        FileMove(A_LoopFileFullPath, T_Root "\scan\" T_Phase "-" (A_PtrSize * 8) "-" (++n) "-" A_LoopFileName)
    try FileDelete(SettingsFile())
    IniWrite("1", SettingsFile(), "Sidekick", "Debug")
    SK_Debug := 1
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

; For sentences, counts and states - never for keys.
T_Eq(actual, expected, name) {
    T_Check(actual == expected, name, "got: " actual " | expected: " expected)
}

; For keys: says whether they match, never what they are.
T_Same(actual, expected, name) {
    T_Check(actual == expected, name, actual = "" ? "got none" : "got a different key")
}

T_Info(s) => T_Line("INFO  " s)

; Short, printable form of a test string (no keys in these).
T_Show(s) {
    s := StrReplace(StrReplace(StrReplace(s, "`r", "\r"), "`n", "\n"), Chr(0), "\0")
    return "[" (StrLen(s) > 40 ? SubStr(s, 1, 40) "..." : s) "]"
}

T_Dir(path) {
    SplitPath(path, , &dir)
    return dir
}

T_Count(pattern) {
    n := 0
    Loop Files, pattern
        n++
    return n
}

T_Asides() {
    out := []
    Loop Files, T_Dir(SK_LockedFile()) "\api-keys.locked.damaged-*.json"
        out.Push(A_LoopFileFullPath)
    return out
}

T_Bytes(path) => FileExist(path) ? FileRead(path, "RAW") : Buffer(0)
T_Text(path) => SK_Decode(T_Bytes(path))

T_SameBytes(a, b) {
    return a.Size = b.Size && (a.Size = 0 || DllCall("msvcrt\memcmp", "Ptr", a, "Ptr", b, "UPtr", a.Size, "CDecl Int") = 0)
}

T_WriteText(path, text) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

T_WritePlain(m) => T_WriteText(SK_File(), Jxon_Dump(m, 2))
T_WriteLocked(m) => T_WriteText(SK_LockedFile(), SK_RenderLocked(m))

T_PlainRaw() {
    text := T_Text(SK_File())
    try return Jxon_Load(&text)
    catch
        return Map()
}

T_PlainHas(id, key) {
    m := T_PlainRaw()
    return m.Has(id) && m[id] == key
}

T_LockedRaw() => SK_ParseLocked(T_Text(SK_LockedFile()), &e) ? e : SK_NewMap()

T_LockedUnlocks(id, key) {
    m := T_LockedRaw()
    return m.Has(id) && SK_Unlock(m[id], &k, &e) && k == key
}

T_LogText() => T_Text(DataFile("sidekick.log"))

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

T_Binary(b64, &size) {
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
    bin := Buffer(size)
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1, "Ptr", bin, "UInt*", &size, "Ptr", 0, "Ptr", 0)
    return bin
}

; The same blob with one byte in the middle flipped.
T_Flip(b64) {
    bin := T_Binary(b64, &size)
    NumPut("UChar", NumGet(bin, size // 2, "UChar") ^ 0xFF, bin, size // 2)
    return SK_Base64(bin.Ptr, size)
}

; How many bytes the raw Windows call unlocks a value to.
T_RawUnlockSize(b64) {
    bin := T_Binary(b64, &size)
    out := SK_Blob()
    if !DllCall("crypt32\CryptUnprotectData", "Ptr", SK_Blob(bin.Ptr, size), "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 0x1, "Ptr", out, "Int")
        return -1
    n := NumGet(out, 0, "UInt")
    DllCall("LocalFree", "Ptr", NumGet(out, A_PtrSize, "Ptr"), "Ptr")
    return n
}
