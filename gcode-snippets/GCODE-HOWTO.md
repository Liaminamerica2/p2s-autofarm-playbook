# G-code how-to: the FarmBoard ejection cycle

Reverse-engineered by diffing a plain slice against the same model run through
the FarmLoop app's Process Gcode step. Sources:

- Plain slice: [`../evidence/Poop-Bucket-Logo-V2(5)_Poop Bucket.gcode.3mf`](../evidence/Poop-Bucket-Logo-V2%285%29_Poop%20Bucket.gcode.3mf)
- Processed, single loop: [`../evidence/FL_S2_Poop-Bucket-Logo-V2(5)_Poop Bucket.gcode_single_loop.3mf`](../evidence/FL_S2_Poop-Bucket-Logo-V2%285%29_Poop%20Bucket.gcode_single_loop.3mf)

Goal: document the mechanism well enough to hand-write an equivalent
Bambuddy start/end G-code injection block (see
[../software-setup/README.md#4-wire-it-into-bambuddy](../software-setup/README.md#4-wire-it-into-bambuddy))
instead of depending on the FarmLoop app, whose output has at least one
serious placement bug — see [../FL_S2_INCIDENT.md](../FL_S2_INCIDENT.md) before
copying anything below verbatim.

> **DRAFT:** built from one model, one app version (2.72), FarmBoard firmware
> 2.94, P2S + Push Mode. Re-diff against your own files before trusting exact
> values. Comments in brackets are this doc's own notes, not from the source file.

---

## 1. The mechanism, in short

The FarmBoard doesn't parse G-code for meaning. It watches the printer's
**local MQTT** state — specifically `nozzle_target_temper`, set by `M104 Sn` —
for a small set of out-of-band values, and reacts to *when* that value shows
up and how long it stays. Two primitives do all the work:

1. **Sentinel values** — `M104 S<n>` where `n` is 1–5. These are never real
   print temperatures; they're a signal piggybacked on a command the firmware
   already reports over MQTT. Each value arms the next FarmBoard stage.
2. **Switch taps** — `G1 Z<height> F<feed>` moves that press/release a
   physical limit switch, because the bed/gantry position doubles as an input
   to the FarmBoard. `Z255` = pressed, `Z243` = released, `Z220` = fully
   retracted/parked. Tap *pattern* (count, duration, spacing) selects which
   gesture fires — this mirrors the vendor's documented Mechanical-mode
   gesture table (see [../hardware-setup/README.md](../hardware-setup/README.md)),
   just driven by G-code instead of a finger.

Sentinel table, in the order they appear in the file:

| Value | Name | Stage armed |
|---|---|---|
| `M104 S1` | RESET | Home the mechanism, arm MQTT auto-trigger |
| `M104 S2` | T1 | Fan on + door open (post-print) |
| `M104 S3` | T2 | Start bending |
| `M104 S4` | Safety | Run safety check |
| `M104 S5` | T3 | Final door close |

Every sentinel is followed almost immediately by the tap sequence for that
stage, then a `G4` dwell long enough for the physical mechanism to finish
before the next G-code line runs.

---

## 2. Tap/press primitives

| Command | Meaning |
|---|---|
| `G1 Z255 F<feed>` | Press the switch |
| `G1 Z243 F<feed>` | Release the switch (holding position) |
| `G1 Z220 F<feed>` | Release and fully retract (park) |
| `G4 P<ms>` | Dwell in milliseconds — used for short, precise gaps |
| `G4 S<sec>` | Dwell in seconds — used for long waits |
| `M400` | Wait for planner moves to finish before the next dwell starts, so the dwell timing is accurate |

Feed rates used: `F6000` (fast, first tap of a burst), `F3000` (normal
tap/release), `F1000` (slow presses inside a multi-tap gesture, e.g. triple
tap). Gesture identity seems to come from **tap count + hold duration**, not
feed rate — feed rate mostly just controls how crisp the press looks.

---

## 3. Start-of-print: RESET + TRIGGER 0

Inserted right after the initial `G28` home, **before** the model's own
first-layer/leveling G-code. Purpose: put the mechanism in a known state at
the start of every job, independent of whatever state it was left in after
the previous ejection.

```gcode
G28

; --- V2.93 MQTT sentinel: RESET (arm MQTT auto-trigger) ---
M104 S1                ; FL_S2 RESET sentinel (arm MQTT via nozzle_target_temper=1)

; --- RESET: 4 quick taps (within 3 seconds) ---
G1 Z255 F6000     ; Tap 1 - press
G4 P150
G1 Z243 F3000    ; Release
G4 P250
G1 Z255 F3000    ; Tap 2 - press
G4 P150
G1 Z243 F3000    ; Release
G4 P250
G1 Z255 F3000    ; Tap 3 - press
G4 P150
G1 Z243 F3000    ; Release
G4 P250
G1 Z255 F3000    ; Tap 4 - press
G4 P150
G1 Z243 F3000    ; Release

; Wait for reset sequence (bender returns home ~7s)
G4 P1000         ; Wait for reset complete

; --- TRIGGER 0: Long tap (3-4s) + Short tap ---

G1 Z255 F3000
M400
G4 P3500
G1 Z243 F3000    ; Release switch
G4 P500          ; Wait 500ms

G1 Z255 F3000    ; Short tap - quick press
G4 P200          ; Brief contact
G1 Z20 F3000    ; Release switch
```

Gesture shape: **4 quick taps (~150ms press / 250ms gap) → 1s settle → 1 long
press (~3.5s) → 500ms gap → 1 short tap (~200ms)**. The last release goes to
`Z20`, not `Z243`/`Z220` — worth double-checking against your own hardware's
neutral position rather than copying blindly.

> **Note:** the file's own comment says the reset takes "~7s" but the coded
> wait after the 4 taps is only `G4 P1000` (1s). Either the mechanism resets
> faster than the comment claims, or there's slack elsewhere (the TRIGGER 0
> long press) that absorbs the difference. Confirm on your own board before
> relying on the 1s figure.

---

## 4. ⚠️ The "FL NATURAL COOLDOWN" block — do not copy the placement

Appears a little further into the **start** sequence, still before the
model's nozzle-load/first-layer G-code:

```gcode
; ================ FL NATURAL COOLDOWN ================
; Hold in the closed chamber for 120 min before the door opens.
; Fans off so the part cools evenly instead of from one side — ASA, ABS
; and PC warp and split when cooled fast while still stuck to the plate.
M106 S0          ; part cooling fan off
M106 P2 S0       ; auxiliary fan off
M106 P3 S0       ; chamber fan off
G4 S30
G4 S30
... (240x total in the double-loop evidence file; the single-loop file matches this count per loop)
; ================ FL NATURAL COOLDOWN END (120 min) ================
```

This is exactly the defect written up in [../FL_S2_INCIDENT.md](../FL_S2_INCIDENT.md):
the block's own comment describes **post-print** behavior ("before the door
opens"), but it's spliced into the **pre-print** start sequence, heaters on,
fans off, for two hours. It reproduces in this single-loop file too — it
isn't specific to the double-loop case.

**If you want a real natural-cooldown hold, build it as its own stage gated
on bed temperature at the actual end of the print** — see the `M190 S26`
loop in §6, which *is* correctly placed. Don't lift this block's position;
only reuse the fan-off pattern (`M106 S0` / `M106 P2 S0` / `M106 P3 S0`) if
you need it, and remember `P2` = auxiliary, `P3` = exhaust/chamber on the
P2S (see [../gcode-snippets/README.md](../gcode-snippets/README.md)).

---

## 5. Nozzle-prep / bed-leveling swap (start sequence, minor)

Around the model's normal `G29.1` bed-mesh-compensation and nozzle-prime
lines, the processed file swaps in different values and a different prime
routine:

```gcode
G29.1 Z+0.00 ; for Textured PEI Plate
M109 S220
M975 S1
G90
M83
T1000

G92 E0
G1 E50 F200
M400
G1 X100 F21000
```

versus the stock slice's `G29.1 Z0.03` + a `G130`-based wipe-line prime.
This looks like app-level tuning (Z-offset choice, a simpler prime) rather
than anything the FarmBoard reacts to — no sentinel or tap pattern here.
`M975` and `T1000` meanings aren't confirmed against Bambu's command
reference; treat as unconfirmed and don't assume you need them unless you're
deliberately replicating the app's leveling behavior. Probably safe to leave
your slicer's stock version in place unless you hit a specific leveling
problem.

---

## 6. End-of-print: T1 → bed cooldown → T2 → sweep → safety → T3

This is the part worth replicating — it's the actual ejection cycle, and
(unlike §4) it's correctly positioned after the print's own end G-code.

### 6a. T1 sentinel + TRIGGER 1 (fan on, door open)

```gcode
; --- V2.93 MQTT sentinel: T1 (last-layer done) ---
M104 S2                ; FL_S2 T1 sentinel (open door + fan via nozzle_target_temper=2)

; --- TRIGGER 1: Long press (4-6 seconds) - Fan ON + Door Open ---
G1 Z243 F3000    ; Go to position
M400
G1 Z255 F3000       ; Press switch (slow = ~5s contact)
M400
G4 S5
M400
G1 Z243 F3000    ; Release switch
; Fan stays ON, door is opening
```

### 6b. Bed-temperature-gated cooldown (the *correct* cooldown)

```gcode
;Cooldown Start
M190 S26
M190 S26
... (repeated; 60 in this evidence file)
;Cooldown End
M140 S0 ; turn off bed
M104 S0 ; turn off hotend
```

`M190 Sxx` blocks until the bed reaches the target temperature — repeating
it is presumably a slicer-template artifact (or a workaround for something
re-issuing the wait), not literally 60 independent waits. If you write this
by hand, **one `M190 S<target>` should do the same job** — worth testing
rather than copying the repetition. `<target>` here is 26, matching the
temperature-based cooldown option mentioned in the incident report.

### 6c. T2 sentinel + TRIGGER 2 (start bending)

```gcode
; --- V2.93 MQTT sentinel: T2 (cool-done) ---
M104 S3                ; FL_S2 T2 sentinel (start bending via nozzle_target_temper=3)

; --- TRIGGER 2: Triple tap - Start bending ---
G4 P500
G1 Z255 F1000    ; Tap 1
G4 P150
G1 Z243 F3000
G4 P300
G1 Z255 F1000    ; Tap 2
G4 P150
G1 Z243 F3000
G4 P300
G1 Z255 F1000    ; Tap 3
G4 P150
G1 Z243 F3000

G4 P6000         ; Wait for count window to expire

; --- Wait for bending cycles ---
; 5 cycles x ~16s each = ~80 seconds
; Adjust based on your configured cycle count
G4 P85000        ; Wait for bending complete
```

Per the repo's own README, the bender is physically removed on this build
(it propped the bed open below 30 °C, replaced with an engineering plate) —
so this trigger is likely **not applicable to the current hardware**.
Documented here for completeness / in case the bender is reinstalled later.
The `5 cycles × ~16s` figure is explicitly a guess in the source comment —
if you ever re-enable the bender, verify the real cycle time instead of
trusting `G4 P85000`.

### 6d. Sweep / push section

Marked with `@fl:section:start "p2s.clear.sweep"` / `@fl:section:end` —
these look like the FarmLoop app's own template markers (probably consumed
by the app when re-processing a file, not by the printer or FarmBoard). Two
passes at different speeds, same path shape:

```gcode
; @fl:section:start "p2s.clear.sweep"
;============================= PUSH SECTION =============================
; @fl:replace next 1 "clear-height.smart-default"
G1 Z160.00 F10000
M400

; -------- central sweeps (2x) --------
G1 X125 F3000
G1 Y250 F3000
G1 Y0   F3000
G1 Y250 F3000
G1 Y0   F3000

; -------- extended right-to-left rake --------
; far right (X220), sweep back->front, step left 30mm each pass
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

G1 Z160.00 F12000 ; second pass, faster
M400

; same rake pattern repeated at F12000
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
;===============================  END SECTION  =============================

M73 P74 R2
G1 X65 Y245 F12000     ; move to safe corner before parking
G1 Y265 F3000          ; final park at rear edge (idle position)
```

`Z160.00` is the sweep height (`@fl:replace next 1 "clear-height.smart-default"`
suggests the app computes this per-model from part height). Per
[../hardware-setup/README.md](../hardware-setup/README.md), if the sweep
misses parts or runs into them, the generated height math may be assuming
the nozzle tip and pusher contact face are coplanar when they aren't on your
build — measure that gap with the printer idle before trusting this number.

### 6e. Safety check trigger + T3 (final door close)

```gcode
; --- V2.93 MQTT sentinel: Safety (push-done) ---
M104 S4                ; FL_S2 safety sentinel (run safety check via nozzle_target_temper=4)

; --- TRIGGER SAFETY CHECK: Double tap ---
G1 Z243 F3000    ; Go to position
M400
G1 Z255 F1000    ; Tap 1
G4 P150
G1 Z243 F3000
G4 P300
G1 Z255 F1000    ; Tap 2
G4 S5
G1 Z243 F3000

; --- Wait for safety check (5-step sequence) ---
; Bender extend(7s) + retract(7s) + extend(7s) + door open(8s) + door close(8s) = ~37s
G4 P20000        ; Wait for safety check

; --- V2.93 MQTT sentinel: T3 (push-done, door close) ---
M104 S5                ; FL_S2 T3 sentinel (final door close via nozzle_target_temper=5)

; @fl:section:end "p2s.clear.sweep"
; @fl:section:start "p2s.stage2.trigger3"
; --- TRIGGER 3: Long press (4-6 seconds) - Final door close ---
G1 Z255 F3000
M400       ; Press switch (slow = ~5s contact)
G4 S5
M400
G1 Z220 F3000    ; Release switch
; @fl:section:end "p2s.stage2.trigger3"
```

Note the comment says the safety sequence takes ~37s but the coded wait
(`G4 P20000`) is only 20s — same kind of comment/code mismatch as §3.
Verify against real hardware timing rather than trusting either number
outright, and pad the dwell if your board consistently needs longer.

### 6f. Tail: fans off, motor current restore

```gcode
M106 S0 ; turn off fan
M106 P2 S0 ; turn off remote part cooling fan
M106 P3 S0 ; turn off chamber cooling fan

M400 ; wait all motion done
M17 S
M17 Z0.4 ; lower z motor current to reduce impact if there is something in the bottom

M400 P100
M17 R ; restore z current

M220 S100  ; Reset feedrate magnitude
M201.2 K1.0 ; Reset acc magnitude
M73.2   R1.0 ;Reset left time magnitude
M1002 set_gcode_claim_speed_level : 0

M17 X0.8 Y0.8 Z0.5 ; lower motor current to 45% power
```

The `M17 S` / `M17 Z0.4` / `M400 P100` / `M17 R` block (lower Z current,
pause, restore) is stock Bambu end G-code — kept as-is, just moved to after
the ejection cycle instead of being the very last thing that runs. The
processed file also **drops** the stock sound sequence (`M1006 ...`) and the
air-purification block (`M622`/`M623`) that the plain slice has — decide
deliberately whether you want those back; nothing here suggests the
FarmBoard needs them gone, they may just not have been carried over.

---

## 7. Consolidated timing reference

| Stage | Tap pattern | Post-trigger wait |
|---|---|---|
| RESET | 4x quick tap (150ms press / 250ms gap) | `G4 P1000` (1s) |
| TRIGGER 0 | 1 long press (~3.5s) + 1 short tap (~200ms) | none coded |
| TRIGGER 1 (fan+door) | 1 long press (~5s) | none coded before bed cooldown |
| Bed cooldown | — | `M190 S26` until bed ≤ 26 °C |
| TRIGGER 2 (bend) | 3x tap (~1s hold, ~300ms gap) | `G4 P6000` + `G4 P85000` (~91s total, tune to your bend-cycle count) |
| Safety check | 2x tap (last tap held 5s) | `G4 P20000` (20s; comment implies ~37s — verify) |
| TRIGGER 3 (door close) | 1 long press (~5s) | none coded |

---

## 8. Before writing your own injection block

- Re-run the diff yourself against a current export before trusting any
  value above — app version, firmware version, and your own Detachment
  Tuning settings (push height, cooldown target) all change the generated
  numbers:
  ```bash
  diff raw/Metadata/plate_1.gcode fl/Metadata/plate_1.gcode | less
  ```
- Don't lift the §4 cooldown block's *position* — only its fan-off pattern
  if you need one, placed at the real end of print.
- Confirm the sweep height (`Z160.00` here) against your own nozzle/pusher
  gap, not this model's number.
- If the bender is out of your build (per the main [README.md](../README.md)),
  TRIGGER 2 and the safety check's bender-extend/retract timing likely don't
  apply — you may only need TRIGGER 1 (door open), the bed cooldown, and a
  door-close trigger.
- Test each stage watching the machine, one trigger at a time, before
  trusting a full unattended run — see [../FL_S2_INCIDENT.md](../FL_S2_INCIDENT.md#how-to-check-your-own-files-before-running-them).

---

## 9. Options for the ejection block

This build differs from what the FarmLoop app assumes: an **engineering
plate** (parts self-release below ~30 °C, no bending needed) with the
**bender physically removed** (it propped the chamber open), leaving only
the FarmBoard **door** and the toolhead **pusher**. [`start-gcode-p2s.gcode`](start-gcode-p2s.gcode)
and [`end-gcode-p2s.gcode`](end-gcode-p2s.gcode) in this folder implement
the recommended option below; the alternatives are documented here in case
your setup differs.

### Event-order options

| | Option | Order of events | Pros | Cons / risks |
|---|---|---|---|---|
| **A (used)** | Cool-closed, then open | print end → fans off/aux+exhaust on → `M190 S<release>` → buffer dwell → T1 door open → sweep → T3 door close → tail | Parts release before anything moves; chamber heat stays in the box | Slower than B; needs `M190` to actually block on cooling — verify on your firmware |
| B | FarmLoop's order: open first, cool with door open | print end → T1 door open+fan → `M190` → sweep → T3 close | Fastest cooldown | Dumps chamber heat/fumes into the room while cooling |
| C | Sentinel-only (no Z taps) | Same as A, minus every `G1 Z243/Z255` block | Simplest, no Z-axis hammering | Dead if MQTT/Digital mode drops — not used here, kept as a fallback |
| D | No FarmBoard | Door left open/removed; `M190` → sweep → park | Zero dependency on the board | Chamber open permanently; PLA/PETG only |
| E | Material-dependent A/B | Two end blocks, toggled per queue item in Bambuddy | Best of A and B per material | Two snippets to keep in sync |

### Sweep sub-options

- **Per-model height, `{max_layer_z} − 10`** — used. This is FarmLoop's
  own default: its Detachment Tuning page says "Push height is
  automatically calculated as the maximum part height minus 10 mm", and
  the evidence file (a 170.00 mm part, `max_z_height` in its header) was
  swept at `Z160.00`. Bambuddy resolves `{max_layer_z}` at dispatch; the
  `−10` is a relative `G91` move. **Not safe below ~12 mm part height**
  — see the `SWEEP_MIN` note in the snippet. (The stock P2S end G-code
  runs `M211 Z1`, so at this point a negative Z clamps at 0 rather than
  driving the bed into the nozzle — but the toolhead then drags across
  the plate, so the rule stands.)
- **Dual-speed passes** — slow (`F3000`) first, fast (`F12000`) second.
  The source file's own pattern, kept as-is.
- ~~Dual-height rake~~ — dropped after the first live run. On a 15 mm
  part the formula already puts the pusher 5 mm off the plate; there is
  no meaningful lower pass, and without a measured pusher offset a lower
  pass is a plate-crash risk.
- Not used, but worth knowing about: a slow "nudge" pass at low Z *before*
  the real sweep to break loose any parts still stuck; sweeping the plate
  perimeter before the central rake, for plates packed to the edges.

### Release-gate sub-options (A uses the first)

- `M190 S<target>` (block until bed reaches target) + a fixed `G4` buffer
  dwell — used here, since bed temperature is the only signal available
  and the plate/part interface lags the sensor.
- Fixed time only, no temperature check — simpler, but ignores room
  temperature swings.
- Temperature gate plus a nudge pass (see above) before the real sweep.

### Open questions carried into the snippets

1. ~~Where Bambuddy inserts the end block.~~ **Resolved — see section 10.**
2. ~~Whether the FarmBoard needs T2 (`S3`) / Safety (`S4`) sentinels before
   it'll accept T3 (`S5`).~~ **Resolved on the first live run (2026-09-20):
   it doesn't.** The door closed on T3 with S3/S4 never sent, so
   `end-gcode-p2s.gcode` skips both with no shim.

---

## 10. How Bambuddy actually inserts these snippets

Confirmed by reading Bambuddy's source directly (`maziggy/bambuddy`, commit
`9e9c08b`, main, 2026-09-17) — this replaces guesswork with the real
mechanism, and fills the TODO in
[../software-setup/README.md#4-wire-it-into-bambuddy](../software-setup/README.md#4-wire-it-into-bambuddy).

**Injection happens server-side, in Python, at print-dispatch time — not on
the printer and not in the slicer.** When a queue item has
`gcode_injection = True`, `PrintScheduler._start_print()`
(`backend/app/services/print_scheduler.py`) calls
`inject_gcode_into_3mf()` (`backend/app/utils/threemf_tools.py`), which:

1. Opens the `.gcode.3mf` (a zip), and edits the plate's `.gcode` text
   in-memory.
2. **Start snippet** (what you paste into Settings → Workflow → G-code
   Injection → start_gcode) is inserted immediately **before** the line
   `; MACHINE_START_GCODE_END`. That marker sits at the bottom of the
   printer's own startup block — bed heat, homing, nozzle prime are already
   done by the time your snippet runs. This is why
   [`start-gcode-p2s.gcode`](start-gcode-p2s.gcode) has **no leading
   `G28`** — it would be redundant.
3. **End snippet** is inserted immediately **before** `; EXECUTABLE_BLOCK_END`.
   Bambu firmware (confirmed on a P1S, per the injector's own code comments)
   ignores G-code placed *after* that marker — so your end snippet runs
   *inside* the executable block, but **after the printer's own complete
   machine-end sequence**, which this repo's own plain-slice evidence file
   ends with `M18` (steppers fully de-energized). This is why
   [`end-gcode-p2s.gcode`](end-gcode-p2s.gcode) now starts with an explicit
   **`M17`** before any `G1 Z` move — without it, the first tap gesture
   would be commanding a disabled stepper.
4. Recomputes the `Metadata/plate_N.gcode.md5` sidecar automatically. You
   don't need to handle this yourself — it's only relevant if you ever
   write your own injector outside Bambuddy.
5. Writes a temp copy and uploads that; **the original library/archive
   file is never modified.**

If either marker is missing from a file (older export, non-Bambu slicer),
Bambuddy falls back to prepending (start) or appending at EOF (end) instead
— worth knowing if a future firmware/slicer update changes the template.

**Other behavior worth knowing:**

- **Injection failure is silent.** Any exception, or a `None` result, logs
  a warning server-side and the **original, un-injected file prints
  instead** — nothing on the printer itself will tell you your snippet
  didn't run. Check Bambuddy's logs if the ejection cycle doesn't fire.
- **Snippets are keyed by printer model**, so a farm with mixed printer
  models can carry different snippets per model in the same Settings JSON.
- **Placeholder substitution exists**: `{max_layer_z}` / `{max_print_height}`
  resolve to the model's tallest point (Bambu's `max_z_height` header
  field), `{total_layers}` to `total_layer_number`. Substitution is
  literal text replacement only — no arithmetic — so you can't write
  `{max_layer_z - 10}`. The workaround `end-gcode-p2s.gcode` uses:
  `G1 Z{max_layer_z}` then `G91` / `G1 Z-10` / `G90`. **Confirmed present
  in the 1.2.5.5 tag** (fetched `backend/app/utils/threemf_tools.py` at
  that tag: `_substitute_placeholders`, the `max_layer_z` alias, both
  markers and the MD5 recompute are all there), not just on main.
- If a placeholder is unknown it is left as literal text with only a
  server-side warning, so `G1 Z{max_layer_z}` would reach the printer
  verbatim. Bambu firmware should reject the malformed Z and not move,
  and the following relative `Z-10` then runs from wherever the bed is —
  harmless at the post-tap height, but the sweep would run at the wrong
  Z. If parts are ever left behind, check Bambuddy's logs for that
  warning first.
- Only one plate is targeted (the one selected, or else the lowest-numbered
  `.gcode` member) — irrelevant for single-plate farm prints, but worth
  knowing if you ever queue multi-plate files.

---

## 11. First live run (2026-09-20) and the M190 test

Run with `end-gcode-p2s.gcode` as it stood before this section, on a
~15 mm part (75 layers × 0.2 mm):

| Observation | Meaning | Change made |
|---|---|---|
| Door closed at the end | T3 works without S3/S4 | shim removed (§9 q2) |
| Sweep "way too high" | fixed `Z160` was from a 170 mm part | `{max_layer_z} − 10` (§9) |
| Smell in the room during cooldown | aux fan (`P2`) recirculating fumes | `M106 P2 S0`; exhaust `P3` kept |
| Screen showed "cooling until 28 °C", door opened — not clear when | `M190 S28` was *recognised* as a bed wait, but unknown whether it released at 28 °C or timed out earlier (the `G4 S120` right after it hides the moment) | isolate it with the test below |

Why the timing is worth one dedicated run: in Marlin lineage `M190 S`
waits only while *heating*; `M190 R` waits in both directions. FarmLoop's
own file repeats `M190 S26` sixty times, which smells like a per-call
timeout being worked around. Bambu's real behaviour is unknown.

> **`M190 R` is off the table.** Tried on 2026-09-20 (injection confirmed
> working — the start taps ran): the printer raised *"temperature of the
> heated bed exceeds the limit and automatically adjusts to the limit
> temperature"*, then reported Finished a few minutes later with no door
> movement. That text is **HMS 0300-0100-0003-0008**, whose documented
> cause is "the heatbed temperature set in G-code exceeds the limit; the
> printer adjusts to the maximum allowable temperature" — so the `R`
> form was parsed as a target *above* the bed maximum and the bed was
> commanded up, not down. On the X1C forum thread `M190 R` is reported as
> "does not work… times out after maybe 10 minutes… gives up around 45 °C"
> (arthor, 2024). Treat it as a heater-on hazard on this firmware.

**Test:** [`end-gcode-test-m190.gcode`](end-gcode-test-m190.gcode). Paste
it as the END snippet in place of the production one, queue a tiny
1-layer print (no sweep, no door, no taps — a leftover part is fine),
and watch the bed temperature on the printer screen. Three `M190 S28`
run back to back; after each one the **part-cooling fan spins for 3 s
and the toolhead jogs 30 mm in X and back** — audible and visible, no
Z, no door. Note the bed temperature and clock time at every signal and
when Finished appears:

| Signals… | Verdict | Production fix |
|---|---|---|
| once at ~28 °C after a real wait, then twice more within seconds | `M190 S` blocks until cool | keep the single `M190 S28` — done |
| every N seconds/minutes, bed still hot each time | `M190 S` has a per-call timeout of N | repeat `M190 S28` ⌈cooldown ⁄ N⌉ times (FarmLoop's 60× now makes sense) |
| within seconds of the last layer, all three in a row | `M190 S` ignores cooling | fixed `G4 S<seconds>` sized to a cooldown you time by hand |

Even if you miss the signals, the bed temperature when the screen shows
**Finished** settles most of it: ~28 °C means it blocks until cool;
clearly hotter means it timed out three times over.

> The first version of this test toggled the "logo lamp" (`M960 S5`)
> because the stock P2S start G-code uses it. That lamp is an X1-series
> part; the P2S has nothing visible to switch, and nothing was seen on
> the 2026-09-22 run. That run still produced a result: the bed was 42 °C
> at the last layer and the screen still read "cooling to 28 °C" minutes
> later, so `M190 S28` **does hold on cooling** at least that long —
> what's left is whether it holds all the way to 28 °C.

**What the community says about `M190 S` on cooling** (all X1/P1-era
reports; none P2S-specific, which is why our own test matters):

- the_Raz (X1C, 2023): "Bambu seem to use M190 S for cooling too: I've
  seen it (unnecessarily) wait for cooling after I replaced the smooth
  PEI to the cold plate between prints."
- NVNDO (2024), working auto-eject end G-code: `M140 S0 ; For some reason
  you need to set the bed temp again before` → `M190 S30 ; wait for bed
  to be cold` → `G04 S300` → push. Note the `M140 S0` *first* — our
  snippet already does that.
- julie777 (2024): set `M190 S40`, "code execution does not continue
  until the bed temp reaches 33C" — a ~7 °C **undershoot**. If the P2S
  does the same, a 28 °C target may need ~21 °C bed, unreachable in a
  warm room. `RELEASE_TEMP` guidance in the snippet header covers this.
- ProtoSpyre (2024): a soft alarm "bed temperature abnormal, exceeds
  maximum temperature" while the bed sits above a low target. Not seen
  on our runs with `S28` (only with `R28`), but worth recognising.
- Alternatives people use instead: `M140 S<t>` + `G4 P60000` ×10 stepped
  down (3DTech), or `M400 S600` + `M140 S<t>` steps (JonRaymond). Both
  are time-based; `M190 S` repeated N× (FarmLoop's 60×) is the only
  temperature-based form in the wild.

---

## 12. Line-by-line verification (2026-09-22)

Sources: **stock** = the P2S start/end templates (2026/05/18) embedded in
the evidence file's header; **atlas** = the community Bambu G-code atlas
(georgebashi), with its own confidence marks; **FL** = the FarmLoop app's
output in the evidence file; **vendor** = 3D Farmers help center;
**run** = observed on this printer.

| Line(s) | Purpose | Verified by | Status |
|---|---|---|---|
| `M17` (bare) | re-enable steppers after stock `M18` | atlas ✅ standard; stock end ends `M400` / `M18` | OK |
| `M106 S0` / `P3 S0` / `P10 S0` | part, chamber, left-aux fans off | atlas ✅ P-index table (P10 = P2S left aux); stock end uses all three | OK |
| `M145 P1` + `M106 P2 S255` | closed duct, recirculate through filter | stock end "air purification" J1 branch, byte-identical; ha-bambulab: mode 1 "uses chamber air sucked through a filter" | OK |
| `M145 P0` + `M106 P3 S255` (commented alt.) | cooling mode, vents | stock end J2 branch; ha-bambulab: mode 0 "air is pulled from the outside" | OK, smells |
| `M140 S0`, `M104 S0` | heaters off (again) | standard; NVNDO's "set the bed temp again before M190" | OK |
| `M190 S28` ×4 | wait for bed to cool | run: screen "cooling to 28 °C", held ≥ minutes at 42 °C; the_Raz, NVNDO, julie777 | **hold confirmed; finish temp / timeout / undershoot pending test** |
| `M190 R…` | — | run: HMS 0300-0100-0003-0008; arthor: times out ~10 min | **never use** |
| `G4 S120`, `G4 S12`, `G4 S5` | dwell, seconds | forum 666: `G4 S` seconds, `P` ms; FL uses both | OK |
| `M104 S2` / `M104 S5` | FarmBoard sentinels | FL comments "V2.93 MQTT sentinel"; run: door opened on S2, closed on S5 | OK on this board; **not vendor-documented** |
| `G1 Z243` / `Z255` / `Z220` presses | switch gestures | FL file; vendor gesture table (long press 4–8 s = door open / door close); printable_height 256 | OK; inert while Digital mode connected (vendor) |
| `G1 Z{max_layer_z}` + `G91 Z-10 G90` | sweep height = max part − 10 | FarmLoop UI text + evidence (170 → 160); Bambuddy 1.2.5.5 source has the alias | OK; **pusher contact not yet seen at this height** |
| sweep X/Y pattern | rake parts to the front | FL file verbatim; X/Y soft endstops off (stock never re-enables) so Y265 is legal | OK |
| `G91 Z30 G90` lift | clear leftover parts before park | our addition; Z soft endstop on (`M211 Z1`, stock end line 3) | OK |
| `M18` | steppers off | stock end's last command | OK |
| `M17 S / Z0.4 / R` bracket | (removed) | atlas: `M17 S` ❓ unknown; bracket only meaningful around a downward move | removed as no-op |
| `M960 S5` | (removed from test) | forum 666: "toolhead logo lamp"; run: nothing visible on P2S | removed |
| start: `M104 S1` + 4 taps + long+short | reset, close door | FL file; vendor: "four quick taps = emergency reset", "long press + short tap = close door, print begins"; soft endstops off here (`M211 X0 Y0 Z0` ×2 before marker) | OK |

> **Where the references disagree with the printer, the printer wins.**
> The atlas' thermal section states the P2S "has no M145 P1 (heating-mode
> routing)" and "no M141/M191 anywhere in P2S templates". The 2026/05/18
> P2S template embedded in this repo's evidence file contains both:
> `M145 P1 ; set airduct mode to heating mode for heating` (start, and
> the end G-code's air-purification J1 branch) and `M191 S0 ; wait for
> chamber temp` (start, cooling branch). The atlas was compiled from an
> older profile set. The ha-bambulab P2S issue independently describes
> mode 1 as "chamber air sucked through a filter", which is what the
> snippet relies on.

### Still needs confirmation on this printer

1. **`M190 S28` finish temperature** — does it release at 28, undershoot,
   or time out? The running/next `end-gcode-test-m190.gcode` answers it.
2. **Sweep contact** at `{max_layer_z} − 10` on a real part: the formula
   is the vendor's, but the pusher's face-to-nozzle offset on this
   toolhead has never been measured.
3. **Filter-mode cooldown time** with the door closed and only the aux
   fan recirculating — likely much slower than the vented run; if it's
   impractical, switch to the commented `M145 P0` alternative and accept
   the smell, or vent the room.
4. **Sentinel-only door open** — the one run without taps (the `R28` run)
   failed, but the HMS alarm confounds it. Not important while both
   mechanisms are in the file.
5. **`M145 P0` in the tail** — restores the stock end's final airduct
   state; harmless, but unverified that the next print's start G-code
   expects it (it sets its own mode anyway).

Put `end-gcode-p2s.gcode` back afterwards and carry the result into its
section 1.
