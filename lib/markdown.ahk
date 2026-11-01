#Requires AutoHotkey v2.0
; ===========================================================================
; lib/markdown.ahk — an AI answer's Markdown, made readable.
;
; Models answer in Markdown: # headings, **bold**, - bullets, `code`. The AI
; window shows answers in a rich edit control, which takes RTF, so this turns
; the Markdown into RTF - and, in the same pass, into plain text with the
; marks taken out, which is what Copy and Insert hand on.
;
; Written here rather than borrowed: there is no maintained Markdown library
; for AutoHotkey, and the way round that - a browser control running a
; JavaScript one - costs a runtime and two DLLs per bitness for one window.
; So this is deliberately a small subset, what chat models actually write:
;
;   # headings (1-6)           **bold**  *italic*  ***both***  ~~struck~~
;   - * + bullets, nested      `code`    ```fenced code blocks```
;   1. and 1) numbered lists   [text](url)  <sub>2</sub>  <sup>2</sup>  <br>
;   > quotes, --- rules        | GFM | tables |
;
; Anything else is shown as it was written, never dropped: an unclosed **,
; a # without a space, a table without its --- row. Every character of the
; answer is escaped on its way into the RTF, so nothing in an answer can
; become an RTF command.
;
; Each line of the answer stays one line - in the window and in the plain
; text - except the ``` lines around code and a table's --- row, which go,
; and a --- rule, which becomes the blank line around it.
; ===========================================================================

; Markdown in; a Map with "rtf" and "text" out. tableWidth is the room a
; table may fill, in twips (1/1440 inch); 0 means 6.5 inches.
MD_Render(md, tableWidth := 0) {
    static sizes := [32, 28, 24, 22, 22, 22]                       ; # to ######, in half-points
    static bullets := [Chr(0x2022), Chr(0x25E6), Chr(0x25AA)]      ; • ◦ ▪, by level
    ; A rule is an underlined tab out to the edge, in grey: the control does
    ; not draw a paragraph's border, and an underline is a line in Word too.
    rule := "\pard\sa120\tx" (tableWidth > 0 ? tableWidth : 9360) "{\cf1\ul\tab}\par"
    lines := MD_Lines(md)
    paras := []          ; one RTF paragraph (or table row) per entry
    plain := []          ; the plain text, a line per entry
    lists := []          ; the indent of each list level open now
    fence := ""          ; the closing pattern of the code block we are in
    codeIndent := 0, codeLi := 0
    skipBlank := false   ; a rule takes the blank line after it

    i := 0
    while (++i <= lines.Length) {
        line := lines[i]

        if (fence != "") {
            if RegExMatch(line, "^\s*" fence "\s*$") {
                fence := ""
                continue
            }
            ; The block's own indent comes off; anything deeper is the code's.
            RegExMatch(line, "^ {0," codeIndent "}", &lead)
            code := SubStr(line, lead.Len + 1)
            paras.Push("\pard\li" codeLi "{\f1\fs20 " MD_Esc(code) "}\par")
            plain.Push(code)
            continue
        }

        if (Trim(line, " `t") = "") {
            if !skipBlank {
                paras.Push("\pard\par")
                plain.Push("")
            }
            skipBlank := false
            continue
        }
        skipBlank := false

        RegExMatch(line, "^[ `t]*", &ws)
        indent := MD_IndentWidth(ws[0])
        text := Trim(line, " `t")

        ; A list ends at the first line back at the margin that isn't an item.
        if (indent = 0 && !RegExMatch(text, "^(?:[-*+]|\d{1,9}[.)])\s"))
            lists := []

        ; ``` or ~~~ opens a code block, closed by a run at least as long.
        if RegExMatch(text, "^(``{3,}|~{3,})(.*)$", &f)
                && !(SubStr(f[1], 1, 1) = "``" && InStr(f[2], "``")) {
            fence := SubStr(f[1], 1, 1) "{" StrLen(f[1]) ",}"
            codeIndent := indent
            codeLi := (lists.Length && indent > 0) ? MD_ListLi(MD_ContinuedLevel(lists, indent)) : 360
            continue
        }

        ; ---, *** or ___ alone: a rule, which takes the place of the blank
        ; line before it and swallows the one after.
        if RegExMatch(text, "^([-*_])(?:\s*\1){2,}$") {
            if (paras.Length && paras[paras.Length] = "\pard\par")
                paras[paras.Length] := rule
            else {
                paras.Push(rule)
                plain.Push("")
            }
            skipBlank := true
            continue
        }

        if RegExMatch(text, "^(#{1,6})\s+(.*?)(?:\s+#+)?$", &h) {
            p := ""
            r := MD_Inline(h[2], &p)
            paras.Push("\pard\sb" (StrLen(h[1]) <= 2 ? 160 : 100) "\sa40\keepn{\b\fs"
                     . sizes[StrLen(h[1])] " " r "}\par")
            plain.Push(p)
            continue
        }

        ; A table: a row of cells, then a row of --- under each of them.
        if (InStr(text, "|") && i < lines.Length) {
            head := MD_Cells(text)
            delim := Trim(lines[i + 1], " `t")
            if (InStr(delim, "|") && RegExMatch(delim, "^\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?$")
                    && MD_Cells(delim).Length = head.Length) {
                rows := [head]
                i += 1
                while (i < lines.Length && Trim(lines[i + 1], " `t") != "" && InStr(lines[i + 1], "|")) {
                    i += 1
                    rows.Push(MD_Cells(Trim(lines[i], " `t")))
                }
                MD_Table(rows, MD_Cells(delim), tableWidth, paras, plain)
                lists := []
                continue
            }
        }

        if RegExMatch(text, "^((?:>\s?)+)(.*)$", &q) {
            StrReplace(q[1], ">", , , &depth)
            p := ""
            r := MD_Inline(q[2], &p)
            paras.Push("\pard\li" (360 * depth) "{\cf1 " r "}\par")
            plain.Push(p)
            continue
        }

        if RegExMatch(text, "^(?:([-*+])|(\d{1,9}[.)]))\s+(.*)$", &mk) {
            level := MD_ListLevel(lists, indent)
            mark := (mk[1] != "") ? bullets[Min(level + 1, 3)] : mk[2]
            item := mk[3]
            if RegExMatch(item, "^\[([ xX])\]\s+(.*)$", &task)          ; - [ ] and - [x]
                item := (task[1] = " " ? Chr(0x2610) : Chr(0x2611)) " " task[2]
            p := ""
            r := MD_Inline(item, &p)
            at := MD_ListLi(level)
            paras.Push("\pard\li" at "\fi-300\tx" at " " MD_Esc(mark) "\tab " r "\par")
            plain.Push(MD_Spaces(2 * level) mark " " p)
            continue
        }

        ; More of a list item: indented under it, without a marker.
        if (lists.Length && indent > 0) {
            level := MD_ContinuedLevel(lists, indent)
            p := ""
            r := MD_Inline(text, &p)
            paras.Push("\pard\li" MD_ListLi(level) " " r "\par")
            plain.Push(MD_Spaces(2 * level + 2) p)
            continue
        }

        p := ""
        r := MD_Inline(text, &p)
        paras.Push("\pard " r "\par")
        plain.Push(p)
    }

    ; The control ends with a paragraph of its own; a closing \par would
    ; add an empty line under the answer.
    if (paras.Length && SubStr(paras[paras.Length], -4) = "\par")
        paras[paras.Length] := SubStr(paras[paras.Length], 1, -4)

    rtf := MD_RtfHead()
    for para in paras
        rtf .= para "`r`n"
    out := ""
    for n, l in plain
        out .= (n > 1 ? "`n" : "") l
    return Map("rtf", rtf "}", "text", out)
}

; Text that is not Markdown - an error, say - shown as it is, line by line.
MD_RenderPlain(s) {
    s := StrReplace(StrReplace(s, "`r`n", "`n"), "`r", "`n")
    rtf := MD_RtfHead()
    for n, line in StrSplit(s, "`n")
        rtf .= (n > 1 ? "\par`r`n" : "") "\pard " MD_Esc(line)
    return Map("rtf", rtf "}", "text", s)
}

; The answer's font is the AI window's own, Calibri 11pt (22 half-points).
; Code is Consolas a point smaller, which looks the same size beside it.
; Colour 1 is the grey of quotes.
MD_RtfHead() {
    return "{\rtf1\ansi\ansicpg1252\deff0\uc1"
         . "{\fonttbl{\f0\fswiss\fcharset0 Calibri;}{\f1\fmodern\fcharset0 Consolas;}}"
         . "{\colortbl `;\red96\green96\blue96;}"
         . "\f0\fs22 "
}

; The answer's lines, without the blank ones at either end.
MD_Lines(md) {
    lines := StrSplit(StrReplace(StrReplace(md, "`r`n", "`n"), "`r", "`n"), "`n")
    while (lines.Length && Trim(lines[lines.Length], " `t") = "")
        lines.Pop()
    while (lines.Length && Trim(lines[1], " `t") = "")
        lines.RemoveAt(1)
    return lines
}

MD_IndentWidth(ws) {
    StrReplace(ws, "`t", , , &tabs)
    return StrLen(ws) + 3 * tabs
}

MD_Spaces(n) {
    out := ""
    Loop n
        out .= " "
    return out
}

; How far in a list level's text starts, in twips. The marker hangs 300
; twips to the left of it, which fits a bullet or a number up to 99.
MD_ListLi(level) => 360 * (level + 1)

; The list level of an item indented this far. lists holds the indent of
; each level open now; a deeper indent opens a level, a shallower one closes
; the levels it is outside of.
MD_ListLevel(lists, indent) {
    while (lists.Length && indent < lists[lists.Length])
        lists.Pop()
    if (!lists.Length || indent > lists[lists.Length])
        lists.Push(indent)
    return lists.Length - 1
}

; The level a marker-less indented line belongs to: the deepest one it is
; indented past.
MD_ContinuedLevel(lists, indent) {
    level := 0
    for n, at in lists {
        if (at < indent)
            level := n - 1
    }
    return level
}

; A table row's cells. \| is a pipe inside a cell, not a border.
MD_Cells(row) {
    static PH := Chr(0xE000)
    row := StrReplace(row, "\|", PH)
    if (SubStr(row, 1, 1) = "|")
        row := SubStr(row, 2)
    if (SubStr(row, -1) = "|")
        row := SubStr(row, 1, -1)
    cells := StrSplit(row, "|")
    for n, c in cells
        cells[n] := StrReplace(Trim(c, " `t"), PH, "\|")
    return cells
}

; A table as RTF rows, the first in bold, each column as wide as its longest
; cell asks; and as plain text, cells between " | ". (Not tabs: Insert types
; the text, and a typed Tab moves on to the next field.)
MD_Table(rows, delim, width, paras, plain) {
    cols := rows[1].Length
    aligns := [], chars := [], cells := []
    for d in delim
        aligns.Push(RegExMatch(d, "^:-+:$") ? "\qc" : RegExMatch(d, "-:$") ? "\qr" : "")
    Loop cols
        chars.Push(3)
    for row in rows {
        r := [], t := []
        Loop cols {
            p := ""
            r.Push(MD_Inline(A_Index <= row.Length ? row[A_Index] : "", &p))
            t.Push(p)
            chars[A_Index] := Max(chars[A_Index], Min(StrLen(p), 40))
        }
        cells.Push([r, t])
    }

    ; About 115 twips a character at 11pt, plus each cell's padding. A table
    ; is shrunk to fit the room it has, never stretched.
    want := 0
    for n in chars
        want += n * 115 + 240
    room := width > 0 ? width : 9360
    scale := want > room ? room / want : 1
    edges := "", x := 0
    for n in chars {
        x += Round((n * 115 + 240) * scale)
        edges .= "\clbrdrt\brdrs\brdrw10\clbrdrl\brdrs\brdrw10"
               . "\clbrdrb\brdrs\brdrw10\clbrdrr\brdrs\brdrw10\cellx" x
    }

    for n, row in cells {
        rtf := "\trowd\trgaph100\trleft0" edges
        Loop cols
            rtf .= "\pard\intbl" aligns[A_Index] " " (n = 1 ? "{\b " row[1][A_Index] "}" : row[1][A_Index]) "\cell"
        paras.Push(rtf "\row")
        line := ""
        Loop cols
            line .= (A_Index > 1 ? " | " : "") row[2][A_Index]
        plain.Push(line)
    }
}

; ---------------------------------------------------------------------------
; Inline marks. Returns the RTF of s and adds its plain text to plain.
;
; One pattern finds the next mark of any kind; the text before it is plain,
; and the mark's own text is worked through the same way, so marks nest:
; **bold with `code` in it**. A mark needs its closing half on the same line,
; or it is no mark: "**" left open stays "**".
;
; The closing half is looked for at most 1,000 characters on. Without that
; limit, a long line full of open marks - "a *b *c *d ..." - is searched to
; its end from every one of them, which takes minutes at 100 KB.
; ---------------------------------------------------------------------------
MD_Inline(s, &plain) {
    static re := "(*UCP)(?|"
        . "\\([!-/:-@\[-``{-~])(*MARK:esc)"                                ; \* \_ \# ...
        . "|(``+)(?!``)(.{1,1000}?)(?<!``)\1(?!``)(*MARK:code)"             ; `code`
        . "|\*\*\*(?=\S)(.{1,1000}?)(?<=\S)\*\*\*(*MARK:bi)"                ; ***both***
        . "|\*\*(?=\S)(.{1,1000}?)(?<=\S)\*\*(*MARK:b)"                     ; **bold**
        . "|(?<!\w)__(?=\S)(.{1,1000}?)(?<=\S)__(?!\w)(*MARK:b)"            ; __bold__
        . "|\*(?=[^\s*])(.{1,1000}?)(?<=[^\s*])\*(?!\*)(*MARK:i)"           ; *italic*
        . "|(?<!\w)_(?=[^\s_])(.{1,1000}?)(?<=[^\s_])_(?!\w)(*MARK:i)"      ; _italic_, not snake_case
        . "|~~(?=\S)(.{1,1000}?)(?<=\S)~~(*MARK:s)"                         ; ~~struck~~
        . "|(!?)\[([^\]]{1,1000})\]\(\s*<?([^\s()<>]{1,2000}(?:\([^\s()]{0,200}\)[^\s()<>]{0,200})?)>?(?:\s+`"[^`"]{0,200}`")?\s*\)(*MARK:link)"
        . "|(?i:<(sub|sup)>(.{0,1000}?)</\1>)(*MARK:tag)"                   ; <sub>2</sub> <sup>2</sup>
        . "|(?i:<br\s*/?>)(*MARK:br)"
        . "|<(https?://[^\s<>]{1,2000})>(*MARK:url)"
        . ")"
    rtf := "", pos := 1
    while (at := RegExMatch(s, re, &m, pos)) {
        if (at > pos) {
            chunk := SubStr(s, pos, at - pos)
            rtf .= MD_Esc(chunk), plain .= chunk
        }
        switch m.Mark {
            case "esc":
                rtf .= MD_Esc(m[1]), plain .= m[1]
            case "code":
                ; One space either side is padding: `` `x` `` shows `x`.
                c := m[2]
                if (StrLen(c) > 2 && SubStr(c, 1, 1) = " " && SubStr(c, -1) = " ")
                    c := SubStr(c, 2, -1)
                rtf .= "{\f1\fs20 " MD_Esc(c) "}", plain .= c
            case "bi":
                rtf .= "{\b\i " MD_Inline(m[1], &plain) "}"
            case "b":
                rtf .= "{\b " MD_Inline(m[1], &plain) "}"
            case "i":
                rtf .= "{\i " MD_Inline(m[1], &plain) "}"
            case "s":
                rtf .= "{\strike " MD_Inline(m[1], &plain) "}"
            case "link":
                ; The text, then where it goes - unless that is the text.
                rtf .= MD_Inline(m[2], &plain)
                if (m[3] != m[2])
                    rtf .= " (" MD_Esc(m[3]) ")", plain .= " (" m[3] ")"
            case "tag":
                p := ""
                sup := (m[1] = "sup")
                rtf .= "{" (sup ? "\super " : "\sub ") MD_Inline(m[2], &p) "}"
                plain .= MD_Script(p, sup)
            case "br":
                rtf .= "\line ", plain .= "`n"
            case "url":
                rtf .= MD_Esc(m[1]), plain .= m[1]
        }
        pos := at + m.Len
    }
    if (pos <= StrLen(s)) {
        chunk := SubStr(s, pos)
        rtf .= MD_Esc(chunk), plain .= chunk
    }
    return rtf
}

; Sub- and superscript in plain text: the Unicode characters where every
; one has one (CO₂, m²), else the text as it is - half of one and half of the
; other would read worse.
MD_Script(s, sup) {
    static from := "0123456789+-=()"
    static supTo := "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾", subTo := "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎"
    static supMore := "ni", supMoreTo := "ⁿⁱ"
    static subMore := "aehijklmnoprstuvx", subMoreTo := "ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ"
    out := ""
    Loop Parse s {
        if (n := InStr(from, A_LoopField, true))
            out .= SubStr(sup ? supTo : subTo, n, 1)
        else if (n := InStr(sup ? supMore : subMore, A_LoopField, true))
            out .= SubStr(sup ? supMoreTo : subMoreTo, n, 1)
        else
            return s
    }
    return out
}

; Text made safe for RTF: \ { } escaped, a tab as \tab, everything outside
; ASCII as \uN? - the ? is what a reader without Unicode would show, and
; \uc1 says to skip it. Other control characters are dropped. Plain ASCII
; text, the common case, comes back untouched.
MD_Esc(s) {
    static special := "[^\x20-\x5B\x5D-\x7A\x7C\x7E]+"
    if !RegExMatch(s, special, &m)
        return s
    out := "", pos := 1
    loop {
        out .= SubStr(s, pos, m.Pos - pos)
        Loop Parse m[0] {
            c := Ord(A_LoopField)
            if (c = 0x5C || c = 0x7B || c = 0x7D)
                out .= "\" A_LoopField
            else if (c = 9)
                out .= "\tab "
            else if (c < 32 || c = 127)
                continue
            else if (c > 0xFFFF)                ; a surrogate pair, read as one character
                out .= "\u" (0xD800 + ((c - 0x10000) >> 10) - 0x10000) "?"
                     . "\u" (0xDC00 + ((c - 0x10000) & 0x3FF) - 0x10000) "?"
            else
                out .= "\u" (c > 0x7FFF ? c - 0x10000 : c) "?"
        }
        pos := m.Pos + m.Len
    } until !RegExMatch(s, special, &m, pos)
    return out SubStr(s, pos)
}
