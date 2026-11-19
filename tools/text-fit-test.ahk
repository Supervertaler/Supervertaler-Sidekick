; tools/text-fit-test.ahk — checks TH_EditHeight (lib\theme.ahk), which says
; how tall a box must be to show a wrapped text whole, against what a real
; Edit control does with the same text. The window is never shown; nothing
; here starts Sidekick. The texts are made up.
;
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tools\text-fit-test.ahk
;
; Prints PASS / FAIL / INFO lines; exit code 0 when everything passed.
#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off
#Warn All, StdOut
#Include "..\lib\theme.ahk"

global T_Fails := 0
global T_Seed  := 20261119

Main()
Main() {
global WORDS, T_Fails
WORDS := StrSplit("the a of garden window morning wherein letters weather between and is carried "
    . "through road green holiday per metre translation approximately characterised "
    . "zonnebloemolie verkeersveiligheidscampagne 2.0 3,5 20-40% (ABC) km/h e.g. i.e. "
    . "bicycle station comprises example according front door kitchen arrived in which", " ")

cut := 0, spare := 0, everyday := 0, cases := 0, worst := ""
for points in [7, 9, 11, 14, 20, 28] {
    g := Gui()
    g.SetFont("s" points, "Segoe UI")
    for style in ["Multi ReadOnly -VScroll", "Multi"] {
        box := g.Add("Edit", "x0 y0 w300 r2 " style)
        for width in [130, 180, 257, 300, 411, 520, 777, 1100] {
            box.Move(, , width)
            Loop 60 {
                text := MakeText(A_Index)
                box.Value := text
                lines := SendMessage(0xBA, 0, 0, box)            ; EM_GETLINECOUNT
                lineH := LineHeight(box)
                border := BorderOf(box)
                need := lines * lineH + border                   ; pixels
                got  := TH_EditHeight(box, text, points) * A_ScreenDPI / 96
                cases++
                if (got < need) {
                    cut++
                    if (worst = "")
                        worst := points "pt, " width " wide, " lines " lines: needs " need " px, given " Round(got)
                } else if (points <= 14 && width >= 257) {
                    everyday++
                    if (got >= need + lineH)
                        spare++
                }
            }
        }
        box.Visible := false
    }
    g.Destroy()
}
Check(cut = 0, "no text cut off in " cases " boxes (6 sizes, 8 widths, with and without a scrollbar)"
    . (cut ? " - " cut " were; first: " worst : ""))
; A spare line is the price of never cutting: an Edit also breaks after a
; hyphen, and a word longer than the box is allowed a line of its own.
Check(spare <= everyday * 0.05, "at everyday sizes (up to 14pt, 257 wide or more) a spare line in "
    . spare " of " everyday ", no more than 5%")

; The limits.
g := Gui()
g.SetFont("s11", "Segoe UI")
box := g.Add("Edit", "x0 y0 w400 r2 Multi ReadOnly -VScroll")
one  := TH_EditHeight(box, "", 11)
Check(one > 0 && TH_EditHeight(box, "word", 11) = one, "an empty box is one line tall")
Check(TH_EditHeight(box, "word", 11, 3) > one * 2, "never shorter than the minimum asked for")
long := ""
Loop 400
    long .= "wherein the garden "
six := TH_EditHeight(box, long, 11, 1, 6)
Check(six < one * 6 + 1 && six > one * 4, "never taller than the maximum asked for")
Check(TH_EditHeight(box, "one`r`ntwo`r`n", 11) > TH_EditHeight(box, "one`r`ntwo", 11),
      "a text ending in a line break gets its empty last line")
t0 := A_TickCount
Loop 200
    TH_EditHeight(box, long, 11, 1, 6)
ms := (A_TickCount - t0) / 200
Check(ms < 15, "a 7,200-character text, cut to what a 6-line box could hold, is measured in " Round(ms, 2) " ms")
g.Destroy()

Say(T_Fails ? T_Fails " failed" : "all passed")
ExitApp(T_Fails ? 1 : 0)
}

; Made-up sentences of different lengths, the same ones on every run.
MakeText(n) {
    global WORDS
    count := 3 + Mod(Rand(), 70)
    text := ""
    Loop count {
        text .= WORDS[1 + Mod(Rand(), WORDS.Length)]
        text .= (Mod(Rand(), 40) = 0) ? "`r`n" : " "
    }
    return RTrim(text, " ")
}

Rand() {
    global T_Seed
    T_Seed := Mod(T_Seed * 1103515245 + 12345, 2147483648)
    return T_Seed >> 8
}

LineHeight(ctrl) {
    hFont := SendMessage(0x31, 0, 0, ctrl)                       ; WM_GETFONT
    hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
    tm := Buffer(60, 0)
    DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)
    return NumGet(tm, 0, "Int")
}

BorderOf(ctrl) {
    cl := Buffer(16, 0), wr := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", cl)
    DllCall("GetWindowRect", "Ptr", ctrl.Hwnd, "Ptr", wr)
    return NumGet(wr, 12, "Int") - NumGet(wr, 4, "Int") - NumGet(cl, 12, "Int")
}

Check(ok, name) {
    global T_Fails
    if !ok
        T_Fails++
    Say((ok ? "PASS  " : "FAIL  ") name)
}

Say(line) {
    FileAppend(line "`n", "*")
}
