# Troubleshooting & status

Detailed, in-the-weeds notes for people actually building this. If you're just here to see how the farm is architected, the [root README](../README.md) covers that; this file is the deep dive.

## Status

| Area | State |
|---|---|
| Bambuddy on headless server | Working |
| OrcaSlicer sidecar | Working |
| Bambu Studio sidecar | **TODO:** confirm |
| Part detachment | Fixed with an engineering plate |
| FarmBoard MQTT connection | **TODO:** confirm |
| Door opening | **TODO:** confirm |
| Push sweep height | **TODO:** confirm |
| Cooldown timing | **TODO:** confirm |

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `no configuration file provided` when starting the sidecars | You ran compose from the wrong folder. `cd bambuddy/slicer-api` first. |
| FarmBoard LED shows 4 long blinks | MQTT failed. Recheck IP and access code, and confirm LAN-only mode. |
| FarmBoard says "No printer configured" | Recheck the Printer Connection card. Also check that the printer's IP isn't on the same subnet as the board's own setup access point. **TODO:** confirm whether this was your cause. |
| Access code stopped working | It regenerates when LAN-only or Developer Mode is toggled. |
| Cycle doesn't fire | The `FL_S2_` file was renamed or re-saved. Re-process it in the app. |
| Bambu Studio shows "Stopped" for a good print | Display quirk of how it reads the G-code end. The board still completes its sequence. |
| Part bends loose but isn't ejected | Bending only detaches. The push sweep is what ejects. |
| Sweep passes above short parts | Nozzle-to-pusher offset. Measure it, then adjust. |
| Very long wait before the door opens | Stock end G-code cooldown, not your added block. |
| Printer freezes mid-print | Check for a full USB stick from video recordings. |
| Lift Mode greyed out | Not supported on the P2S. Use Push Mode. |
| Bambuddy unreachable from your phone | Firewall on the server (port 8001). |
