; =====================================================================
; TEST SNIPPET -- step 4b/4c of the plan in end-gcode-p2s.gcode:
; PUSHER HEIGHT LADDER ON AN EMPTY PLATE.
;
; Tiny 1-layer print, nothing else on the plate. The door opens, the
; toolhead does ONE central sweep at the FIXED height on the line marked
; <<< TEST_Z >>>, then parks and the door closes.
;
; Run it once per height, starting HIGH and coming down:
;   Z20 -> Z12 -> Z8 -> Z5 -> (Z3 only if Z5 was silent)
; Stop at the first height where you hear or see the pusher / toolhead
; touch the plate, the bed clips, or anything else. The LAST SILENT
; height is SWEEP_MIN. Never go below Z2.
;
; Do NOT use {max_layer_z} or G91 Z-10 in this test: on a 0.2 mm print
; that would command Z-9.8 (clamped to 0 = toolhead on the plate).
;
; 4c: once a height is silent, set RAKE_ENABLE below to run the full
; rake path at that height to check the bed clips / door frame / rear
; park -- still on an empty plate.
;
; Results log:
;   (date)  Z20: silent/contact  Z12: __  Z8: __  Z5: __  -> SWEEP_MIN = __
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

; --- door open (T1) ---
M104 S2
G1 Z243 F3000
M400
G1 Z255 F3000
M400
G4 S5
M400
G1 Z243 F3000
G4 S12

; --- height under test ---
G1 Z20 F3000           ; <<< TEST_Z >>>  change ONLY this number per run
M400

; --- one central sweep, slow ---
G1 X125 F3000
G1 Y250 F3000
G1 Y0   F3000
M400

; --- 4c: full rake path. Delete the leading ';' on each line to enable.
; G1 Y250 F3000
; G1 X220 F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X190 F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X160 F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X130 F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X100 F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X70  F3000
; G1 Y0   F3000
; G1 Y250 F3000
; G1 X30  F3000
; G1 Y0   F3000
; M400

; --- lift and park ---
G91
G1 Z30 F3000
G90
M400
G1 X65 Y245 F12000
G1 Y265 F3000
M400

; --- door close (T3) ---
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
