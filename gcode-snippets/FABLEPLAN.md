# Plan: G-code options for emptying the P2S after a print

## Context

The FarmLoop app's generated G-code is not trustworthy (see `FL_S2_INCIDENT.md`), so the ejection cycle
needs to be hand-written and injected via Bambuddy (or the slicer's Machine End G-code). The
mechanism is now documented in `gcode-snippets/GCODE-HOWTO.md`. This build differs from what the
app assumes:

- **Engineering plate**: parts self-release once the bed drops below ~30 °C. No bending needed.
- **Bender removed** (it propped the chamber open). Only the FarmBoard **door** and the toolhead
  **pusher** remain.
- FarmBoard runs Digital (MQTT) mode, but the user wants **both** the `M104 Sn` sentinels and the
  Z tap gestures kept, like FarmLoop does, so the cycle works even if MQTT drops.
- Decisions taken: **cool with the door closed first**, gate release on **bed temp (`M190`) plus a
  short buffer**, sweep with the **FarmLoop pusher out the front door**.

Deliverable: the option set written up (so the user can pick/mix), plus the recommended option
drafted as two snippet files ready to paste into Bambuddy.

## Options (all to be documented; only A gets drafted as a file)

| | Option | Order of events | Pros | Cons / risks |
|---|---|---|---|---|
| **A (recommended)** | Cool-closed, then open, sweep, close | print end → part fan off, aux+exhaust on → `M190 S<release>` → buffer dwell → **T1** door open → sweep (2 heights, 2 speeds) → **T3** door close → tail | Parts release before anything moves; chamber heat stays in the box; no bender/safety stages | Slower than B; needs `M190` to block on *cooling* on Bambu firmware (verify) |
| B | FarmLoop order: open first, cool with door open | print end → **T1** door open + fan → `M190` → sweep → **T3** close | Fastest cooldown | Dumps chamber heat and fumes into the room; door open for the whole wait |
| C | Sentinel-only (no Z taps) | Same as A minus every `G1 Z243/Z255` block | Shortest, no Z-axis hammering, no `Z20`/`Z220` park oddities | Dead if MQTT drops (user chose against this, keep as a documented fallback) |
| D | No FarmBoard | Door left open/removed; `M190` → sweep → park | Zero dependency on the board | Chamber open permanently; PLA/PETG only; fumes |
| E | Material-dependent A/B | Two end blocks toggled per queue item in Bambuddy | Best of A and B | Two snippets to maintain |

Sweep sub-options (documented, A uses E1+E2):
- **E1 Dual-height rake**: first pass at `SWEEP_Z_HIGH` (catches tall parts before the low pass can
  topple them), second at `SWEEP_Z_LOW` (short parts). Both use FarmLoop's X-stepped, Y front↔back rake.
- **E2 Two speeds**: slow (`F3000`) pass first, fast (`F12000`) pass second — FarmLoop's pattern, keep.
- E3 Nudge pass: one slow pass at low Z *before* the real sweep, to break any parts still stuck.
- E4 Perimeter-first: clear the four edges toward the front before the central rake (for plates
  packed to the edges).

Release-gate sub-options: `M190 S<t>` + `G4 S<buffer>` (chosen); fixed time only; `M190` + nudge pass.

## Recommended design (Option A) — what the end snippet does

```
;--- 1. heaters off, cool with door CLOSED
M106 S0            ; part fan off
M106 P2 S255       ; aux fan on
M106 P3 S255       ; exhaust fan on
M140 S0
M104 S0
M190 S<RELEASE_TEMP>   ; e.g. 28 — VERIFY it blocks on cool-down (else use R)
G4 S<RELEASE_BUFFER>   ; e.g. 120 — plate/part interface lags the bed sensor
;--- 2. T1: door open (+ FarmBoard fan)
M104 S2
<TRIGGER 1 long-press taps, from GCODE-HOWTO §6a>
G4 S<DOOR_OPEN_WAIT>   ; ~8 s per FL comment, pad to 12
;--- 3. sweep (dual height, dual speed, from GCODE-HOWTO §6d pattern)
G1 Z<SWEEP_Z_HIGH> F10000 ; = pusher_bottom_height + PUSHER_OFFSET
<rake @ F3000>
G1 Z<SWEEP_Z_LOW>  F10000
<rake @ F12000>
G1 X65 Y245 F12000 ; safe corner
G1 Y265 F3000      ; park rear
;--- 4. T3: door close  (T2 bend and S4 safety SKIPPED — bender removed)
M104 S5
<TRIGGER 3 long-press taps, from GCODE-HOWTO §6e>
;--- 5. tail
M106 S0 / M106 P2 S0 / M106 P3 S0, M400, M17 S / M17 Z0.4 / M400 P100 / M17 R, M17 X0.8 Y0.8 Z0.5
```

Parameters go in a comment header at the top of the file (`RELEASE_TEMP`, `RELEASE_BUFFER`,
`DOOR_OPEN_WAIT`, `PUSHER_OFFSET`, `SWEEP_Z_HIGH`, `SWEEP_Z_LOW`) with the values substituted inline —
plain G-code, no templating.

Start snippet = GCODE-HOWTO §3 verbatim (G28, `M104 S1`, 4-tap reset, TRIGGER 0), with the odd
`G1 Z20` final release changed to `G1 Z243` and flagged for a hardware check.

## Files

- **Create** `gcode-snippets/end-gcode-p2s.gcode` — Option A as above.
- **Create** `gcode-snippets/start-gcode-p2s.gcode` — RESET + TRIGGER 0.
- **Edit** `gcode-snippets/GCODE-HOWTO.md` — add `## 9. Options for the ejection block`: the table
  above, sweep/release sub-options, and the two open questions below.
- **Edit** `gcode-snippets/README.md` — fill "Files in this folder" with the two snippets and what
  each parameter means.

## Open questions to settle during implementation / first test

1. **Where Bambuddy inserts the end block.** If it appends *after* the slicer's Machine End G-code,
   the stock tail has already run `M18` (steppers off) and the 6-min air-purification waits. The
   snippet must then start with `M17` and either trust retained position or `G28 X Y` (not a full
   `G28`: Z-homing probes the bed and parts are still on it). Alternative: put the block in the
   OrcaSlicer printer profile's Machine End G-code *before* the stock tail — FL's file does exactly
   this (it deletes the stock sound/purification/`M18` and puts its tail last). Decide after checking
   Bambuddy's injection point once.
2. **Does the FarmBoard accept T3 (`S5`) without seeing T2 (`S3`) and Safety (`S4`) first?** Unknown.
   If it insists on the sequence, send `M104 S3` + `M104 S4` with no taps and no bend wait as a
   no-op ordering shim (bender absent → nothing physically happens).

## Verification

1. Extract-and-diff sanity: build a 3mf with the snippets, `unzip`, `grep -c '^G4 S30'` must be 0,
   `grep -n 'M104 S[1-5]' plate_1.gcode` shows S1 near the start and S2, S5 only after the last
   layer.
2. Dry run, heaters off: send a tiny 1-layer test print. Watch: reset taps at start, door stays
   closed until bed < `RELEASE_TEMP`, door opens, both sweep passes run at the expected heights,
   door closes, printer parks. Hand on the power switch.
3. Sweep-height check with a real part: measure nozzle-tip-to-pusher-face gap with the printer idle
   (per `hardware-setup/README.md`) and confirm `SWEEP_Z_LOW` clears the plate but hits parts ≥ 5 mm tall.
4. Only after 2–3 pass: first unattended run, then update the `TODO: confirm` rows in
   `troubleshooting/README.md` (door opening, push sweep height, cooldown timing).
