; =====================================================================
; P2S / FarmBoard START G-code injection
; Paste into Bambuddy: Settings -> Workflow -> G-code Injection -> P2S
; (or the slicer's Machine Start G-code, ahead of the stock start block)
;
; Hand-written from the mechanism documented in GCODE-HOWTO.md section 3.
; Purpose: put the FarmBoard in a known state at the start of every job,
; independent of whatever state the ejection cycle left it in.
;
; Keeps BOTH the MQTT sentinel (M104 Sn) and the Z-axis tap gestures, so
; the cycle still works if MQTT / Digital mode drops mid-farm.
;
; NO leading G28: Bambuddy's injector (see GCODE-HOWTO.md section 10)
; inserts this snippet immediately before the `; MACHINE_START_GCODE_END`
; marker, i.e. AFTER the printer's own homing/bed-heat/nozzle-prime has
; already run. Re-homing here would be redundant and risks smearing the
; prime line. If you paste this into a pipeline that injects BEFORE that
; marker instead, add `G28` back as the first line.
;
; Verified against the stock P2S start G-code (2026/05/18 template):
;   * `M211 X0 Y0 Z0 ;turn off soft endstop` runs twice before the
;     marker, so soft endstops are OFF here; Z255 is inside the 256 mm
;     travel anyway (printable_height = 256).
;   * The nozzle is at first-layer temperature and 1 mm off the plate
;     after the load line; the first move below (Z255) drops the bed to
;     the bottom, which is where the FarmBoard's switch is.
; Gestures match the vendor's mechanical-mode table: four quick taps =
; "Emergency reset: homes bender, returns to idle"; long press (3-6 s) +
; short tap = "Close door, print begins".
; =====================================================================

; --- MQTT sentinel: RESET (arm MQTT auto-trigger) ---
M104 S1                ; RESET sentinel (nozzle_target_temper=1)

; --- RESET gesture: 4 quick taps (within ~3s) ---
G1 Z255 F6000     ; Tap 1 - press
G4 P150
G1 Z243 F3000     ; Release
G4 P250
G1 Z255 F3000     ; Tap 2 - press
G4 P150
G1 Z243 F3000     ; Release
G4 P250
G1 Z255 F3000     ; Tap 3 - press
G4 P150
G1 Z243 F3000     ; Release
G4 P250
G1 Z255 F3000     ; Tap 4 - press
G4 P150
G1 Z243 F3000     ; Release

G4 P1000          ; Wait for reset (source comment claims ~7s; verify on
                   ; your board and pad this if it doesn't finish in 1s)

; --- TRIGGER 0 gesture: long tap (~3.5s) + short tap ---
G1 Z255 F3000
M400
G4 P3500
G1 Z243 F3000     ; Release switch
G4 P500

G1 Z255 F3000     ; Short tap - quick press
G4 P200
G1 Z243 F3000     ; Release switch
; NOTE: source file released to Z20 here, not Z243/Z220 like every other
; release in the cycle. Changed to Z243 (the cycle's normal "released,
; holding position" height) -- confirm this is correct for your hardware
; before trusting it; Z20 may have been intentional on the vendor's rig.
