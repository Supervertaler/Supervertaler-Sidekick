; lib/sharedkeys.ahk — the API keys shared with Supervertaler for Trados and
; Supervertaler for memoQ (Trados #108), and, from step 1 of "API keys locked
; to the computer" (Plugin Core, docs/design/api-key-protection.md), their
; locked copies.
;
; Two files during step 1:
;
;   * The plain file, <data root>\settings\api-keys.json: one key per
;     provider, plain text, in the data folder - which is synced, backed up
;     and copied whole, and every key in it goes along. Still read and
;     written exactly as before, so a product not yet updated keeps working.
;     Step 2 imports it into the locked file and removes it.
;   * The locked file, %APPDATA%\Supervertaler\api-keys.locked.json: the
;     same ids, each value locked by Windows to this Windows account (DPAPI),
;     in the user's profile rather than the data folder. A copy of it opens
;     for no other account and on no other computer.
;
; The data root is where the other products keep everything, found the way
; they find it: %AppData%\Supervertaler\config.json -> "user_data_path".
;
; Step 1, the same in every product:
;
;   * A read takes the plain file's key when it has one, else the locked
;     file's, else settings.ini [Keys] (Sidekick's own copy, as before).
;   * A key the locked file holds but this account cannot unlock is reported
;     by name - M1 under its box in the providers window, M2 when an action
;     needs it - and ends the search. It is never shown as an empty box that
;     a Save would clear, never sent to a provider blank, and never replaced
;     by an older copy from settings.ini that the provider would turn down.
;   * A save writes the plain file, then the locked one, each under the
;     exclusive open the plugins take, so two products saving at once lose
;     nothing. Always the plain file first: one order everywhere means no two
;     products wait on each other, and a crash between the two writes leaves
;     the plain file the newer one, which reads take and the next start locks.
;   * At start-up SK_SyncLocked copies the plain keys into the locked file -
;     adding and replacing, never removing.
;
; Nothing is cached: a lookup reads the files and unlocks one key, about a
; millisecond, and a cache would go stale when another product changes a key.
;
; Provider ids differ in one place: Sidekick says "anthropic", the plugins say
; "claude". Everything else - openai, gemini, mistral, deepseek, openrouter -
; is the same word. Machine-translation keys (google, microsoft, deepl,
; modernmt) are Sidekick's own and are stored under their own names.

; Where a missing or unreadable key is entered, as the messages name it.
global SK_Place := "Settings → AI providers"

; Set by SK_SyncLocked when it had to set a damaged locked file aside (M6);
; shown in the providers window for the rest of the session.
global SK_SyncNotice := ""

; Path of the shared file, or "" when there is no data root to find.
SK_File() {
    cfg := EnvGet("APPDATA") "\Supervertaler\config.json"
    if !FileExist(cfg)
        return ""
    try {
        raw := FileRead(cfg, "UTF-8")
        data := Jxon_Load(&raw)
        root := (data is Map && data.Has("user_data_path")) ? Trim(data["user_data_path"]) : ""
    } catch {
        return ""
    }
    if (root = "")
        return ""
    return RTrim(root, "\") "\settings\api-keys.json"
}

; Path of the locked file, beside config.json in the roaming part of the
; profile - where Windows keeps the key that unlocks it, so a roaming profile
; carries both. "" when there is no %APPDATA%.
SK_LockedFile() {
    appData := EnvGet("APPDATA")
    return (appData = "") ? "" : RTrim(appData, "\") "\Supervertaler\api-keys.locked.json"
}

; Sidekick's id for a provider -> the id the shared file uses.
SK_Id(id) {
    static alias := Map("anthropic", "claude")
    return alias.Has(id) ? alias[id] : id
}

; The name a user knows a provider by, as the plugins name it in the same
; sentences.
SK_Name(id) {
    static names := ""
    if !IsObject(names) {
        names := Map()
        names.CaseSense := false
        names.Set("claude", "Anthropic", "anthropic", "Anthropic",
            "openai", "OpenAI", "gemini", "Gemini", "grok", "xAI",
            "mistral", "Mistral", "deepseek", "DeepSeek",
            "openrouter", "OpenRouter", "custom", "Custom OpenAI",
            "custom_openai", "Custom OpenAI", "ollama", "Ollama",
            "deepl", "DeepL", "google", "Google Translate",
            "microsoft", "Microsoft Translator", "modernmt", "ModernMT")
    }
    return names.Has(id) ? names[id] : id
}

; ---------------------------------------------------------------------------
; Reading
; ---------------------------------------------------------------------------

; The whole plain file as a Map, empty when absent or unreadable.
SK_Load() {
    file := SK_File()
    if (file = "")
        return Map()
    f := SK_Open(file, "r", &why)
    if !f
        return Map()
    try {
        raw := SK_Decode(SK_ReadAll(f))
        data := (StrLen(Trim(raw, " `t`r`n")) = 0) ? Map() : Jxon_Load(&raw)
        return (data is Map) ? data : Map()
    } catch {
        return Map()
    } finally {
        f.Close()
    }
}

; What a lookup found, as a Map:
;   status  "present", "absent" or "unreadable"
;   key     when present
;   why     when unreadable: "refused" (Windows would not unlock the entry),
;           "damaged" (the locked file is not valid JSON) or "unavailable"
;           (it could not be opened, even after waiting out a writer)
;   file    when unreadable: the locked file's path, for the messages
; Never throws: if something unforeseen does, "unreadable" is the honest
; answer, since "none set" would send the user to paste a key that is there.
SK_Find(id) {
    k := SK_Id(id)
    path := SK_LockedFile()
    try {
        data := SK_Load()
        if (data.Has(k) && Trim(data[k]) != "")
            return Map("status", "present", "key", Trim(data[k]))

        read := SK_ReadLocked(path)
        if (read["why"] != "")
            return Map("status", "unreadable", "why", read["why"], "file", path)

        blob := read["map"].Has(k) ? read["map"][k] : ""
        if (Trim(blob) != "") {
            if !SK_Unlock(blob, &key, &err) {
                SK_Log("api-keys.locked.json: the " k " key cannot be unlocked by this Windows account ("
                     . (err ? Format("Windows error 0x{:08X}", err) : "not base64") ").")
                return Map("status", "unreadable", "why", "refused", "file", path)
            }
            if (Trim(key) != "")
                return Map("status", "present", "key", Trim(key))
        }
    } catch Error as e {
        SK_Log("API key lookup failed: " e.Message)
        return Map("status", "unreadable", "why", "unavailable", "file", path)
    }

    ; Sidekick's own copy, as before the shared file existed.
    own := Trim(AI_Ini(SettingsFile(), "Keys", id, ""))
    return (own != "") ? Map("status", "present", "key", own) : Map("status", "absent")
}

; The key for a Sidekick provider id, or "" when there is none this computer
; can use.
SK_Key(id) {
    return SK_KeyFor(id, &problem)
}

; SK_Key, plus why not: when a key is stored but cannot be unlocked here,
; returns "" and sets problem to the sentence to show instead of calling the
; provider (M2). When there simply is none, problem is "" and the caller says
; so in its own words, as before.
SK_KeyFor(id, &problem) {
    found := SK_Find(id)
    problem := SK_Problem(found, id)
    return (found["status"] = "present") ? found["key"] : ""
}

; M2 - the sentence for an action that needs a key it cannot unlock; "" when
; the key is not unreadable. Worded as the plugins word it.
SK_Problem(found, id) {
    global SK_Place
    if (found["status"] != "unreadable")
        return ""
    name := SK_Name(id)
    switch found["why"] {
        case "damaged":
            return "Can't use your " name " key – the file holding your locked API keys is damaged: "
                 . found["file"] ". Paste the key in again in " SK_Place "."
        case "unavailable":
            return "Can't use your " name " key – the file holding your locked API keys could not be opened: "
                 . found["file"] ". Try again in a moment."
        default:
            return "Can't use your " name " key – it can't be read on this computer (saved under another Windows sign-in, "
                 . "or your Windows password was reset). Paste it in again in " SK_Place "."
    }
}

; M1 - the note under a key box whose key cannot be unlocked here; "" when it
; can, or none is stored. The box itself stays empty, and the stored key is
; kept until a new one is pasted.
SK_Note(found, id) {
    if (found["status"] != "unreadable")
        return ""
    name := SK_Name(id)
    switch found["why"] {
        case "damaged":
            return "Your " name " key can't be read – the file holding your locked API keys is damaged: "
                 . found["file"] ". Paste the key in again; the damaged file will be set aside, not deleted."
        case "unavailable":
            return "Your " name " key can't be read just now – the file holding your locked API keys could not be opened: "
                 . found["file"] "."
        default:
            return "Your " name " key can't be read on this computer – it was saved under another Windows sign-in, "
                 . "or your Windows password was reset. Paste the key in again; nothing else is affected."
    }
}

; M6.
SK_DamagedNotice(setAside) {
    return "The file holding your locked API keys was damaged and has been set aside as " setAside
         . ". Please paste your keys in again."
}

; The locked file's entries, still locked, as Map("map", entries, "why", ...).
; A file that is not valid JSON is "damaged"; one that cannot be opened after
; waiting out a writer is "unavailable". Either way every key in it counts as
; unreadable, not absent.
SK_ReadLocked(path) {
    none := Map("map", SK_NewMap(), "why", "")
    if (path = "" || !FileExist(path))
        return none
    f := SK_Open(path, "r", &why)
    if !f {
        if (why = "missing")
            return none
        SK_Log("api-keys.locked.json could not be opened.")
        return Map("map", SK_NewMap(), "why", "unavailable")
    }
    try raw := SK_ReadAll(f)
    finally f.Close()
    if SK_ParseLocked(SK_Decode(raw), &entries)
        return Map("map", entries, "why", "")
    SK_Log("api-keys.locked.json is damaged (not valid JSON): every key in it counts as unreadable until the next save sets it aside.")
    return Map("map", SK_NewMap(), "why", "damaged")
}

; ---------------------------------------------------------------------------
; Writing
; ---------------------------------------------------------------------------

; Saves one key (an empty key removes it): the plain file, then the locked
; file. Returns true when the save took; false when there is no data root
; (settings.ini still has it) or the plain file could not be written.
;
; A key already stored with this exact value needs no write, and that is a
; success: the providers window saves every box on Save, touched or not.
;
; In step 1 the plain file decides, so a key written there is saved even if
; the locked write fails; that is logged, and the next start's sync repeats
; it. A removal needs both files, because a key left in the locked file would
; still be read. An empty save never removes a key this account cannot
; unlock: the user never saw it - its box was empty - so it stays until a new
; key replaces it.
SK_KeySet(id, key) {
    file := SK_File()
    if (file = "")
        return false
    k := SK_Id(id)
    key := Trim(key)

    ; Critical: a second save in this script (a second click on Save, say)
    ; would otherwise interrupt this one while it waits on a file, then wait
    ; itself for the file this thread holds and cannot let go of until it
    ; resumes.
    wasCritical := A_IsCritical
    Critical
    try {
        if (SK_Update(file, false, (data) => SK_SetPlain(data, k, key), &setAside) < 0)
            return false
        if SK_SetLocked(k, key)
            return true
        if (key = "")
            return false
        SK_Log("The " k " key is saved in api-keys.json but not yet locked to this computer; the next start locks it.")
        return true
    } finally {
        Critical(wasCritical)
    }
}

; The plain half of SK_KeySet. Entries Sidekick does not know are kept.
SK_SetPlain(data, k, key) {
    if (key = "") {
        if !data.Has(k)
            return false
        data.Delete(k)
        return true
    }
    if (data.Has(k) && data[k] == key)
        return false
    data[k] := key
    if !data.Has("_comment")
        data["_comment"] := "API keys shared by Supervertaler for Trados, Supervertaler for memoQ and Supervertaler Sidekick. One key per provider; edit by hand or in any product's settings."
    return true
}

; The locked half of SK_KeySet: true when the locked file now says what was
; asked.
SK_SetLocked(k, key) {
    out := {refused: false}
    written := SK_Update(SK_LockedFile(), true, LockOne, &setAside)
    if out.refused
        SK_Log("Windows would not lock the " k " key.")
    return written >= 0 && !out.refused

    LockOne(entries) {
        out.refused := false
        readable := entries.Has(k) && SK_Unlock(entries[k], &current, &err)
        if (key = "") {
            if !readable
                return false            ; an unreadable entry is kept
            entries.Delete(k)
            return true
        }
        if (readable && current == key)
            return false
        blob := SK_Lock(key)
        if (blob = "") {
            out.refused := true
            return false
        }
        entries[k] := blob
        return true
    }
}

; The step-1 start-up sync: every key in the plain file is copied into the
; locked file where that lacks it or holds something else - a different key,
; or one this account cannot unlock. It adds and replaces, never removes, so
; a damaged, empty or half-written plain file cannot empty the locked one.
;
; The plain file is held - others may read it, not write it - until the
; locked file is written. Otherwise a key another product saves in between
; (plain file, then locked file) could be overwritten in the locked file by
; the older value read here. Plain file first, then locked file: the order
; every writer takes, so none waits on another.
;
; Returns Map("locked", n, "failed", bool, "notice", M6 or ""). A failure
; leaves the plain file deciding, and the next start tries again. Costs one
; unlock per plain key to compare, a fraction of a millisecond each, and a
; write only when something changed.
SK_SyncLocked() {
    global SK_SyncNotice
    result := Map("locked", 0, "failed", false, "notice", "")
    plainPath := SK_File()
    lockedPath := SK_LockedFile()
    if (plainPath = "" || lockedPath = "")
        return result

    wasCritical := A_IsCritical
    Critical
    try {
        f := SK_Open(plainPath, "r -wd", &why)
        if !f {
            if (why = "unavailable") {
                result["failed"] := true
                SK_Log("api-keys.json could not be opened: no key locked to this computer; the next start tries again.")
            }
            return result
        }
        try {
            text := SK_Decode(SK_ReadAll(f))
            try plain := (StrLen(Trim(text, " `t`r`n")) = 0) ? Map() : Jxon_Load(&text)
            catch {
                plain := ""
            }
            if !(plain is Map) {
                result["failed"] := true
                SK_Log("api-keys.json is not valid JSON: no key locked from it; the next start tries again.")
                return result
            }
            if (plain.Count = 0)
                return result

            counts := {locked: 0, refused: false}
            written := SK_Update(lockedPath, true, LockPlain, &setAside)
            result["locked"] := (written > 0) ? counts.locked : 0
            result["failed"] := counts.refused || written < 0
            if (setAside != "") {
                result["notice"] := SK_DamagedNotice(setAside)
                SK_SyncNotice := result["notice"]
            }
            if result["failed"]
                SK_Log("Not every key in api-keys.json could be locked to this computer; the next start tries again.")
            else if (result["locked"] > 0)
                SK_Log("API keys: " result["locked"] " locked to this computer.")
            return result
        } finally {
            f.Close()
        }
    } catch Error as e {
        ; Runs at start-up: nothing here may stop Sidekick starting.
        SK_Log("Keys not locked to this computer: " e.Message)
        result["failed"] := true
        return result
    } finally {
        Critical(wasCritical)
    }

    LockPlain(entries) {
        counts.locked := 0
        counts.refused := false
        for id, value in plain {
            if (SubStr(id, 1, 1) = "_" || !(value is String) || Trim(value) = "")
                continue
            want := Trim(value)
            if (entries.Has(id) && SK_Unlock(entries[id], &have, &err) && have == want)
                continue
            blob := SK_Lock(want)
            if (blob = "") {
                counts.refused := true
                continue
            }
            entries[id] := blob
            counts.locked++
        }
        return counts.locked > 0
    }
}

; One read-modify-write of a key file under an exclusive open, as the plugins
; do it (#108): several products share these files, and two of them saving at
; the same moment must not lose a write. The file is opened sharing only
; delete - still exclusive against every reader and writer - and a second
; writer waits up to a second for it. mutate(entries) returns false to leave
; the file untouched.
;
; Returns 1 written, 0 nothing needed writing, -1 not written.
;
; The new file is written beside the old one and renamed over it while the
; old one is still held (SK_WriteFile), never truncated and rewritten in
; place, so the file is the old keys or the new ones, never neither.
;
; The plain file is read as Sidekick always has (Jxon); one it cannot read is
; never overwritten, since that would drop every key in it. The locked file is
; read strictly (SK_ParseLocked). One that is not valid JSON is not
; overwritten either until its exact bytes are copied to
; api-keys.locked.damaged-<yyyyMMdd-HHmmss>.json beside it (setAside), and
; nothing is written unless that copy is. It holds only locked values, so
; keeping it costs nothing.
SK_Update(path, locked, mutate, &setAside) {
    setAside := ""
    if (path = "")
        return -1
    SplitPath(path, &name, &dir)
    try DirCreate(dir)
    catch {
        return -1
    }
    SK_SweepAbandoned(path)

    f := SK_Open(path, "rw -rw", &why)
    if !f {
        SK_Log(name " not written: it could not be opened.")
        return -1
    }
    try {
        raw := SK_ReadAll(f)
        text := SK_Decode(raw)
        damaged := false
        if !locked {
            try entries := (StrLen(Trim(text, " `t`r`n")) = 0) ? Map() : Jxon_Load(&text)
            catch {
                entries := ""
            }
            if !(entries is Map) {
                SK_Log(name " is not valid JSON; not written, so that no key in it is lost.")
                return -1
            }
        } else if !SK_ParseLocked(text, &entries) {
            damaged := true
            entries := SK_NewMap()
        }

        if !mutate(entries) {
            ; Nothing to write. An empty file - the one this open just made on
            ; a computer that had none - is removed so it cannot be mistaken
            ; for a failed write. Deleted before the handle closes: Windows
            ; marks it delete-pending and nobody can open it meanwhile.
            if (raw.Size = 0)
                DllCall("DeleteFileW", "Str", path)
            return 0
        }

        if damaged {
            setAside := SK_SetAside(path, raw)
            if (setAside = "")
                return -1
            SK_Log(SK_DamagedNotice(setAside))
        }

        text := locked ? SK_RenderLocked(entries) : Jxon_Dump(entries, 2)
        bytes := Buffer(StrPut(text, "UTF-8"))
        size := StrPut(text, bytes, "UTF-8") - 1

        ; Renamed over the file while this handle still holds it: a POSIX
        ; rename (NTFS) may replace a file whose handles all share delete,
        ; and this one does. Until the new file is in place no other product
        ; can open the old one, so the lock covers the whole
        ; read-modify-write.
        if (SK_WriteFile(path, bytes, size, true) = "written")
            return 1

        ; A volume without POSIX renames (FAT, some network shares) cannot
        ; replace a file that is open, even by this process. Let go of it and
        ; try once more; the file is never left half-written either way.
        f.Close()
        f := ""
        return (SK_WriteFile(path, bytes, size, true) = "written") ? 1 : -1
    } catch Error as e {
        SK_Log(name " not written: " e.Message)
        return -1
    } finally {
        if f
            f.Close()
    }
}

; Writes size bytes of buf to path in one step: first to "<path>.<guid>.tmp"
; in the same folder, flushed to disk, then renamed to path. With replace
; false it only creates path, and says "exists" if another writer got there
; first. Returns "written", "exists" or "failed"; on every path but
; "written" the temporary file is removed and path is untouched.
SK_WriteFile(path, buf, size, replace) {
    SplitPath(path, &name)
    temp := path "." SK_Guid() ".tmp"
    try {
        f := FileOpen(temp, "w -rwd", "UTF-8-RAW")
        f.RawWrite(buf, size)
        DllCall("FlushFileBuffers", "Ptr", f.Handle)
        f.Close()

        ; About a third of a second in all for a file someone has in use.
        for delay in [10, 20, 40, 80, 160, 0] {
            if replace {
                err := SK_RenameReplacing(temp, path)
            } else {
                ; Move refuses to overwrite, which is what makes a first
                ; write safe for two writers to race. 8 = MOVEFILE_WRITE_THROUGH.
                err := DllCall("MoveFileExW", "Str", temp, "Str", path, "UInt", 0x8, "Int") ? 0 : A_LastError
                if (err = 80 || err = 183)          ; file exists, already exists
                    return "exists"
            }
            if !err
                return "written"
            if (!SK_InUse(err) || !delay) {
                SK_Log(name " not written (Windows error " err "); the previous file is unchanged.")
                return "failed"
            }
            Sleep(delay)
        }
    } catch Error as e {
        SK_Log(name " not written: " e.Message)
        return "failed"
    } finally {
        ; On success the temporary file has become the real one and this
        ; finds nothing. On every other path it is the cleanup.
        try FileDelete(temp)
    }
}

; Renames source to target, replacing any file there, in one step. Returns 0
; or a Windows error.
;
; By handle with POSIX semantics (Windows 10 1709 and later, NTFS): the name
; is replaced while readers keep the old file, and it works over a file this
; script still holds with delete sharing. MoveFileEx, the fallback where the
; volume does not support that, has to wait for readers.
SK_RenameReplacing(source, target) {
    ; DELETE | SYNCHRONIZE; share read, write and delete; OPEN_EXISTING.
    h := DllCall("CreateFileW", "Str", source, "UInt", 0x00110000, "UInt", 7,
                 "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
    if (h = -1)
        return A_LastError

    ; FILE_RENAME_INFO: Flags, then RootDirectory (a handle, so
    ; pointer-aligned), then FileNameLength in bytes, then the name.
    nameOffset := 2 * A_PtrSize + 4
    nameBytes := StrLen(target) * 2
    info := Buffer(nameOffset + nameBytes + 2, 0)
    NumPut("UInt", 0x3, info, 0)            ; REPLACE_IF_EXISTS | POSIX_SEMANTICS
    NumPut("UInt", nameBytes, info, 2 * A_PtrSize)
    StrPut(target, info.Ptr + nameOffset, "UTF-16")
    ok := DllCall("SetFileInformationByHandle", "Ptr", h, "Int", 22,    ; FileRenameInfoEx
                  "Ptr", info, "UInt", info.Size, "Int")
    err := ok ? 0 : A_LastError
    DllCall("CloseHandle", "Ptr", h)
    if (!err || SK_InUse(err))
        return err

    ; MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH.
    return DllCall("MoveFileExW", "Str", source, "Str", target, "UInt", 0x9, "Int") ? 0 : A_LastError
}

; Access denied (also what a delete-pending file gives), sharing or lock
; violation: someone has the file for a moment.
SK_InUse(err) {
    return err = 5 || err = 32 || err = 33
}

; Opens path with FileOpen's flags, waiting out a writer that holds it - up
; to a second, 50 ms at a time. Returns the File, or "" with why set to
; "missing" or "unavailable".
SK_Open(path, flags, &why) {
    why := ""
    Loop 21 {
        try
            return FileOpen(path, flags, "UTF-8-RAW")
        catch OSError as e {
            if (e.Number = 2 || e.Number = 3) {
                why := "missing"
                return ""
            }
            if (!SK_InUse(e.Number) || A_Index = 21)
                break
            Sleep(50)
        }
    }
    why := "unavailable"
    return ""
}

; An open file's bytes, from the start, as a Buffer.
SK_ReadAll(f) {
    f.Pos := 0
    buf := Buffer(f.Length)
    if (buf.Size > 0)
        f.RawRead(buf, buf.Size)
    return buf
}

; Bytes to text: UTF-8 unless a byte-order mark says UTF-16, the mark itself
; left out. Every byte is converted, a stray zero included, so a garbled file
; cannot pass for a shorter valid one.
SK_Decode(buf) {
    n := buf.Size
    if (n >= 3 && NumGet(buf, 0, "UChar") = 0xEF && NumGet(buf, 1, "UChar") = 0xBB && NumGet(buf, 2, "UChar") = 0xBF)
        return (n = 3) ? "" : StrGet(buf.Ptr + 3, -(n - 3), "UTF-8")
    if (n >= 2 && NumGet(buf, 0, "UChar") = 0xFF && NumGet(buf, 1, "UChar") = 0xFE)
        return (n < 4) ? "" : StrGet(buf.Ptr + 2, -((n - 2) // 2), "UTF-16")
    return (n = 0) ? "" : StrGet(buf, -n, "UTF-8")
}

; Copies a damaged locked file's exact bytes beside it, under a name no
; writer uses. Returns that path, or "" when the copy could not be made.
SK_SetAside(path, raw) {
    SplitPath(path, , &dir, , &stem)
    base := dir "\" stem ".damaged-" FormatTime(, "yyyyMMdd-HHmmss")
    Loop 9 {
        aside := base (A_Index = 1 ? "" : "-" A_Index) ".json"
        result := SK_WriteFile(aside, raw, raw.Size, false)
        if (result = "written")
            return aside
        if (result = "failed")
            return ""
    }
    return ""
}

; Temporary files left by a process killed in the middle of a write - only
; ones old enough that no live write can still own them.
SK_SweepAbandoned(path) {
    try {
        Loop Files, path ".*.tmp" {
            if (DateDiff(A_Now, A_LoopFileTimeModified, "Minutes") >= 5)
                try FileDelete(A_LoopFileFullPath)
        }
    }
}

SK_Guid() {
    g := Buffer(16)
    DllCall("ole32\CoCreateGuid", "Ptr", g)
    out := ""
    Loop 16
        out .= Format("{:02x}", NumGet(g, A_Index - 1, "UChar"))
    return out
}

SK_NewMap() {
    m := Map()
    m.CaseSense := false
    return m
}

; ---------------------------------------------------------------------------
; The locked file's format - the same in every product, or a key locked by
; one will not open in another.
; ---------------------------------------------------------------------------

; Reads the locked file strictly - unlike the plain file, which serves hand
; edits. Other products write this file too, so a truncated or garbled one
; must be recognised as damaged, never read as fewer keys: true only for
; exactly one JSON object and nothing after it. Its string entries go into
; entries (ids case-insensitive, kept as spelt, so they survive a rewrite);
; ids starting with "_" and values that are not strings are left out. Empty
; or blank counts as no entries.
SK_ParseLocked(text, &entries) {
    static ws  := "A)[ \t\r\n]*"
    static str := 'A)"((?:[^"\\\x00-\x1F]++|\\(?:["\\/bfnrt]|u[0-9A-Fa-f]{4}))*+)"'
    static num := "A)-?(?:0|[1-9][0-9]*+)(?:\.[0-9]++)?(?:[eE][+-]?[0-9]++)?"
    static lit := "A)(?:true|false|null)"

    entries := SK_NewMap()
    if (StrLen(Trim(text, " `t`r`n")) = 0)
        return true
    try {
        stack := []                 ; "{" or "[" for each open container
        expect := "value"           ; value, value], key, key}, colon, next, end
        id := ""
        pos := 1
        Loop {
            RegExMatch(text, ws, &m, pos)
            pos += m.Len
            ch := SubStr(text, pos, 1)
            if (expect = "end")
                return pos > StrLen(text)
            if (pos > StrLen(text))
                return false        ; ended inside the object: truncated

            if (expect = "colon") {
                if (ch != ":")
                    return false
                pos++, expect := "value"
            } else if (expect = "next") {
                top := stack[stack.Length]
                if (ch = ",") {
                    pos++, expect := (top = "{") ? "key" : "value"
                } else if (ch = (top = "{" ? "}" : "]")) {
                    stack.Pop(), pos++, expect := stack.Length ? "next" : "end"
                } else {
                    return false
                }
            } else if (expect = "key" || expect = "key}") {
                if (ch = "}" && expect = "key}") {
                    stack.Pop(), pos++, expect := stack.Length ? "next" : "end"
                } else if RegExMatch(text, str, &m, pos) {
                    if (stack.Length = 1)
                        id := SK_Unescape(m[1])
                    pos += m.Len, expect := "colon"
                } else {
                    return false
                }
            } else if (ch = "]" && expect = "value]") {
                stack.Pop(), pos++, expect := stack.Length ? "next" : "end"
            } else if (ch = "{" || ch = "[") {
                if (!stack.Length && ch != "{")
                    return false    ; the file is one object
                stack.Push(ch), pos++, expect := (ch = "{") ? "key}" : "value]"
            } else if !stack.Length {
                return false
            } else if RegExMatch(text, str, &m, pos) {
                if (stack.Length = 1 && SubStr(id, 1, 1) != "_")
                    entries[id] := SK_Unescape(m[1])
                pos += m.Len, expect := "next"
            } else if (RegExMatch(text, num, &m, pos) || RegExMatch(text, lit, &m, pos)) {
                pos += m.Len, expect := "next"
            } else {
                return false
            }
        }
    } catch {
        return false
    }
}

; A JSON string's contents, already checked by SK_ParseLocked's pattern, with
; its escapes undone. A \u pair for a character beyond U+FFFF (as Python
; writes one) becomes that character.
SK_Unescape(s) {
    if !InStr(s, "\")
        return s
    out := "", i := 1
    while (j := InStr(s, "\", true, i)) {
        out .= SubStr(s, i, j - i)
        c := SubStr(s, j + 1, 1)
        switch c, true {
            case "u":
                code := Integer("0x" SubStr(s, j + 2, 4)), i := j + 6
                if (code >= 0xD800 && code <= 0xDBFF && SubStr(s, i, 2) == "\u") {
                    low := Integer("0x" SubStr(s, i + 2, 4))
                    if (low >= 0xDC00 && low <= 0xDFFF)
                        code := 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00), i += 6
                }
                out .= Chr(code)
            case "b": out .= "`b", i := j + 2
            case "f": out .= "`f", i := j + 2
            case "n": out .= "`n", i := j + 2
            case "r": out .= "`r", i := j + 2
            case "t": out .= "`t", i := j + 2
            default:  out .= c, i := j + 2      ; " \ /
        }
    }
    return out SubStr(s, i)
}

; The locked file as core writes it, byte for byte: the comment first, then
; the ids in core's order (ordinal, ignoring case), CRLF line ends; written as
; UTF-8 with no byte-order mark (SK_Update).
SK_RenderLocked(entries) {
    ; Sorted by Sort's case-sensitive (ordinal) order on the upper-cased ids,
    ; each line carrying its id's place in a list rather than the id itself,
    ; so no character in an id can upset the sort's separators.
    ids := [], lines := ""
    for id in entries {
        ids.Push(id)
        lines .= RegExReplace(StrUpper(id), "[\x01\x02]", " ") Chr(1) ids.Length Chr(2)
    }
    out := "{`r`n  `"_comment`": `"Supervertaler API keys, locked by Windows to this Windows account. "
         . "They cannot be read on another computer or by another account. Change them in any product's settings.`""
    if (ids.Length > 0) {
        for line in StrSplit(Sort(RTrim(lines, Chr(2)), "C D" Chr(2)), Chr(2)) {
            id := ids[Integer(SubStr(line, InStr(line, Chr(1), true, -1) + 1))]
            out .= ",`r`n  " SK_JsonString(id) ": " SK_JsonString(entries[id])
        }
    }
    return out "`r`n}`r`n"
}

; A JSON string as core's serializer writes one: the short escapes for
; " \ CR LF tab backspace form-feed, \u for the other control characters and
; for ' < > & and the three Unicode line breaks. Base64 needs none of them.
SK_JsonString(s) {
    if !RegExMatch(s, "[\x00-\x1F`"\\'<>&\x{85}\x{2028}\x{2029}]")
        return '"' s '"'
    static short := Map("`r", "\r", "`t", "\t", '"', '\"', "\", "\\", "`n", "\n", "`b", "\b", "`f", "\f")
    out := ""
    Loop Parse s {
        c := A_LoopField
        if short.Has(c)
            out .= short[c]
        else if (Ord(c) < 0x20 || InStr("'<>&", c) || Ord(c) = 0x85 || Ord(c) = 0x2028 || Ord(c) = 0x2029)
            out .= Format("\u{:04x}", Ord(c))
        else
            out .= c
    }
    return '"' out '"'
}

; ---------------------------------------------------------------------------
; Windows' own lock (DPAPI) and base64 - nothing hand-rolled. The contract
; every product keeps: the key, trimmed, as UTF-8 bytes with no byte-order
; mark and no terminating zero; CryptProtectData for the current user,
; CRYPTPROTECT_UI_FORBIDDEN, no description, no entropy; standard base64 with
; padding and no line breaks.
; ---------------------------------------------------------------------------

; Keeps crypt32.dll loaded for as long as Sidekick runs. DllCall loads a DLL
; that is not already loaded for each call and unloads it after, and that
; made every lock and unlock cost about 4.7 ms instead of 0.3.
SK_Crypt32() {
    static lib := DllCall("LoadLibrary", "Str", "crypt32.dll", "Ptr")
    return lib
}

; The key locked to this Windows account, in base64; "" on failure.
SK_Lock(text) {
    if (text = "")
        return ""
    SK_Crypt32()
    size := StrPut(text, "UTF-8") - 1       ; the terminating zero is not part of the key
    plain := Buffer(size + 1)
    StrPut(text, plain, "UTF-8")
    out := SK_Blob()
    if !DllCall("crypt32\CryptProtectData", "Ptr", SK_Blob(plain.Ptr, size), "Ptr", 0, "Ptr", 0,
                "Ptr", 0, "Ptr", 0, "UInt", 0x1, "Ptr", out, "Int") {
        SK_Log(Format("Windows would not lock a key (Windows error 0x{:08X}).", SK_HResult(A_LastError)))
        return ""
    }
    p := NumGet(out, A_PtrSize, "Ptr")
    try return SK_Base64(p, NumGet(out, 0, "UInt"))
    finally DllCall("LocalFree", "Ptr", p, "Ptr")
}

; Unlocks a base64 value made by SK_Lock, or by any other product. False when
; it is not base64 (err 0) or Windows will not unlock it (err is Windows'
; code as an HRESULT, such as 0x8009000B) - for the log only: the user's
; remedy is the same whatever it is.
SK_Unlock(b64, &text, &err) {
    text := "", err := 0
    b64 := Trim(b64)
    if (b64 = "")
        return false
    SK_Crypt32()
    ; CRYPT_STRING_BASE64: first the size, then the bytes.
    if (!DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1,
                 "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0, "Int") || !size)
        return false
    bin := Buffer(size)
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1,
                "Ptr", bin, "UInt*", &size, "Ptr", 0, "Ptr", 0, "Int")
        return false

    out := SK_Blob()
    if !DllCall("crypt32\CryptUnprotectData", "Ptr", SK_Blob(bin.Ptr, size), "Ptr", 0, "Ptr", 0,
                "Ptr", 0, "Ptr", 0, "UInt", 0x1, "Ptr", out, "Int") {
        err := SK_HResult(A_LastError)
        return false
    }
    p := NumGet(out, A_PtrSize, "Ptr")
    n := NumGet(out, 0, "UInt")
    try text := (n = 0) ? "" : StrGet(p, -n, "UTF-8")
    finally DllCall("LocalFree", "Ptr", p, "Ptr")
    return true
}

; A DATA_BLOB: a 4-byte length, then a pointer - 8 bytes on 32-bit
; AutoHotkey, 16 on 64-bit with the padding.
SK_Blob(ptr := 0, size := 0) {
    blob := Buffer(2 * A_PtrSize, 0)
    NumPut("UInt", size, blob, 0)
    NumPut("Ptr", ptr, blob, A_PtrSize)
    return blob
}

; Bytes to standard base64, padded, on one line (CRYPT_STRING_BASE64 |
; CRYPT_STRING_NOCRLF).
SK_Base64(ptr, size) {
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", ptr, "UInt", size, "UInt", 0x40000001,
                "Ptr", 0, "UInt*", &chars := 0, "Int")
        return ""
    out := Buffer(chars * 2)
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", ptr, "UInt", size, "UInt", 0x40000001,
                "Ptr", out, "UInt*", &chars, "Int")
        return ""
    return StrGet(out, chars, "UTF-16")
}

; Windows' error as core logs it: a Win32 code as its HRESULT (13 ->
; 0x8007000D), an HRESULT as it is.
SK_HResult(err) {
    return (err > 0 && err <= 0xFFFF) ? (0x80070000 | err) : (err & 0xFFFFFFFF)
}
