#Requires AutoHotkey v2.0
; ===========================================================================
; lib/data.ahk — reading and writing the JSON data files.
;
; All user content (snippets, passwords, bookmarks, searches, prompts) lives
; in data/menu.json. Nothing personal belongs in the .ahk sources, so the
; script itself stays shareable.
; ===========================================================================

; Directory holding this install's user data.
DataDir() {
    return A_ScriptDir "\data"
}

DataFile(name) {
    return DataDir() "\" name
}

; ---------------------------------------------------------------------------
; Map access with a default, so a hand-edited data file missing an optional
; key degrades to a sensible value instead of throwing.
; ---------------------------------------------------------------------------
GetKey(obj, key, default := "") {
    if (obj is Map)
        return obj.Has(key) ? obj[key] : default
    return default
}

LoadJsonFile(path) {
    if !FileExist(path)
        return ""
    try {
        txt := FileRead(path, "UTF-8")
        return Jxon_Load(&txt)
    } catch Error as err {
        MsgBox("Could not read:`n" path "`n`n" err.Message,
               "Beijer.bot", "Icon!")
        return ""
    }
}

SaveJsonFile(path, obj) {
    try {
        txt := Jxon_Dump(obj, 2)
        ; Write to a temp file first, then swap, so an interrupted save can
        ; never leave a half-written data file behind.
        tmp := path ".tmp"
        if FileExist(tmp)
            FileDelete(tmp)
        FileAppend(txt, tmp, "UTF-8-RAW")
        if FileExist(path)
            FileDelete(path)
        FileMove(tmp, path)
        return true
    } catch Error as err {
        MsgBox("Could not save:`n" path "`n`n" err.Message,
               "Beijer.bot", "Icon!")
        return false
    }
}

; ---------------------------------------------------------------------------
; First-run bootstrap: a fresh clone has no data/ directory, only the generic
; data.example/ that ships with the repo.
; ---------------------------------------------------------------------------
EnsureDataDir() {
    dir := DataDir()
    if !DirExist(dir) {
        DirCreate(dir)
        example := A_ScriptDir "\data.example"
        if DirExist(example)
            Loop Files, example "\*.json"
                FileCopy(A_LoopFileFullPath, dir "\" A_LoopFileName, false)
    }
    return dir
}

; Bumped whenever the menu data changes, so views can skip a rebuild.
global BB_MenuRev := 0

LoadMenuData() {
    global BB_MenuRev
    BB_MenuRev++
    EnsureDataDir()
    data := LoadJsonFile(DataFile("menu.json"))
    if (data = "") {
        data := Map()
        data["version"] := 1
        data["menu"] := []
        data["hotstrings"] := []
    }
    if !GetKey(data, "menu", false)
        data["menu"] := []
    if !GetKey(data, "hotstrings", false)
        data["hotstrings"] := []
    return data
}

SaveMenuData(data) {
    global BB_MenuRev
    BB_MenuRev++
    return SaveJsonFile(DataFile("menu.json"), data)
}
