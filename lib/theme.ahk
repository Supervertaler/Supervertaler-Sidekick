#Requires AutoHotkey v2.0
; ===========================================================================
; lib/theme.ahk — how Sidekick's windows look.
;
; The colours are supervertaler.com's light theme (its CSS variables of the
; same names), so the program and the site read as one thing: white paper,
; near-black ink, and the purple of the Sv mark for whatever is the brand's
; or the thing to press.
;
; Also here: measuring how tall a box of wrapped text has to be. That is
; about fit rather than colour, but it is the same kind of question - what
; will this look like on screen - and it has no better home.
; ===========================================================================

TH_PAPER     := "FFFFFF"    ; boxes, lists and panes
TH_WASH      := "F7F5FC"    ; the window and its title bar: the site's faint purple
TH_INK       := "0A0A0A"    ; text
TH_INK_FAINT := "6B6B6B"    ; hints, the status line, model names
TH_BRAND     := "6D28D9"    ; the purple
TH_TINT      := "F3EFFB"    ; a purple wash, for the selected translation

; The title bar in the same faint purple as the window, so the two read as
; one surface, with a thin purple line round the whole window. Not the full
; purple: that was tried on 2026-11-19 and the Sv mark, a purple disc,
; vanished into it. Windows 11 only: Windows 10 has no such setting, returns
; an error, and keeps its usual title bar.
TH_Caption(hwnd) {
    global TH_BRAND, TH_WASH, TH_INK
    ; DWMWA_BORDER_COLOR 34, DWMWA_CAPTION_COLOR 35, DWMWA_TEXT_COLOR 36.
    for attr, rgb in Map(34, TH_BRAND, 35, TH_WASH, 36, TH_INK) {
        value := Buffer(4, 0)
        NumPut("UInt", TH_Bgr(rgb), value)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr,
                    "Ptr", value, "UInt", 4)
    }
}

; "RRGGBB" as the 0x00BBGGRR number Windows wants.
TH_Bgr(rgb) {
    n := Integer("0x" rgb)
    return ((n & 0xFF) << 16) | (n & 0xFF00) | ((n >> 16) & 0xFF)
}

; The lists as File Explorer draws them: a soft highlight and arrows for
; folders, rather than the Windows 95 dotted lines and boxed plus signs.
TH_ExplorerLook(ctrl) {
    try DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "Explorer",
                "Ptr", 0)
}

; The one purple button on a window: the thing it is for. A Text control,
; because a real Button takes its colours from Windows and cannot be given
; any; so it cannot hold the keyboard focus, and whatever it does needs a key
; of its own.
TH_PrimaryButton(gui, options, text, onClick) {
    global TH_BRAND
    gui.SetFont("s9 Bold cFFFFFF")
    ; 0x200 SS_CENTERIMAGE: the text in the middle top to bottom as well.
    btn := gui.Add("Text", options " Center 0x200 Background" TH_BRAND, text)
    gui.SetFont("s9 Norm c" TH_INK)
    btn.OnEvent("Click", onClick)
    return btn
}

; ---------------------------------------------------------------------------
; How tall a multi-line Edit has to be to show a text without cutting any of
; it off, at the width the control has now.
;
; Until 2026-11-19 this was guessed: characters divided by an average
; character width. Words wrap whole, so a line holds fewer characters than
; the average says, and a translation regularly needed one line more than it
; was given - its last line showed as a sliver. This asks Windows to lay the
; text out the way an Edit does (DT_EDITCONTROL) and reads off the height.
;
; ctrl       the Edit, already at its final width
; points     its font size (Segoe UI)
; minLines, maxLines   never shorter or taller than this many lines
; Returns the height for ctrl.Move, in the same units.
;
; No SendMessage: the QuickTrans layout calls this once per box, and a sent
; message in the middle of a layout is what let a timer land inside one (see
; MW_QTLayout). GetDC, DrawText and the rest are plain calls.
; ---------------------------------------------------------------------------
TH_EditHeight(ctrl, text, points, minLines := 1, maxLines := 1000) {
    static DT_FLAGS := 0x400 | 0x10 | 0x2000 | 0x800 | 0x40
        ; CALCRECT, WORDBREAK, EDITCONTROL, NOPREFIX, EXPANDTABS
    scale := A_ScreenDPI / 96

    client := Buffer(16, 0), outer := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", client)
    DllCall("GetWindowRect", "Ptr", ctrl.Hwnd, "Ptr", outer)
    frame := (NumGet(outer, 12, "Int") - NumGet(outer, 4, "Int"))
            - NumGet(client, 12, "Int")
    clientW := NumGet(client, 8, "Int")

    lineH := 0, textH := 0
    hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
    if !hdc
        return Ceil((minLines * points * 1.7) + 8)      ; a guess beats a crash
    try {
        old := DllCall("SelectObject", "Ptr", hdc, "Ptr", TH_Font(points), "Ptr")
        try {
            tm := Buffer(60, 0)                         ; TEXTMETRICW
            DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm)
            lineH := NumGet(tm, 0, "Int")               ; tmHeight
            ; An Edit keeps half an average character clear either side of
            ; its text, and a pixel more each side inside that. Measured at
            ; twelve sizes; tools	ext-fit-test.ahk holds it to that.
            ; The last term is a sliver more, growing with the font (3px at
            ; 28pt): without it 11 boxes in 5,760 came out a line short, all
            ; at 28pt, where a word that fits by a pixel here does not there.
            ave := Max(1, NumGet(tm, 20, "Int"))
            textW := clientW - 2 * (ave // 2) - 2 - Round(3 * ave / 25)
            if (textW < 20)
                textW := 20

            ; A text ending in a line break has an empty last line, which
            ; DrawText does not count and an Edit shows.
            shown := (text = "" || SubStr(text, -1) = "`n") ? text "X" : text
            ; Only as much of a long text as could fill the tallest the box
            ; may be: no line holds more characters than it has pixels / 2.
            if (maxLines < 1000)
                shown := SubStr(shown, 1, maxLines * (textW // 2 + 1))
            rc := Buffer(16, 0)
            NumPut("Int", textW, rc, 8)
            textH := DllCall("DrawTextW", "Ptr", hdc, "Str", shown,
                             "Int", -1, "Ptr", rc, "UInt", DT_FLAGS)

            ; A word too long for a line is the one case where DrawText and
            ; an Edit break in different places, and the Edit can come out a
            ; line longer. A spare line for each such word covers it. Only
            ; words long enough to be candidates are measured at all.
            pos := 1, size := Buffer(8, 0)
            while (pos := RegExMatch(shown, "\S{" Max(2, textW // (2 * ave)) ",}", &word, pos)) {
                DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", word[0],
                        "Int", word.Len, "Ptr", size)
                if (NumGet(size, 0, "Int") > textW)
                    textH += lineH
                pos += word.Len
            }
        } finally
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    } finally
        DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)

    if (lineH < 1)
        lineH := Round(points * scale * 1.7)
    textH := Max(textH, minLines * lineH)
    textH := Min(textH, maxLines * lineH)
    ; The Edit starts its text a pixel or so below its top edge; the rest of
    ; the 6 is so the last line's descenders are not against the border.
    return Ceil((textH + frame + 6 * scale) / scale)
}

; Segoe UI at a size, as AutoHotkey makes it for a control. Kept for the life
; of the program: there is one per text size ever used, and the text size
; only goes from 7 to 28.
TH_Font(points) {
    static fonts := Map()
    if !fonts.Has(points)
        fonts[points] := DllCall("CreateFontW"
            , "Int", -Round(points * A_ScreenDPI / 72), "Int", 0, "Int", 0, "Int", 0
            , "Int", 400, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
            , "UInt", 4, "UInt", 0, "UInt", 0, "UInt", 0, "Str", "Segoe UI", "Ptr")
    return fonts[points]
}
