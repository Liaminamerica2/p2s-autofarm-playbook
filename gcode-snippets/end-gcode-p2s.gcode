; =====================================================================
;
;   DO NOT RUN THIS FILE AS-IS. IT IS NOT FINISHED / TESTED.
;   Work through the steps below in order. Each one changes exactly ONE
;   thing, has a pass condition, and fills in one parameter of this
;   file. Every step is attended, hand near the power switch, door
;   closed at start, until step 8 says otherwise. Log every result in
;   GCODE-HOWTO.md section 11.
;
;   Rules for every test:
;     - tiny 1-layer print unless the step says "real part"
;     - one end snippet per test, pasted into Bambuddy in place of this
;       file; the start snippet stays as it is (already proven)
;     - confirm injection each time: start taps seen after homing, and
;       "G-code injected for model P2S" in the Bambuddy log. No taps =
;       the un-injected file printed; fix that before reading anything
;       else into the result.
;
;   1. COOLING: what does M190 S do, and how long does it take.    RIGHT NOW WHEN RUNNING THIS THE DOOR OPENS AT 40°C IT SHOULD OPEN BELLOW 30 
;      Snippet: end-gcode-test-m190.gcode (running / next).
;      Record: bed temp + clock time at each fan+jog signal and when
;      Finished appears; room temperature.
;      Pass: Finished within ~2 C of the target, in a time you can live
;      with per print. Sets RELEASE_TEMP and RELEASE_REPEATS.
;      If it never reaches target (undershoot / warm room): raise
;      RELEASE_TEMP by 2-3 C and rerun.
;      If filter-mode (M145 P1 + P2) is too slow: rerun once with the
;      commented M145 P0 + M106 P3 S255 lines and note the smell. Pick.
;
;   2. PLATE RELEASE: does the engineering plate let go on its own at   EHHH IT KIND OF DOES BUT I NEED THIS COLDER.
;      RELEASE_TEMP. Real part (the ~15 mm one).
;      Snippet: same as step 1 with G4 S120 after the waits, nothing
;      else -- door stays closed, nothing moves.
;      When Finished: open the door by hand, lift the part with two
;      fingers. Pass: no force needed. Sets RELEASE_BUFFER.
;      This step ANSWERS "is the bender useful": if the part is free,
;      the bender adds nothing on this plate and stays out. If it is
;      still stuck, first try lower RELEASE_TEMP / longer buffer; only
;      if that fails does the bender go back in (T2 sentinel M104 S3 +
;      triple tap, section 6c of GCODE-HOWTO.md).
;
;   3. DOOR: open and close with nothing else in the file.                 WORKS.
;      Snippet: M17, fans as in section 1 of this file, M104 S2 + long
;      press, G4 S30, M104 S5 + long press, M18.
;      Record: seconds from press to fully open; from press to closed.
;      Pass: opens, closes, no strain. Sets DOOR_OPEN_WAIT.
;      3b (optional): same without the G1 Z presses. Tells you whether
;      the sentinels alone drive the board (they should while Digital
;      mode is connected) -- the one earlier attempt was confounded by
;      the M190 R alarm.
;
;   4. PUSHER GEOMETRY, EMPTY PLATE -- the nozzle-breaking one.           WORKS. but be careful
;      4a. Printer idle, steppers off: measure with calipers the gap
;          between the nozzle tip and the pusher's lowest contact face.
;          That number is PUSHER_OFFSET. If the face is BELOW the tip,
;          the formula {max_layer_z} - 10 puts the face at
;          (part height - 10 - PUSHER_OFFSET) above the plate, and any
;          part shorter than (10 + PUSHER_OFFSET + 2) mm scrapes.
;      4b. Empty plate, 1-layer test print. Snippet: M17, door open as
;          in step 3, then ONE central sweep (G1 X125, Y250, Y0) at a
;          FIXED height, no placeholder: start at G1 Z20. Pass: no
;          contact, no sound. Then Z12, Z8, Z5, one run each, until you
;          hear or see contact -- stop there. The last silent height is
;          SWEEP_MIN. Never go below Z2. Do not use G91 Z-10 in this
;          step: with a 0.2 mm test print it would command Z-9.8.
;      4c. Check the rake path itself once at Z20 on the empty plate:
;          X30..X220, Y0..Y250, then X65 Y245 -> Y265 park. Pass: no
;          contact with bed clips, the front door frame, or the rear.
;
;   5. SWEEP, REAL PART. The ~15 mm part; step 1+2 cooldown first.
;      Snippet: this file with the sweep height HARD-CODED to the value
;      step 4 proved (e.g. G1 Z5), placeholder lines commented out.
;      Watch the toolhead: pusher face hits the part's side, part slides
;      to the front and out; no skipped steps, no nozzle contact with
;      the part top. Pass: plate empty, part in the bin undamaged.
;      Then repeat ONCE with the placeholder lines restored
;      (G1 Z{max_layer_z} / G91 Z-10) and confirm it moved to the same
;      height -- that proves Bambuddy resolved {max_layer_z}.
;
;   6. FULL CYCLE, ATTENDED. This file, unmodified, real part.
;      Pass: every stage in order, door closed at the end, plate empty,
;      total time noted. Any surprise -> back to the step that owns it.
;
;   7. THE PRINT AFTER. Queue a second print behind step 6 and watch its
;      START: homing OK after our M18 / M145 P0, no HMS alarm, start
;      taps fire, first layer normal. Pass: it prints.
;      Also check Bambuddy Settings -> Queue & Dispatch:
;        - "Require plate-clear confirmation" must be OFF, or the queue
;          will wait for a human after every print.
;        - "Keep bed warm between prints" must be OFF, or Bambuddy will
;          reheat the bed while this file is trying to cool it.
;        - "Preheat & soak" is fine on; it runs before our start snippet.
;
;   8. FIRST UNATTENDED RUN. Two prints queued, you leave the room but
;      stay in the building, camera on. Pass: both parts in the bin,
;      printer idle, no alarms. Only after this is the "DO NOT RUN"
;      line above allowed to go.
;
;   ANYTHING ELSE (not tests, but will bite):
;     - Bin under the front door: parts go out at Y0; make sure the
;       door swing and the pusher path clear it.
;     - HMS alarm mid-cycle (filament, clog, over-temp): the printer
;       pauses inside our end block; the door may stay open with the
;       bed halfway through the sweep. Decide now what you do then.
;     - LAN access code regenerates if LAN-only / Developer mode is
;       toggled; the FarmBoard and Bambuddy both lose the printer.
;     - Bambuddy injection failure is silent: the plain file prints and
;       the part just sits there. A missed start tap is the early tell.
;     - The FarmBoard's own log records every trigger; read it after
;       any step that misbehaves before blaming the G-code.
;     - Parts under 12 mm, or any part whose top is not its highest
;       point where the rake passes, need a hand-set height (step 4).
;
; =====================================================================
; P2S / FarmBoard END G-code injection -- Option A (cool-closed)
; Paste into Bambuddy: Settings -> Workflow -> G-code Injection -> P2S
; (end_gcode). Bambuddy inserts it immediately before
; `; EXECUTABLE_BLOCK_END`, i.e. AFTER the printer's entire stock end
; sequence -- see GCODE-HOWTO.md section 10. Every line below is
; annotated with where it was verified; section 12 of GCODE-HOWTO.md has
; the full table and the list of what is still unconfirmed.
;
; Order of events: cool with the door CLOSED, chamber air recirculated
; through the filter -> door opens once the bed has dropped below the
; release temperature -> pusher sweeps parts out of the open door ->
; door closes. No bender / safety-check stages: the bender is physically
; removed from this build (see ../README.md).
;
; Keeps BOTH the MQTT sentinel (M104 Sn) and the switch-press gestures,
; as the FarmLoop app's own output does. The vendor states the limit
; switch is disabled while Digital (MQTT) mode is connected, so in normal
; operation the sentinels do the work and the presses are inert.
;
; Facts this file relies on, all checked against the stock P2S profile
; (2026/05/18 templates) embedded in the evidence file:
;   * stock end G-code has ALREADY run: M140 S0, M104 S0, all fans off,
;     the M17 S / Z0.4 / M17 R low-current bracket, 2 x 180 s air
;     purification, the finish jingle, and M18 (steppers off).
;   * stock end G-code re-enables the Z soft endstop (M211 Z1), so a Z
;     below 0 clamps at 0 here. X/Y soft endstops stay off (M211 X0 Y0 Z0
;     from start G-code is never undone), which is what lets FarmLoop
;     park at Y265 beyond the 256 mm bed.
;   * printable_height = 256, so the Z243 / Z255 press heights and the
;     Z220 release are inside travel.
;
; --- Tunable parameters ---
;   RELEASE_TEMP    = 28   deg C. Engineering plate releases below ~30 C.
;                         NOTE a forum report (julie777, 2024) of M190 S40
;                         not continuing until 33 C: if this printer
;                         undershoots too, 28 may only release near 21 C
;                         and never in a warm room -- if the screen sits
;                         on "cooling to 28 C" far longer than the bed
;                         takes to reach it, raise this value.
;   RELEASE_REPEATS = 4    M190 S is repeated. Harmless if it blocks all
;                         the way; a ~40 min cap if it has the ~10 min
;                         per-call timeout reported on an X1C (arthor,
;                         2024). FarmLoop's own output repeats it 60x.
;   RELEASE_BUFFER  = 120  s dwell after the wait, so the plate/part
;                         interface (unmonitored) catches up with the bed
;                         sensor.
;   DOOR_OPEN_WAIT  = 12   s. Vendor: door open takes ~8 s; padded.
;   SWEEP_Z         = {max_layer_z} - 10   FarmLoop's push-height default
;                         ("maximum part height minus 10 mm"); the 170 mm
;                         evidence part was swept at Z160. {max_layer_z}
;                         is resolved by Bambuddy (present in 1.2.5.5);
;                         the -10 is a relative move.
;   SWEEP_MIN       = parts SHORTER THAN 12 mm: max-10 lands at <= 2 mm;
;                         Z clamps at 0 (soft endstop is on here) but the
;                         toolhead then drags across the plate. Hard-code
;                         `G1 Z<n>`, n >= 2, and delete the G91 block.
; =====================================================================

; --- 0. Re-enable steppers (stock end already ran M18) ---
M17                    ; bare M17 = enable all steppers (standard)

; --- 1. Heaters off, door CLOSED, filter-mode recirculation ---
; P2S has no exhaust fan. M145 P0 (cooling mode) opens the duct and pulls
; OUTSIDE air in through the aux fan, which pushes chamber air out into
; the room -- that was the smell on the first run. M145 P1 + P2 is
; Bambu's own post-print "air purification" branch: duct closed, chamber
; air recirculated through the filter. Slower cooldown, no fumes.
M106 S0                ; part cooling fan off                 (std, P1/no-P = part fan)
M106 P3 S0             ; chamber fan off                      (atlas: P3 = chamber fan)
M106 P10 S0            ; left aux fan off                     (atlas: P10 = P2S left aux)
M145 P1                ; airduct -> heating/filter mode       (stock P2S start+end G-code)
M106 P2 S255           ; aux fan = filter fan in this mode    (stock P2S end, J1 branch)
M140 S0                ; bed target 0                         (std; stock end already did)
M104 S0                ; hotend target 0                      (std; stock end already did)
; Faster alternative that DOES vent to the room (stock end's J2 branch):
; M145 P0
; M106 P3 S255

; RELEASE_TEMP wait, RELEASE_REPEATS times. Screen shows "cooling to 28C"
; while this holds (seen 2026-09-20). Community + our own run agree
; M190 S waits on COOLING on Bambu firmware; timeout/undershoot still
; being measured with end-gcode-test-m190.gcode.
; NEVER change to M190 R: on 2026-09-20 it raised HMS 0300-0100-0003-0008
; ("heatbed temperature set in G-code exceeds the limit ... adjusts to
; the maximum allowable temperature") -- i.e. it commanded the bed UP.
M190 S28
M190 S28
M190 S28
M190 S28
G4 S120                ; RELEASE_BUFFER                        (std; G4 S = seconds)

; --- 2. MQTT sentinel: T1 (fan on + door open) ---
M104 S2                ; T1 sentinel (nozzle_target_temper=2) (FarmLoop file; worked 2026-09-20)

; TRIGGER 1 gesture: vendor "Open door + fan: long press (4-8 s) at end
; of print". Z255 = pressed, Z243 = released (FarmLoop file).
G1 Z243 F3000          ; go to position
M400
G1 Z255 F3000          ; press
M400
G4 S5                  ; hold ~5 s
M400
G1 Z243 F3000          ; release

G4 S12                 ; DOOR_OPEN_WAIT

; --- 3. Sweep: slow pass, then fast pass, both at SWEEP_Z ---
G1 Z{max_layer_z} F10000   ; nozzle level with the top of the tallest part (Bambuddy placeholder)
M400
G91
G1 Z-10 F1200          ; sink 10 mm below it = FarmLoop's default push height
G90
M400

; central sweeps (2x)                                     (FarmLoop file, verbatim)
G1 X125 F3000
G1 Y250 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 Y0   F3000

; right-to-left rake, slow                                (FarmLoop file, verbatim)
G1 Y250 F3000
G1 X220 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X190 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X160 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X130 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X100 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X70  F3000
G1 Y0   F3000
G1 Y250 F3000
G1 X30  F3000
G1 Y0   F3000

G1 X220 F3000
M400

; right-to-left rake, fast, same height                   (FarmLoop file, verbatim)
G1 Y250 F12000
G1 X220 F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X190 F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X160 F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X130 F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X100 F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X70  F12000
G1 Y0   F12000
G1 Y250 F12000
G1 X30  F12000
G1 Y0   F12000

G91
G1 Z30 F3000           ; lift 20 mm clear of the tallest part top before travelling
G90
M400
G1 X65 Y245 F12000     ; safe corner                          (FarmLoop file)
G1 Y265 F3000          ; park at rear edge; beyond the 256 mm bed, legal because X/Y soft endstops are off

; --- 4. T2 (bend) and Safety-check: SKIPPED ---
; Bender removed from this build. Confirmed 2026-09-20: the FarmBoard
; accepts T3 and closes the door without ever seeing S3/S4.

; --- 5. MQTT sentinel: T3 (final door close) ---
M104 S5                ; T3 sentinel (nozzle_target_temper=5) (FarmLoop file; worked 2026-09-20)

; TRIGGER 3 gesture: vendor "Close door + finish: long press (4-8 s)".
G1 Z255 F3000          ; press
M400
G4 S5                  ; hold ~5 s
M400
G1 Z220 F3000          ; release and back off

; --- 6. Tail ---
M106 P2 S0             ; filter fan off
M145 P0                ; airduct back to cooling mode, the stock end's final state
M400                   ; wait for all motion
M18                    ; steppers off, as the stock end G-code finishes
