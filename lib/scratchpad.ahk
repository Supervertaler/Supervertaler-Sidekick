#Requires AutoHotkey v2.0
; ===========================================================================
; lib/scratchpad.ahk — what happens to the text on the Scratchpad tab.
;
; Plain text, one file, no structure: data\scratchpad.txt. The tab exists so
; that a thought can be written down in the second it takes to press the key,
; and anything with fields, titles or records to fill in first fails that
; test. The window owns the box (see lib\mainwindow.ahk); this file owns the
; saving.
;
; It is written back a beat after typing stops rather than on every
; keystroke, and again whenever the window closes or the script exits —
; a note that is only safe if the program shuts down cleanly is not safe.
; The exposure is therefore the delay below: kill the process mid-sentence
; and you lose that sentence.
;
; Scale: one note file read once and rewritten whole. Written against a few
; screens of text; a megabyte of notes would still work, but every save
; would rewrite the megabyte. If it ever grows that far it wants appending,
; not this.
; ===========================================================================

global SP_Pending := ""      ; text waiting to be written
global SP_Saved   := ""      ; what the file is known to hold
global SP_Dirty   := false
global SP_Stamp   := ""      ; modification time of our last read or write
global SP_Error   := ""      ; last write failure, "" while all is well
global SP_Blocked := false   ; the file exists but could not be read

; How long to wait after the last keystroke. Long enough that a sentence is
; one write instead of forty, short enough to lose nothing that matters.
SP_DELAY := 1200

SP_File() {
    EnsureDataDir()
    return DataFile("scratchpad.txt")
}

; Read the note. A file that exists but cannot be read is NOT treated as an
; empty note: that would put an empty box on screen and then, at the first
; keystroke, write the empty box over whatever could not be read. Saving is
; switched off instead, and the window says so.
SP_Load() {
    global SP_Saved, SP_Pending, SP_Dirty, SP_Stamp, SP_Blocked, SP_Error

    path := SP_File()
    text := ""
    SP_Blocked := false
    SP_Error := ""

    if FileExist(path) {
        try {
            ; Newlines are kept as bare LF in here, because that is what an
            ; Edit control hands back and what it takes: converting at both
            ; ends of the file instead means the text compared against
            ; SP_Saved is the same text either way round.
            text := StrReplace(FileRead(path, "UTF-8"), "`r`n", "`n")
        } catch Error as err {
            SK_Log("Scratchpad: cannot read " path " — " err.Message)
            SP_Blocked := true
            SP_Error := err.Message
            SP_Saved := "", SP_Pending := "", SP_Dirty := false
            return ""
        }
    }

    SP_Saved := text
    SP_Pending := text
    SP_Dirty := false
    SP_Stamp := SP_FileStamp()
    return text
}

SP_FileStamp() {
    path := SP_File()
    if !FileExist(path)
        return ""
    try return FileGetTime(path, "M")
    catch
        return ""
}

; The file was edited by hand while Sidekick was running. Picking that up
; when the tab is opened costs one FileGetTime; not picking it up means the
; next save quietly overwrites the edit. Anything typed here and not yet
; written wins, because that is the newer text and it is the one on screen.
SP_ChangedOnDisk() {
    global SP_Stamp, SP_Dirty, SP_Blocked
    if (SP_Dirty || SP_Blocked)
        return false
    return SP_FileStamp() != SP_Stamp
}

; Called from the Edit's Change handler: remember the text, restart one
; timer. Nothing here touches the disk.
SP_Touch(text) {
    global SP_Pending, SP_Dirty, SP_DELAY
    SP_Pending := text
    SP_Dirty := true
    SetTimer(SP_Flush, -SP_DELAY)      ; one-shot; an existing one is reset
}

SP_Flush(*) {
    global SP_Pending, SP_Saved, SP_Dirty, SP_Stamp, SP_Error, SP_Blocked

    if (!SP_Dirty || SP_Blocked)
        return !SP_Blocked
    if (SP_Pending == SP_Saved) {
        SP_Dirty := false
        return true
    }

    path := SP_File()
    tmp  := path ".tmp"
    try {
        if FileExist(tmp)
            FileDelete(tmp)
        ; ...and CRLF on the way out, so the file reads properly in
        ; Notepad and anything else Windows offers to open a .txt with.
        FileAppend(StrReplace(SP_Pending, "`n", "`r`n"), tmp, "UTF-8")
        ; Overwrite in one move rather than delete-then-move: an interrupted
        ; save then leaves either the old note or the new one, never neither.
        FileMove(tmp, path, true)
    } catch Error as err {
        ; Stays dirty, so the next flush tries again — and the half-written
        ; temp file goes, so a failed save leaves nothing behind.
        SP_Error := err.Message
        try FileDelete(tmp)
        SK_Log("Scratchpad: save failed — " err.Message)
        return false
    }

    SP_Saved := SP_Pending
    SP_Dirty := false
    SP_Error := ""
    SP_Stamp := SP_FileStamp()
    return true
}

; For the paths that must not lose anything: the window closing, the script
; exiting or reloading.
SP_FlushNow(*) {
    try SetTimer(SP_Flush, 0)          ; cancel the pending one-shot
    return SP_Flush()
}

; The OnExit handler, and it MUST return false.
;
; An OnExit callback that returns a true value cancels the exit — that is what
; the return value is for. Wiring this up as `OnExit((*) => SP_FlushNow())`
; returned the save's own success, so every successful save vetoed the exit:
; the tray's Exit did nothing, Ctrl+R could not reload, and a second copy of
; the script could not replace the first, which left two instances fighting
; over the same hotkeys. Save, then get out of the way.
SP_OnExit(*) {
    try SP_FlushNow()
    return false
}

; What the status bar says while the Scratchpad tab has focus.
SP_StatusText() {
    global SP_Blocked, SP_Error, SP_Dirty
    if SP_Blocked
        return "Scratchpad: data\scratchpad.txt could not be read, so "
             . "nothing is being saved. Move it aside and reload."
    if (SP_Error != "")
        return "Scratchpad: the last save failed (" SP_Error ") — still trying."
    return "Scratchpad — saves itself a moment after you stop typing"
         . "   ·   Ctrl+1 clipboard  ·  Ctrl+2 QuickTrans  ·  Esc close"
}
