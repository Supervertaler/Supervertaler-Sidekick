; tools/window-placement-test.ahk — checks lib\placement.ahk, which decides
; where the main window opens, against made-up monitor layouts. Shows no
; window and does not start Sidekick.
;
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tools\window-placement-test.ahk
;
; Prints PASS / FAIL lines; exit code 0 when everything passed.
#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off
#Warn All, StdOut
#Include "..\lib\placement.ahk"

global T_Fails := 0

; A made-up layout: a 1920x1200 monitor to the left of a 2560x1440 primary,
; each with a 48px taskbar at the bottom.
LEFT  := [-1920, 240, 0, 1440, -1920, 240, 0, 1392]
MAIN  := [0, 0, 2560, 1440, 0, 0, 2560, 1392]
BOTH  := [MAIN, LEFT]
W := 1278, H := 898

Check("saved on the left monitor, pointer on the main one: moves across, same offset",
  MW_PlaceOnPointerMonitor(-1597, 734 - 240 + 240, W, H, 1000, 500, BOTH), 323, 494)
Check("saved on the main monitor, pointer on the left one: moves across, pulled inside",
  MW_PlaceOnPointerMonitor(1200, 100, W, H, -500, 600, BOTH), -1278, 340)
Check("saved on the monitor the pointer is on: left exactly where it was",
  MW_PlaceOnPointerMonitor(-1597, 300, W, H, -10, 900, BOTH), -1597, 300)
Check("partly off the edge of the pointer's monitor, as the user left it: not touched",
  MW_PlaceOnPointerMonitor(1500, 700, W, H, 100, 100, BOTH), 1500, 700)
Check("pointer on the taskbar still counts as that monitor",
  MW_PlaceOnPointerMonitor(-1597, 300, W, H, 1200, 1430, BOTH), 323, 60)
Check("no saved position: centred on the pointer's monitor",
  MW_PlaceOnPointerMonitor("", "", W, H, -500, 600, BOTH), -1599, 367)
Check("saved on a monitor that is gone: centred on the pointer's monitor",
  MW_PlaceOnPointerMonitor(-1597, 734, W, H, 1000, 500, [MAIN]), 641, 247)
Check("window bigger than the pointer's monitor: top-left corner stays reachable",
  MW_PlaceOnPointerMonitor(100, 100, 2400, 1300, -500, 600, BOTH), -1920, 240)
Check("pointer on no monitor, saved position still on one: kept",
  MW_PlaceOnPointerMonitor(100, 100, W, H, 9000, 9000, BOTH), 100, 100)
Check("pointer on no monitor, nothing saved: left to Windows",
  MW_PlaceOnPointerMonitor("", "", W, H, 9000, 9000, BOTH), "", "")
Check("no monitors reported at all: left to Windows, no error",
  MW_PlaceOnPointerMonitor(100, 100, W, H, 10, 10, []), "", "")

; The real screen: every monitor found, with its work area inside it.
real := MW_Monitors()
ok := real.Length = MonitorGetCount() && real.Length >= 1
for mon in real
    ok := ok && mon.Length = 8 && mon[5] >= mon[1] && mon[6] >= mon[2] && mon[7] <= mon[3] && mon[8] <= mon[4]
Say((ok ? "PASS  " : "FAIL  ") "this computer's monitors are all listed (" real.Length ")")
if !ok
    T_Fails++

Say(T_Fails ? T_Fails " failed" : "all passed")
ExitApp(T_Fails ? 1 : 0)

Check(name, got, wantX, wantY) {
    global T_Fails
    if (got[1] = wantX && got[2] = wantY && (got[1] = "") = (wantX = "")) {
        Say("PASS  " name)
        return
    }
    T_Fails++
    Say("FAIL  " name ": got " got[1] ", " got[2] " - wanted " wantX ", " wantY)
}

Say(line) {
    FileAppend(line "`n", "*")
}
