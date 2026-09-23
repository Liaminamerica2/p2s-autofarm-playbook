# G-code snippets

Known-good G-code fixes for Bambuddy's per-model start/end G-code injection (**Settings → Workflow → G-code Injection → P2S**), used to keep the FarmLoop Stage 2 board's ejection cycle in sync with the print. See [../software-setup/README.md#4-wire-it-into-bambuddy](../software-setup/README.md#4-wire-it-into-bambuddy) for where this gets configured, and [../hardware-setup/README.md](../hardware-setup/README.md) for the mechanism these markers drive.

> **TODO:** drop your actual working injection files in this folder (e.g. `end-gcode-p2s.gcode`) once finalized, and list them below. The notes here are what's been learned so far — the vendor tools regenerate raw G-code that needs the same fixes reapplied each time.

See **[GCODE-HOWTO.md](GCODE-HOWTO.md)** for the reverse-engineered mechanism behind the FarmBoard trigger sequence (MQTT sentinels via `M104 Sn`, tap/press gestures, sweep and cooldown blocks) — read this before hand-writing an injection block instead of relying on the FarmLoop app's output.

## Known-good notes

- On the P2S, `M106 P2` is the **auxiliary** fan and `M106 P3` is the **exhaust** fan. Generated code that fires the wrong one for cooldown needs `P2` swapped for `P3` in both the on and off lines.
- The stock Machine End G-code already runs a two-stage cooldown (aux fan first, then an exhaust fan gated on chamber temperature) **before** any block you add. If the door seems to wait forever, look there first — it's usually not your injected block.
- If the sweep or push runs too high and misses parts, measure the vertical gap between the nozzle tip and the pusher's contact face with the printer idle. Generated math may assume they're coplanar.
- Bambuddy inserts your start snippet **after** the printer's own homing/heat/prime, and your end snippet **after** the printer's entire stock end sequence (which ends in `M18`, steppers off). So: no `G28` needed at the top of a start snippet, and an `M17` is needed at the top of an end snippet before any `G1 Z` move. See [GCODE-HOWTO.md §10](GCODE-HOWTO.md#10-how-bambuddy-actually-inserts-these-snippets) for the full mechanism, verified against Bambuddy source.
- Injection failure is silent — a bad snippet just falls back to the un-injected file with a server-side log line, nothing visible on the printer.

## Files in this folder

- **[`start-gcode-p2s.gcode`](start-gcode-p2s.gcode)** — start-of-print injection: homes, then arms the FarmBoard (RESET sentinel + 4-tap gesture) and fires TRIGGER 0.
- **[`end-gcode-p2s.gcode`](end-gcode-p2s.gcode)** — end-of-print injection ("Option A" in [GCODE-HOWTO.md §9](GCODE-HOWTO.md#9-options-for-the-ejection-block)): cools with the door closed, gates the door open on bed temperature, sweeps the plate with the pusher, closes the door. Bender/safety stages are skipped — that hardware isn't in this build.
- **The test plan** — the header of `end-gcode-p2s.gcode` is an 8-step, one-variable-at-a-time campaign (cooling → plate release / is the bender needed → door → pusher height on an empty plate → sweep on a real part → full cycle → the print after → first unattended run), each step naming the parameter it fills in. Test snippets for the steps that are easy to get wrong by hand:
  - [`end-gcode-test-door.gcode`](end-gcode-test-door.gcode) — step 3: open, wait, close; nothing else.
  - [`end-gcode-test-sweep-height.gcode`](end-gcode-test-sweep-height.gcode) — step 4b/4c: one sweep at a fixed height on an empty plate, run per height from Z20 down; finds `SWEEP_MIN` without ever using the placeholder.
- **[`end-gcode-test-m190.gcode`](end-gcode-test-m190.gcode)** — step 1, diagnostic only. Swap it in for one run to learn whether `M190 S28` really blocks until the bed cools; the readout is the part fan spinning up and a 30 mm toolhead jog after each wait, plus the bed temperature when Finished appears (no door, no taps, no FarmBoard involved — and no "logo lamp", the P2S doesn't have one). Procedure and result table in [GCODE-HOWTO.md §11](GCODE-HOWTO.md#11-first-live-run-2026-09-20-and-the-m190-test). **Do not use `M190 R` on this printer** — it raised a bed-over-limit error and clamped the bed target up.
- The tunable values (release temperature, dwell padding, the `{max_layer_z} − 10` sweep height and its 12 mm minimum) are in the comment header at the top of `end-gcode-p2s.gcode` — read that before your first run.

**Status (2026-09-22):** every non-stock line in both snippets has been checked against the P2S stock templates, the community G-code atlas, the FarmLoop vendor docs and forum reports — the table is [GCODE-HOWTO.md §12](GCODE-HOWTO.md#12-line-by-line-verification-2026-09-22). Door open/close and the sentinels work on this board; the sweep height is per-model; cooldown now recirculates through the filter instead of venting. Still unconfirmed on this printer: the `M190 S` finish temperature (test snippet running), pusher contact at the new sweep height, and how long filter-mode cooldown takes.
