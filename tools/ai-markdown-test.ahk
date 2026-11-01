; tools/ai-markdown-test.ahk — offline tests for the AI window's Markdown
; (lib\markdown.ahk) and the window that shows it (lib\ai.ahk).
;
; Not run on its own. tools\ai-markdown-test.ps1 points APPDATA - and with it
; the data root and the key files - at a scratch folder, writes a small
; script there that includes Sidekick's lib files and this one, and runs one
; phase of it at a time, in 64-bit and 32-bit AutoHotkey; settings.ini is the
; scratch folder's too. The "send" phase asks a fake provider the runner
; serves on 127.0.0.1, never a real one.
;
; Windows are built and never shown, but for one moment in "window", where
; the AI window is shown far off screen, without a taskbar button, to see
; that Escape still closes it.
;
; Nothing here touches the clipboard: the Sidekick that is running would
; record whatever went on it in its clipboard history, in the real data
; folder. Copy is tested up to what it hands AutoHotkey to put there; Insert
; up to the text it would type.
;
; Results go to run\results-<phase>-<bits>.txt as PASS / FAIL / INFO lines.

global T_Root    := A_Args.Length >= 1 ? A_Args[1] : ""
global T_Phase   := A_Args.Length >= 2 ? A_Args[2] : ""
global T_Results := A_ScriptDir "\results-" T_Phase "-" (A_PtrSize * 8) ".txt"
global T_Fails   := 0
global T_FakeUrl := ""
global T_Box     := ""          ; a hidden answer box, for the convert phase
global T_Menu    := 0           ; what the answer box's right-click sent its window

; The one test key. Made up; the runner checks it turns up nowhere but the
; file meant to hold it.
global KA := "sk-ant-test-Markdown-PROJ-001"

T_Main()

T_Main() {
    DirCreate(A_ScriptDir "\data")          ; for SK_Log's sidekick.log
    T_Guard()
    switch T_Phase, false {
        case "convert": T_ConvertPhase()
        case "window":  T_WindowPhase()
        case "send":    T_SendPhase()
        default:
            T_Line("FAIL  unknown phase '" T_Phase "'")
            ExitApp(2)
    }
    ExitApp(T_Fails ? 1 : 0)
}

; Before anything else: the key files, settings.ini and the data folder must
; be in the scratch folder, never the user's own. Stops the run otherwise.
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
; Phase "convert": Markdown in, RTF and plain text out, and what a real (but
; hidden) answer box makes of that RTF.
; ---------------------------------------------------------------------------
T_ConvertPhase() {
    global T_Box
    static hidden := Gui()
    T_Box := AI_AddAnswerBox(hidden, "w700 h380")
    T_Sample()
    T_Lists()
    T_Code()
    T_Tables()
    T_InlineMarks()
    T_NonAscii()
    T_Malformed()
    T_Empty()
    T_NoMarkdown()
    T_Messages()
    T_ClipLayout()
    T_Fuzz()
    T_Scale()
}

; A realistic answer: the δ explanation of 1 Nov, with what models add to it.
T_Sample() {
    md := T_Fixture("ai-markdown-sample.md")
    want := T_Fixture("ai-markdown-sample.txt")
    r := T_Show(md)
    T_Check(r["ok"], "sample: the answer box reads all of the RTF")
    T_Eq(r["text"], want, "sample: the plain text - marks gone, each line kept, bullets as • and ◦")
    T_Eq(T_Visible(r["shown"]), T_Visible(want), "sample: the box shows the same characters as the plain text")
    T_Check(!RegExMatch(r["rtf"], "[^\x00-\x7F]"), "sample: the RTF is all ASCII (everything else as \uN)")
    T_Check(T_Balanced(r["rtf"]), "sample: every { in the RTF is closed")

    f := T_Fmt(T_Box, "The Symbol")
    T_Check(f["bold"] && f["size"] = 16, "sample: # heading - bold, 16pt", T_Desc(f))
    f := T_Fmt(T_Box, "Mathematics")
    T_Check(f["bold"] && f["size"] = 14, "sample: ## heading - bold, 14pt", T_Desc(f))
    f := T_Fmt(T_Box, "At a glance")
    T_Check(f["bold"] && f["size"] = 12, "sample: ### heading - bold, 12pt", T_Desc(f))
    f := T_Fmt(T_Box, "is the lowercase form")
    T_Check(!f["bold"] && !f["italic"] && f["size"] = 11 && f["face"] = "Calibri",
        "sample: body text - Calibri 11pt, as the window", T_Desc(f))
    f := T_Fmt(T_Box, "Small change/increment")
    T_Check(f["bold"] && !f["italic"], "sample: **bold** inside a bullet", T_Desc(f))
    f := T_Fmt(T_Box, "epsilon-delta")
    T_Check(f["italic"] && !f["bold"], "sample: *italic*", T_Desc(f))
    f := T_Fmt(T_Box, "sum(")
    T_Check(f["face"] = "Consolas" && f["size"] = 10, "sample: a code span in Consolas", T_Desc(f))
    f := T_Fmt(T_Box, "ij", 1, "Kronecker delta (" Chr(0x3B4))
    T_Check(f["sub"] && f["bold"], "sample: <sub>ij</sub> subscript, and still bold", T_Desc(f))
    f := T_Fmt(T_Box, "-1", 1, "depth, in m")
    T_Check(f["sup"], "sample: <sup>-1</sup> superscript", T_Desc(f))
    f := T_Fmt(T_Box, "δ(i,j)")
    T_Check(f["strike"], "sample: ~~struck~~", T_Desc(f))
    f := T_Fmt(T_Box, "In Dutch and German")
    T_Check(f["color"] = 0x606060, "sample: a > quote in grey", T_Desc(f))
    f := T_Fmt(T_Box, "Meaning")
    T_Check(f["bold"], "sample: a table's first row in bold", T_Desc(f))
    f := T_Fmt(T_Box, "def kronecker")
    T_Check(f["face"] = "Consolas", "sample: a fenced block in Consolas", T_Desc(f))

    top := T_Indent(T_Box, "Small change/increment")
    nested := T_Indent(T_Box, "Used in")
    para := T_Indent(T_Box, "is the lowercase form")
    T_Check(para["first"] = 0 && top["rest"] > top["first"] && nested["rest"] > top["rest"],
        "sample: bullets hang, nested ones further in",
        "para " para["first"] " top " top["first"] "/" top["rest"] " nested " nested["first"] "/" nested["rest"])
    T_Check(InStr(r["shown"], Chr(0x2022) "`tSmall change") && InStr(r["shown"], "Field`tMeaning`tUnit"),
        "sample: in the box a tab follows a bullet, and parts table cells (as Word copies them)")
}

T_Lists() {
    T_Plain("- a`n  - b`n    - c`n  - d`n- e", "• a`n  ◦ b`n    ▪ c`n  ◦ d`n• e", "lists: three levels by two-space indents")
    T_Plain("- a`n    - b`n        - c", "• a`n  ◦ b`n    ▪ c", "lists: by four-space indents")
    T_Plain("- a`n`t- b", "• a`n  ◦ b", "lists: by a tab")
    T_Plain("* star`n+ plus", "• star`n• plus", "lists: * and + are bullets too")
    T_Plain("1. One`n   - sub`n2. Two`n10) Ten", "1. One`n  ◦ sub`n2. Two`n10) Ten", "lists: numbers kept as written, bullets under them")
    T_Plain("- item`n  more of it`n- next", "• item`n  more of it`n• next", "lists: an indented line goes on with the item")
    T_Plain("- a`n`n- b", "• a`n`n• b", "lists: blank lines between items stay")
    T_Plain("- [ ] to do`n- [x] done", "• " Chr(0x2610) " to do`n• " Chr(0x2611) " done", "lists: task boxes")
    T_Plain("- a`nNot in the list", "• a`nNot in the list", "lists: a line at the margin ends the list")
    r := T_Show("- a`nNot in the list")
    T_Eq(T_Indent(T_Box, "Not in")["first"], 0, "lists: ... and is not indented")
    T_Plain("- `n-`n1.", "-`n-`n1.", "lists: a marker with nothing after it is just text")
    T_Plain("2023. Het jaar van Acme", "2023. Het jaar van Acme", "lists: a year at the start of a line comes out as typed")
}

T_Code() {
    md := T_B("§§§python`nx = **1**`n# not a heading`n- not a bullet`n§§§")
    T_Plain(md, "x = **1**`n# not a heading`n- not a bullet", "code: nothing inside a fenced block is Markdown")
    T_Check(T_Fmt(T_Box, "x = ")["face"] = "Consolas" && !T_Fmt(T_Box, "1")["bold"], "code: in Consolas, not bold")
    T_Plain("~~~`ncode`n~~~`nafter", "code`nafter", "code: ~~~ fences")
    T_Plain(T_B("§§§§`n§§§`ninner`n§§§`n§§§§"), T_B("§§§`ninner`n§§§"), "code: a longer fence holds a shorter one")
    T_Plain(T_B("text`n§§§`nnever closed`n**b**"), "text`nnever closed`n**b**", "code: an unclosed fence runs to the end")
    T_Plain(T_B("- item`n  §§§`n  indented()`n    deeper()`n  §§§"), "• item`nindented()`n  deeper()", "code: a block inside a list item")
    T_Plain(T_B("Use §§a§b§§ or §§ §x§ §§"), T_B("Use a§b or §x§"), "code: backticks inside code")
    T_Plain(T_B("a §\§ b"), "a \ b", "code: a backslash in code stays")
}

T_Tables() {
    md := "| Term | Acme | n |`n|:--|:-:|--:|`n| **δ** | yes | 1 |`n| ε | no | 22 |"
    T_Plain(md, "Term | Acme | n`nδ | yes | 1`nε | no | 22", "tables: rows of cells between ' | ', the --- row gone")
    r := T_Show(md)
    T_Check(InStr(r["rtf"], "\qc ") && InStr(r["rtf"], "\qr ") && InStr(r["rtf"], "\cellx"), "tables: an RTF table, centred and right-aligned as marked")
    T_Check(T_Fmt(T_Box, "Term")["bold"] && T_Fmt(T_Box, "δ")["bold"] && !T_Fmt(T_Box, "yes")["bold"], "tables: header and **marks** in cells bold, the rest not")
    T_Eq(r["shown"], "Term`tAcme`tn`nδ`tyes`t1`nε`tno`t22`n`n", "tables: the box's own text, a cell per tab (and the paragraph a table must end with)")
    T_Plain("| a \| b | c |`n|---|---|`n| 1 | 2 |", "a | b | c`n1 | 2", "tables: \| is a pipe in a cell")
    T_Plain("| a | b |`n|---|---|`n| 1 |`n| 1 | 2 | 3 |", "a | b`n1 | `n1 | 2", "tables: short rows filled, long ones cut, as GFM does")
    T_Plain("a | b`nc | d", "a | b`nc | d", "tables: no --- row, no table")
    T_Plain("| a | b |`n|---|", "| a | b |`n|---|", "tables: a --- row of another width, no table")
    wide := "|", delim := "|", row := "|"
    Loop 10
        wide .= " Column " A_Index " |", delim .= "---|", row .= " " T_Repeat("word ", 20) "|"
    r := T_Show(wide "`n" delim "`n" row, 7000)
    RegExMatch(r["rtf"], "\\cellx(\d+)\\pard", &last)
    T_Check(r["ok"] && last[1] + 0 <= 7000 + 10, "tables: ten wide columns squeezed into the room there is", "last edge " last[1])
}

T_InlineMarks() {
    T_Plain(T_B("**b** *i* ***bi*** ~~s~~ §c§ __b2__ _i2_"), "b i bi s c b2 i2", "inline: each kind of mark comes off")
    r := T_Show("**bold *and italic* inside**")
    T_Check(T_Fmt(T_Box, "and italic")["italic"] && T_Fmt(T_Box, "and italic")["bold"] && !T_Fmt(T_Box, "inside")["italic"],
        "inline: marks nest")
    T_Plain("snake_case_name, file_v2_final.docx, 5 * 3 * 2, 2*3", "snake_case_name, file_v2_final.docx, 5 * 3 * 2, 2*3",
        "inline: underscores inside words and spaced stars are not marks")
    T_Plain("\*not italic\* and \# and \\", "*not italic* and # and \", "inline: \ escapes a mark")
    T_Plain("[Acme](https://acme.example/a_(b)) and [https://x.example](https://x.example)",
        "Acme (https://acme.example/a_(b)) and https://x.example", "inline: links - the text, then where to")
    T_Plain("<https://acme.example/PROJ-001>", "https://acme.example/PROJ-001", "inline: <url>")
    T_Plain("H<sub>2</sub>O, m<sup>2</sup>, x<sup>n</sup>, E<sub>kin</sub>, X<SUP>abc</SUP>",
        "H₂O, m², xⁿ, Eₖᵢₙ, Xabc", "inline: sub- and superscript as Unicode where it exists")
    T_Plain("one<br>two<br/>three", "one`ntwo`nthree", "inline: <br>")
}

; Greek, accents, CJK, Arabic, emoji - and an emoji built of several.
T_NonAscii() {
    s := "Ελληνικά: δ Δ ε. Français: é è ü ß ø Å œ. 中文 德尔塔 日本語 한국어. مرحبا. "
       . T_B("😀 👩‍💻 🇳🇱 é (e + combining accent)`n**Ελληνικά** and _français_ and §日本語§")
    r := T_Show(s)
    want := StrReplace(StrReplace(StrReplace(s, "**"), "_français_", "français"), "``")
    T_Eq(r["text"], want, "non-ASCII: the plain text keeps every character")
    T_Eq(r["shown"], want "`n", "non-ASCII: the box shows every character, surrogate pairs and joiners too")
    T_Check(T_Fmt(T_Box, "Ελληνικά", 2)["bold"], "non-ASCII: **Greek** in bold")
}

; Markdown gone wrong: shown as written, never dropped, never a crash.
T_Malformed() {
    T_Plain("Unclosed **bold and a stray # here", "Unclosed **bold and a stray # here", "malformed: an unclosed ** stays")
    T_Plain("#hashtag`n#`n**`n``", "#hashtag`n#`n**`n``", "malformed: # without a space, a lone ** or backtick")
    T_Plain("[link](`n<sub>x`na\", "[link](`n<sub>x`na\", "malformed: half a link, an open tag, a closing backslash")
    T_Plain("***a **b", "***a **b", "malformed: *** and ** left open")
    rtfish := "{\rtf1\ansi {\b not bold}} \par \u948? }}}{{{ \object"
    r := T_Show(rtfish)
    T_Check(r["ok"] && r["shown"] == rtfish "`n" && !T_Fmt(T_Box, "not bold")["bold"],
        "malformed: RTF in an answer is shown as text, never obeyed")
    T_Plain("**" T_Repeat("x", 900) "**", T_Repeat("x", 900), "malformed: bold over 900 characters is bold")
    long := "**" T_Repeat("x", 1500) "**"
    T_Plain(long, long, "malformed: a mark that closes 1,500 characters on is not one, and stays as typed")
}

T_Empty() {
    r := T_Show("")
    T_Check(r["ok"] && r["text"] = "" && r["shown"] = "", "empty: nothing in, nothing shown")
    r := T_Show("  `n`n`t`n ")
    T_Check(r["ok"] && r["text"] = "" && r["shown"] = "", "empty: blank lines only, nothing shown")
    T_Plain("`n`nText`n`n", "Text", "empty: blank lines at either end go")
}

; A translation or a proofread - the answers Insert is for - has no Markdown,
; and must come out exactly as the AI wrote it.
T_NoMarkdown() {
    s := "Dit is de vertaling van PROJ-001 voor Acme.`n"
       . "Regel twee: 5 * 3 = 15, bestand_naam_v2.docx, C# en F#, item #3, 2 - 1 = 1, 100 % zeker.`n`n"
       . "Derde alinea met „aanhalingstekens” en ‘enkele’ – en een gedachtestreepje…  `n"
       . "    Ingesprongen regel, {accolades}, \backslash, <tag> en |pijp|."
    want := StrReplace(s, "…  `n", "…`n")
    want := StrReplace(want, "    Ingesprongen", "Ingesprongen")
    T_Plain(s, want, "no Markdown: a translation comes out as written (bar trailing spaces and indents)")
}

; Errors and messages are not Markdown: shown and copied exactly.
T_Messages() {
    msg := "The API returned status 500.`n`n{`"error`": {`"message`": `"**Overloaded** - # try later`"}}"
    r := MD_RenderPlain(msg)
    T_Check(AI_PutRtf(T_Box, r["rtf"]), "messages: the box reads it")
    T_Eq(r["text"], msg, "messages: the text is the message, ** and all")
    T_Eq(T_Shown(T_Box), msg "`n", "messages: and so is what the box shows")
    T_Check(!T_Fmt(T_Box, "Overloaded")["bold"], "messages: nothing in bold")
    T_Check(!AI_PutRtf(T_Box, "{\rtf1 {{{ broken"), "messages: RTF the box can't read is reported, so the window can fall back")
}

; What Copy hands AutoHotkey: the ClipboardAll layout, read back here.
T_ClipLayout() {
    static CF_RTF := DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt")
    text := "Line δ`nLine 😀"
    rtf := MD_Render("**Line** δ")["rtf"]
    data := AI_ClipData(text, rtf)
    p := data.Ptr
    f1 := NumGet(p, 0, "UInt"), n1 := NumGet(p, 4, "UInt")
    t := StrGet(p + 8, "UTF-16")
    f2 := NumGet(p, 8 + n1, "UInt"), n2 := NumGet(p, 12 + n1, "UInt")
    r := StrGet(p + 16 + n1, "CP0")
    T_Check(data is ClipboardAll, "copy: a ClipboardAll")
    T_Check(f1 = 13 && t == "Line δ`r`nLine 😀" && n1 = (StrLen(t) + 1) * 2, "copy: the text first, as Unicode, lines ending in CR LF")
    T_Check(f2 = CF_RTF && r == rtf && n2 = StrLen(rtf) + 1, "copy: then the RTF, as 'Rich Text Format'")
    T_Check(NumGet(p, 16 + n1 + n2, "UInt") = 0 && data.Size = 20 + n1 + n2, "copy: then the closing 0, and nothing after")
}

; Random Markdown-ish text: the box must take every RTF made of it, and show
; the same characters as the plain text Copy and Insert hand on.
T_Fuzz() {
    static bits := ["**", "*", "_", "__", "``", "``````", "~~", "# ", "## ", "- ", "  - ", "1. ", "> ", "|", "---",
        "\", "{", "}", "[", "](", "https://acme.example/x_y", ")", "<sub>", "</sub>", "<sup>", "</sup>", "<br>", "<",
        " ", " ", "word", "PROJ-001", "δ", "é", "德", "😀", "`t", "`n", "`n", "`n`n", "\par", "{\rtf1", "\u948?"]
    seed := 20261101, bad := 0, first := ""
    Loop 400 {
        s := ""
        Loop 1 + Mod(T_Next(&seed), 40)
            s .= bits[1 + Mod(T_Next(&seed), bits.Length)]
        r := T_Show(s)
        if !r["ok"] || T_Visible(r["shown"]) !== T_Visible(r["text"]) {
            bad++
            if (first = "")
                first := s
        }
    }
    T_Check(bad = 0, "fuzz: 400 random answers, each read in full and shown as its plain text",
        bad " differ; the first: " StrReplace(StrReplace(first, "`n", "\n"), "`t", "\t"))
}

; 100 times a normal answer, and lines no answer should have.
T_Scale() {
    md := T_Fixture("ai-markdown-sample.md")
    big := ""
    Loop 100
        big .= md "`n`n"
    T_Time(big, "scale: 100 sample answers, " Round(StrLen(big) / 1024) " KB, " T_LineCount(big) " lines")

    open := RTrim(T_Repeat("a *b _c ~~d [e](f **g ", 5000))
    T_Time(open, "scale: one " Round(StrLen(open) / 1024) " KB line of marks that never close", true)

    cjk := ""
    Loop 1000
        cjk .= "- **德尔塔** 是希腊字母表的第四个字母，δ 在数学中表示一个很小的变化量。😀`n"
    T_Time(cjk, "scale: 1,000 lines of Chinese and emoji, " Round(StrLen(cjk) / 1024) " K characters")
}

; Converts, shows and times one long answer; checks nothing went missing on
; the way - the box starts out holding only 32,767 characters.
T_Time(md, name, same := false) {
    t0 := A_TickCount
    r := MD_Render(md)
    t1 := A_TickCount
    ok := AI_PutRtf(T_Box, r["rtf"])
    t2 := A_TickCount
    shown := T_Shown(T_Box)
    T_Info(name ": convert " (t1 - t0) " ms, show " (t2 - t1) " ms; " StrLen(shown) " characters in the box")
    T_Check(ok && T_Visible(shown) == T_Visible(r["text"]) && (!same || r["text"] == md),
        name ": all of it shown, past the 32,767 characters an edit box starts out with")
    T_Check(t2 - t0 < 5000, name ": under 5 s", (t2 - t0) " ms")
}

; ---------------------------------------------------------------------------
; Phase "window": the real AI window, built and not shown.
; ---------------------------------------------------------------------------
T_WindowPhase() {
    global AI_Window, AI_Output, AI_Answer, T_Menu
    AI_BuildWindow()
    T_Eq(WinGetClass(AI_Output), "RICHEDIT50W", "window: the answer box is a rich edit control")
    T_Check(ControlGetStyle(AI_Output) & 0x800, "window: read-only")

    md := T_Fixture("ai-markdown-sample.md")
    want := T_Fixture("ai-markdown-sample.txt")
    AI_ShowAnswer(md, true)
    T_Check(AI_Answer["raw"] == md && AI_Answer["text"] == want, "window: an answer - the Markdown kept, the plain text ready")
    T_Eq(T_Visible(T_Shown(AI_Output)), T_Visible(want), "window: and shown")
    T_Check(T_Fmt(AI_Output, "Small change/increment")["bold"], "window: formatted")
    T_Eq(AI_Answer["text"], want, "window: Insert would type the plain text")      ; AI_Insert sends AI_Answer["text"]
    room := AI_TableRoom()
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", AI_Output.Hwnd, "Ptr", rc)
    w := NumGet(rc, 8, "Int") * 1440 / A_ScreenDPI
    T_Check(room > 5000 && room < w - 300, "window: a table gets the box's width, less margins", room " of " Round(w) " twips")

    msg := "The API returned status 401.`n`n{`"error`": `"**invalid** # key`"}"
    AI_ShowAnswer(msg)
    T_Check(AI_Answer["text"] == msg && T_Shown(AI_Output) == msg "`n" && !T_Fmt(AI_Output, "invalid")["bold"],
        "window: a message shown exactly as it is")
    AI_ShowAnswer("")
    T_Check(AI_Answer["text"] = "" && T_Shown(AI_Output) = "", "window: cleared while thinking")

    ; Bigger: the answer takes the room, the buttons stay under it, in a row.
    AI_ShowAnswer(md, true)
    AI_OnSize(AI_Window, 0, 1100, 800)
    AI_Output.GetPos(&bx, &by, &bw, &bh)
    rows := Map(), right := 0
    for ctrl in AI_Window {
        if (ctrl.Type = "Button") {
            ctrl.GetPos(&x, &y, &cw)
            rows[y] := 1, right := Max(right, x + cw)
        }
    }
    T_Check(bh >= 650 && rows.Count = 1 && rows.Has(by + bh + 8) && right <= 1100,
        "window: resized, the buttons stay under the answer", "box " bx "," by " " bw "x" bh "; button rows " rows.Count)
    AI_OnSize(AI_Window, 0, 700, 450)
    AI_Output.GetPos(, &by, , &bh)
    for ctrl in AI_Window
        if (ctrl.Type = "Button")
            ctrl.GetPos(, &y)
    T_Check(y = by + bh + 8, "window: and smaller again")

    ; Right-click: the box has no menu of its own, and must pass the click on.
    OnMessage(0x7B, T_OnContextMenu)                     ; WM_CONTEXTMENU
    PostMessage(0x204, 2, 0x00140014, AI_Output)         ; WM_RBUTTONDOWN at 20,20
    PostMessage(0x205, 0, 0x00140014, AI_Output)         ; WM_RBUTTONUP
    Sleep(200)
    OnMessage(0x7B, T_OnContextMenu, 0)
    T_Eq(T_Menu, AI_Output.Hwnd, "window: a right-click in the answer reaches the window, for its menu")
    SendMessage(0xB1, 0, 0, AI_Output)                   ; EM_SETSEL nothing
    T_Check(!AI_HasSelection(), "window: menu - Copy greyed with nothing selected")
    SendMessage(0xB1, 4, 10, AI_Output)
    T_Check(AI_HasSelection(), "window: menu - Copy there with something selected")

    ; Escape still closes the window when the answer has the focus. Shown
    ; far off screen for this, without a taskbar button.
    AI_Window.Opt("+ToolWindow")
    AI_Window.Show("x-32000 y-32000 NoActivate")
    PostMessage(0x100, 0x1B, 0x00010001, AI_Output)      ; WM_KEYDOWN Escape
    Sleep(200)
    T_Check(!DllCall("IsWindowVisible", "Ptr", AI_Window.Hwnd), "window: Escape in the answer closes the window")
    AI_Window.Hide()
}

T_OnContextMenu(wParam, lParam, msg, hwnd) {
    global T_Menu
    T_Menu := wParam
    return 0                                            ; handled: no menu in a test
}

; ---------------------------------------------------------------------------
; Phase "send": AI actions ask a fake provider on 127.0.0.1, which answers
; with whatever fake-answer.txt holds, with the status in fake-status.txt.
; ---------------------------------------------------------------------------
T_SendPhase() {
    global T_FakeUrl, AI_Window, AI_Output, AI_Status, AI_BtnRetry, AI_BtnCopy, AI_BtnInsert, AI_Answer
    static hidden := Gui()
    T_FakeUrl := "http://127.0.0.1:" Trim(FileRead(T_Root "\fake-port.txt"))
    FileAppend(KA "`n", T_Root "\keys.txt", "UTF-8")
    T_WriteText(SK_File(), Jxon_Dump(Map("claude", KA), 2))
    IniWrite("anthropic", SettingsFile(), "AI", "Provider")
    IniWrite("claude-test", SettingsFile(), "AI", "Model")
    AI_Window := {Show: (*) => 0, Hide: (*) => 0, Flash: (*) => 0}
    AI_Output := AI_AddAnswerBox(hidden, "w700 h380")
    AI_Status := {Value: ""}
    AI_BtnRetry := {Enabled: 0}, AI_BtnCopy := {Enabled: 0}, AI_BtnInsert := {Enabled: 0}
    ask := () => AI_Ask("Explain δ for Acme.", Map("selection", "no"))

    md := T_Fixture("ai-markdown-sample.md")
    want := T_Fixture("ai-markdown-sample.txt")
    T_Send(ask, md)
    T_Check(AI_Status.Value = "Done." && AI_BtnCopy.Enabled && AI_BtnInsert.Enabled, "send: answered", AI_Status.Value)
    T_Eq(AI_Answer["text"], want, "send: a Markdown answer, as plain text for Copy and Insert")
    T_Eq(AI_Answer["raw"], md, "send: and as Markdown, for Copy as Markdown")
    T_Eq(T_Visible(T_Shown(AI_Output)), T_Visible(want), "send: and formatted in the box")
    T_Check(T_Fmt(AI_Output, "Kronecker delta")["bold"], "send: bold where the AI wrote **")

    AI_Retry()
    T_Wait()
    T_Eq(AI_Answer["text"], want, "send: Retry - the same again")

    T_Send(ask, "")
    T_Check(AI_Status.Value = "Failed." && InStr(AI_Answer["text"], "The reply contained no text.") = 1,
        "send: an empty answer - says so", AI_Answer["text"])
    T_Send(ask, "  `n`n `t `n")
    T_Check(AI_Status.Value = "Failed." && InStr(AI_Answer["text"], "The reply contained no text.") = 1,
        "send: an answer of blank lines - says so", AI_Answer["text"])

    body := "{`"type`":`"error`",`"error`":{`"type`":`"overloaded_error`",`"message`":`"**Overloaded** - # try later`"}}"
    T_Send(ask, body, 529)
    T_Eq(AI_Answer["text"], "The API returned status 529.`n`n" body, "send: an error - shown exactly, ** and all")
    T_Check(AI_Status.Value = "Failed." && !T_Fmt(AI_Output, "Overloaded")["bold"], "send: ... and not formatted")

    big := ""
    Loop 100
        big .= md "`n`n"
    t0 := A_TickCount
    T_Send(ask, big)
    ms := A_TickCount - t0
    T_Info("send: 100 sample answers in one reply, " Round(StrLen(big) / 1024) " KB: asked to shown in " ms " ms")
    T_Check(AI_Status.Value = "Done." && AI_Answer["text"] == MD_Render(big)["text"]
        && T_Visible(T_Shown(AI_Output)) == T_Visible(AI_Answer["text"]), "send: 100 answers' worth, all shown")

    log := FileExist(T_Root "\fake-requests.txt") ? FileRead(T_Root "\fake-requests.txt", "UTF-8") : ""
    StrReplace(log, "`n", , , &lines)
    T_Eq(lines, 6, "send: the fake provider was asked exactly 6 times")
    T_Check(!InStr(log, "none"), "send: each time with the key header")
}

; One AI action, start to finish, the fake provider answering with answer.
T_Send(action, answer, status := 200) {
    T_WriteText(T_Root "\fake-answer.txt", answer)
    T_WriteText(T_Root "\fake-status.txt", status "")
    T_FakeProviders()
    action.Call()
    T_Wait()
}

T_Wait() {
    global AI_Busy
    deadline := A_TickCount + 30000
    while (AI_Busy && A_TickCount < deadline)
        Sleep(20)
    if AI_Busy {
        AI_Abort()
        T_Check(false, "send: no answer within 30 s")
    }
}

; Every provider points at the fake one, and is checked to.
T_FakeProviders() {
    AI_ProvidersReload()
    for id, p in AI_Providers() {
        p["base"] := T_FakeUrl "/" id
        p["url"] := T_FakeUrl "/" id (id = "anthropic" ? "/messages"
                  : id = "gemini" ? "/models/{model}:generateContent" : "/chat/completions")
        p["models_url"] := T_FakeUrl "/" id "/models"
    }
    for id, p in AI_Providers() {
        for k in ["base", "url", "models_url"] {
            if (InStr(p[k], T_FakeUrl "/") != 1) {
                T_Line("ABORT  " id " " k " is not the fake provider: " p[k])
                ExitApp(2)
            }
        }
    }
}

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; Markdown through the converter and into the hidden box.
T_Show(md, width := 0) {
    r := MD_Render(md, width)
    ; As AI_ShowAnswer has it: the box turns down RTF with no characters in it.
    r["ok"] := AI_PutRtf(T_Box, r["rtf"]) || Trim(r["text"], " `t`n") = ""
    r["shown"] := T_Shown(T_Box)
    return r
}

T_Plain(md, want, name) {
    r := T_Show(md)
    T_Check(r["ok"] && r["text"] == want && T_Visible(r["shown"]) == T_Visible(want), name,
        "ok " r["ok"] " | got: " T_Esc(r["text"]) " | expected: " T_Esc(want) " | shown: " T_Esc(r["shown"]))
}

; What a rich edit control shows, a paragraph to a line, each line ending in
; `n (the box always ends with a paragraph mark of its own, and so with `n).
; raw: as it is held, with the marks a table is made of, CR for a paragraph -
; the text the control's character positions count.
T_Shown(box, raw := false) {
    gl := Buffer(8, 0)
    NumPut("UInt", 8, "UInt", 1200, gl)                 ; GTL_NUMCHARS, Unicode
    len := SendMessage(0x45F, gl.Ptr, 0, box)           ; EM_GETTEXTLENGTHEX
    buf := Buffer((len * 2 + 64) * 2, 0)
    gt := Buffer(A_PtrSize = 8 ? 32 : 20, 0)
    NumPut("UInt", buf.Size, "UInt", raw ? 4 : 0, "UInt", 1200, gt)   ; GT_RAWTEXT or GT_DEFAULT
    SendMessage(0x45E, gt.Ptr, buf.Ptr, box)            ; EM_GETTEXTEX
    if raw
        return StrGet(buf, "UTF-16")
    s := StrReplace(StrGet(buf, "UTF-16"), "`r", "`n")
    return (s = "") ? "" : s "`n"
}

; Text with the things the box and the plain text lay out differently taken
; out - spaces, tabs, line breaks, a table's | - and sub- and superscript
; digits read as plain ones. What is left must be the same.
T_Visible(s) {
    static from := "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ⁿⁱₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ"
    static to   := "0123456789+-=()0123456789+-=()niaehijklmnoprstuvx"
    s := RegExReplace(s, "[\s|\x0B]")
    out := ""
    Loop Parse s
        out .= (n := InStr(from, A_LoopField, true)) ? SubStr(to, n, 1) : A_LoopField
    return out
}

; The character format of a piece of the box's text: the nth needle, or the
; first needle after `after`.
T_Fmt(box, needle, nth := 1, after := "") {
    text := T_Shown(box, true)
    start := after = "" ? 1 : InStr(text, after, true) + StrLen(after)
    at := InStr(text, needle, true, start, nth)
    f := Map("bold", 0, "italic", 0, "strike", 0, "sub", 0, "sup", 0, "size", 0, "face", "", "color", -1, "found", at > 0)
    if !at
        return f
    range := Buffer(8, 0)
    NumPut("Int", at - 1, "Int", at - 1 + StrLen(needle), range)
    SendMessage(0x437, 0, range.Ptr, box)               ; EM_EXSETSEL
    cf := Buffer(116, 0)
    NumPut("UInt", 116, "UInt", 0xF003000F | 0x40000000, cf)  ; all the masks we read
    SendMessage(0x43A, 1, cf.Ptr, box)                  ; EM_GETCHARFORMAT, SCF_SELECTION
    fx := NumGet(cf, 8, "UInt")
    f["bold"] := !!(fx & 1), f["italic"] := !!(fx & 2), f["strike"] := !!(fx & 8)
    f["sub"] := !!(fx & 0x10000), f["sup"] := !!(fx & 0x20000)
    f["size"] := NumGet(cf, 12, "Int") / 20
    f["color"] := (fx & 0x40000000) ? -1 : NumGet(cf, 20, "UInt")
    f["face"] := StrGet(cf.Ptr + 26, 32, "UTF-16")
    SendMessage(0xB1, 0, 0, box)
    return f
}

T_Desc(f) => (f["found"] ? "" : "NOT FOUND ") "bold " f["bold"] " italic " f["italic"] " strike " f["strike"]
    . " sub " f["sub"] " sup " f["sup"] " " f["size"] "pt " f["face"] " colour " Format("{:06X}", f["color"] & 0xFFFFFF)

; A paragraph's indents, in twips: where its first line starts, where the rest do.
T_Indent(box, needle) {
    text := T_Shown(box, true)
    at := InStr(text, needle, true)
    range := Buffer(8, 0)
    NumPut("Int", at - 1, "Int", at - 1, range)
    SendMessage(0x437, 0, range.Ptr, box)
    pf := Buffer(188, 0)
    NumPut("UInt", 188, "UInt", 0x1 | 0x4, pf)          ; PFM_STARTINDENT | PFM_OFFSET
    SendMessage(0x43D, 0, pf.Ptr, box)                  ; EM_GETPARAFORMAT
    first := NumGet(pf, 12, "Int")
    return Map("first", first, "rest", first + NumGet(pf, 20, "Int"))
}

T_Balanced(rtf) {
    rtf := StrReplace(StrReplace(StrReplace(rtf, "\\"), "\{"), "\}")
    StrReplace(rtf, "{", , , &open)
    StrReplace(rtf, "}", , , &close)
    return open = close
}

T_Fixture(name) {
    SplitPath(A_LineFile, , &dir)
    s := FileRead(dir "\" name, "UTF-8")
    return RTrim(StrReplace(s, "`r`n", "`n"), "`n")
}

T_Repeat(s, n) {
    out := ""
    Loop n
        out .= s
    return out
}

T_LineCount(s) {
    StrReplace(s, "`n", , , &n)
    return n + 1
}

; A small random number generator with a fixed start, so a failure repeats.
T_Next(&seed) {
    seed := Mod(seed * 1103515245 + 12345, 2147483648)
    return seed >> 8
}

; Markdown with § for each backtick, which AutoHotkey strings make hard to read.
T_B(s) => StrReplace(s, "§", "``")

T_Esc(s) => StrReplace(StrReplace(s, "`n", "\n"), "`t", "\t")

T_WriteText(path, text) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
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

T_Eq(actual, expected, name) {
    T_Check(actual == expected, name, "got: " T_Esc(actual "") " | expected: " T_Esc(expected ""))
}

T_Info(s) => T_Line("INFO  " s)
