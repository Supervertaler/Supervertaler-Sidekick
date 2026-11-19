; ---------------------------------------------------------------------------
; Where the main window opens: on the monitor the mouse pointer is on.
;
; The window used to reopen exactly where it was last closed, which on two
; monitors meant it could come up on the one you were not looking at. It still
; remembers its size, and its place within a monitor, but the monitor is now
; always the pointer's.
;
; MW_PlaceOnPointerMonitor is arithmetic only - no window, no screen - so that
; tools\window-placement-test.ahk can run it against made-up monitor layouts.
; ---------------------------------------------------------------------------

; x, y        the saved top-left corner, or "" if none was saved
; w, h        the window's size
; px, py      the pointer
; monitors    one entry per monitor: [left, top, right, bottom,
;             workLeft, workTop, workRight, workBottom]
; All in raw screen pixels. Returns [x, y]; both are "" only when there was no
; saved position and the pointer is on no monitor, leaving the caller to let
; Windows choose.
MW_PlaceOnPointerMonitor(x, y, w, h, px, py, monitors) {
    target := MW_MonitorAt(px, py, monitors)
    saved  := (x != "" && y != "")
    source := saved ? MW_MonitorAt(x + w // 2, y + h // 2, monitors) : 0

    if !target {
        ; Should not happen; if it does, keep a saved position that is still
        ; on a screen and drop one that is not.
        return source ? [x, y] : ["", ""]
    }
    if (source = target)
        return [x, y]                   ; already here: leave it where it was put

    t := monitors[target]
    if source {
        ; The same distance from the corner of this monitor as it was from
        ; the corner of that one.
        s  := monitors[source]
        nx := t[5] + (x - s[5])
        ny := t[6] + (y - s[6])
    } else {
        ; No saved position, or one on a monitor that is no longer attached.
        nx := t[5] + (t[7] - t[5] - w) // 2
        ny := t[6] + (t[8] - t[6] - h) // 2
    }

    ; Wholly inside the work area where it fits; where it does not (a window
    ; sized on a bigger monitor), the top-left corner wins, so the title bar
    ; can always be reached.
    nx := Max(t[5], Min(nx, t[7] - w))
    ny := Max(t[6], Min(ny, t[8] - h))
    return [nx, ny]
}

; The index of the monitor a point is on, or 0.
MW_MonitorAt(px, py, monitors) {
    for i, m in monitors {
        if (px >= m[1] && px < m[3] && py >= m[2] && py < m[4])
            return i
    }
    return 0
}

; The attached monitors, in the shape MW_PlaceOnPointerMonitor takes.
MW_Monitors() {
    list := []
    Loop MonitorGetCount() {
        try {
            MonitorGet(A_Index, &l, &t, &r, &b)
            MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
            list.Push([l, t, r, b, wl, wt, wr, wb])
        }
    }
    return list
}
