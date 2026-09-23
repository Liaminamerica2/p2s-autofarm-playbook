; =====================================================================
; TEST SNIPPET -- step 3 of the plan in end-gcode-p2s.gcode: DOOR ONLY.
; Opens the door, waits 30 s, closes it. No cooldown wait, no sweep.
; Tiny 1-layer print. Record seconds from press to fully open and from
; press to fully closed -> DOOR_OPEN_WAIT.
;
; 3b: to test whether the sentinels alone drive the board, comment out
; every G1 Z line below and rerun. (Vendor says the limit switch is
; disabled while Digital mode is connected, so 3b should still work.)
;
; Results log:
;   (date)  open: __ s   close: __ s   3b sentinel-only: worked / not
; =====================================================================

M17

M106 S0
M106 P3 S0
M106 P10 S0
M145 P1
M106 P2 S255
M140 S0
M104 S0
G4 S5

; --- T1: door open ---
M104 S2
G1 Z243 F3000
M400
G1 Z255 F3000
M400
G4 S5
M400
G1 Z243 F3000

G4 S30

; --- T3: door close ---
M104 S5
G1 Z255 F3000
M400
G4 S5
M400
G1 Z220 F3000

M106 P2 S0
M145 P0
M400
M18
