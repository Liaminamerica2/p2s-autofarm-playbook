# Hardware setup

Getting the P2S, AMS, and FarmLoop Stage 2 kit physically assembled, networked, and tuned so parts actually get ejected. For the server-side software (Bambuddy, slicer sidecars), see [../software-setup/README.md](../software-setup/README.md). For the G-code injected into prints, see [../gcode-snippets/README.md](../gcode-snippets/README.md).

## Bill of materials — hardware

| Item | Notes |
|---|---|
| Bambu Lab P2S | With AMS 2 Pro |
| FarmLoop Stage 2 kit | FarmBoard, door, bender and pusher attachment |
| Engineering build plate | Fixed part-detachment problems in this setup |
| Always-on Linux box | Any x86_64 machine that can run Docker |
| Storage for the printer | SD card and/or large USB stick (see [Prepare the printer](#1-prepare-the-printer)) |

## 1. Prepare the printerhttps://marketplace.visualstudio.com/items?itemName=appliedengdesign.vscode-gcode-syntax

1. Update the printer firmware and slicer to current versions.
2. Turn on **LAN-only mode** and **Developer Mode**. Local MQTT is only exposed when both are on.
3. Write down three values. You will need them for both Bambuddy and the FarmBoard:
   - Printer IP (Wi-Fi settings on the printer)
   - LAN access code (8 digits, network settings)
   - Serial number (device settings)
4. **The access code regenerates when you toggle LAN-only or Developer Mode.** Re-read it after any change.
5. Insert storage. The P2S needs it for file transfer and thumbnails, and "store on external storage" is now a toggle on the printer itself rather than in the slicer. If you record video or timelapse, use a large-capacity stick formatted in the printer, because a full USB stick has been reported to freeze prints mid-job.

> Give the printer a DHCP reservation so its IP never changes. 

## 2. Set up the FarmLoop Stage 2 board

1. Assemble the kit following the vendor's instructions. TODO: DETERMINE IF THE BENDER IS REQUIRED BECAUSE WE HAVE THE ENGINEERING PLATE
2. Put the FarmBoard in **OTA mode** and open `http://farmloop.local`.
3. In the **Printer Connection** card, enter your Wi-Fi SSID and password, the printer IP, the LAN access code and the serial number.
4. Tick **Enable MQTT auto-trigger**, save, and exit OTA mode.
5. Read the LED after reboot:

| LED pattern | Meaning |
|---|---|
| 5 slow + 10 fast blinks | Wi-Fi and MQTT both connected |
| 2 long blinks | Wi-Fi failed: check SSID and password |
| 4 long blinks | MQTT failed: check printer IP, access code and LAN-only mode |

While Digital mode is connected, the board's limit switch is disabled. Turn Digital mode off (or take the printer off the network) if you need it for testing.

> **No-software fallback:** the board also has a Mechanical mode driven by button gestures (close door, open door + fan, start bending, and so on). It works with no app, account or Wi-Fi, but you have to be there to tap through each stage. See the vendor's docs for the gesture table.

## 3. Prepare files for ejection

1. Process your sliced file in the FarmLoop app. Output files are prefixed with **`FL_S2_`** and carry the embedded markers.
2. **Do not rename or re-save** the processed file (not in Bambu Studio, not in a file browser). Doing so can strip the markers and the cycle won't fire. Re-process through the app instead.
3. On the P2S, **Push Mode is the only detachment option.** Lift Mode is marked "Not available for P2S" in the app. Push height defaults to max part height minus 10 mm and can be overridden.
4. Tuning that helps detachment: a lower bed temperature and a slightly higher first-layer Z offset. An engineering plate made the biggest difference here.
5. If the sweep or push runs too high and misses parts, measure the vertical gap between the nozzle tip and the pusher's contact face with the printer idle. Generated math may assume they're coplanar.
