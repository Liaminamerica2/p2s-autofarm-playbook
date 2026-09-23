# Software setup

The server-side stack: Bambuddy, the slicer sidecars, and the desktop slicer. For physically setting up the printer and the FarmLoop board, see [../hardware-setup/README.md](../hardware-setup/README.md). For the actual G-code injected into prints, see [../gcode-snippets/README.md](../gcode-snippets/README.md).

## Bill of materials — software

| Item | Purpose |
|---|---|
| [Bambuddy](https://github.com/maziggy/bambuddy) | Self-hosted print manager (queue, archive, G-code injection) |
| `orca-slicer-api` / `bambu-studio-api` | Server-side slicing sidecars, shipped in Bambuddy's `slicer-api/` folder |
| OrcaSlicer or Bambu Studio | Desktop slicing (the slicer itself needs a GUI) |
| FarmLoop app | Processes files and embeds the markers the FarmBoard listens for |

## 1. Run Bambuddy

On the server:

```bash
git clone https://github.com/maziggy/bambuddy.git
cd bambuddy
docker compose up -d
```

Follow the upstream README for the exact compose file and options. The UI comes up on port **8001** (`http://<SERVER_IP>:8001`).

- If you can't reach it from another device, check the server's firewall first.
- In the UI, add the printer using its IP, access code and serial number (see [../hardware-setup/README.md#1-prepare-the-printer](../hardware-setup/README.md#1-prepare-the-printer)).
- Bambuddy offers an optional Bambu Cloud token sync. Skip it if you want to stay fully local.

## 2. Add the slicer sidecars

The sidecars are pre-built `linux/amd64` images, so no local build is needed. They live in a **subfolder** of the Bambuddy repo:

```bash
cd bambuddy/slicer-api
cp .env.example .env            # optional: change ports or pin SIDECAR_TAG
docker compose up -d            # OrcaSlicer sidecar only
# or
docker compose --profile bambu up -d   # both sidecars
```

Then check health and point Bambuddy at them:

```bash
curl http://localhost:3003/health
```

In Bambuddy go to **Settings → Slicer** and set the sidecar URL to `http://<SERVER_IP>:3003` (OrcaSlicer) and `http://<SERVER_IP>:3001` (Bambu Studio).

Things to know:

- Ports **3000 and 3002** are reserved by Bambuddy's virtual-printer feature. That's why the OrcaSlicer sidecar publishes on 3003.
- If you use the `bambu` profile, you must pass `--profile bambu` on **every** compose command (pull, up, down), or that service is silently skipped.
- `docker exec -it bambuddy sh` puts you in the main Bambuddy container, not a sidecar. Use `orca-slicer-api` or `bambu-studio-api` as the container name for those.

## 3. Choose a desktop slicer

- **OrcaSlicer** is the better default here: native P2S profiles, open source, and it works well with Bambuddy's archiving.
- **Bambu Studio** gets fresher official profiles. Use **"Send with External storage"** rather than the plain Print button, or Bambuddy's archiving is bypassed.
- Bambuddy can act as a **virtual printer**, so your slicer can send files straight to it.

## 4. Wire it into Bambuddy

Bambuddy supports per-model start and end G-code snippets that can be toggled per queue item. This is where a fully local pipeline gets tricky, because the FarmBoard expects the processed file's markers to survive intact.

Injection happens **server-side in Python at print-dispatch time**, editing a temp copy of the `.gcode.3mf` — the original file is never touched. Your start snippet (Settings → Workflow → G-code Injection → P2S → start_gcode) is spliced in **after** the printer's own homing/heat/prime already ran; your end snippet is spliced in **after** the printer's entire stock end sequence, including its final `M18` (steppers off). Both of those facts drove real fixes in this repo's own snippet files — see [../gcode-snippets/GCODE-HOWTO.md#10-how-bambuddy-actually-inserts-these-snippets](../gcode-snippets/GCODE-HOWTO.md#10-how-bambuddy-actually-inserts-these-snippets) for the full mechanism (verified against Bambuddy source, commit `9e9c08b`), including why the start snippet has no `G28` and the end snippet opens with `M17`.

One more thing worth knowing: **injection failure is silent** — an exception or bad snippet just falls back to printing the original, un-injected file, with only a server-side log line to tell you. If the ejection cycle doesn't fire, check Bambuddy's logs before assuming the G-code itself is wrong.

The actual snippet files (fan channel swap, cooldown timing, sweep height math) live in [../gcode-snippets/README.md](../gcode-snippets/README.md) — read that before writing your own injection block.
