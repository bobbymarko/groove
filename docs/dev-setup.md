# Development setup (macOS)

## Requirements

- Godot 4.7 or newer: `brew install --cask godot`
- A Bluetooth LE trainer for hardware milestones. Everything else runs on the simulated trainer.

## Bluetooth from the editor

The stock Godot.app has no Bluetooth usage description in its Info.plist, so macOS
blocks CoreBluetooth and the GDBLE extension cannot see any devices. Build a patched
copy once and run the project through it:

```bash
tools/make-dev-runner.sh
tools/run-dev.sh
```

The first launch asks for Bluetooth permission for "RideDev". Allow it. Output goes to
`build/run.log`. `build/` is ignored by git.

Opening the project in the normal Godot editor is fine for everything that does not
touch Bluetooth.

## Tests and screenshots

```bash
tools/test.sh                      # headless unit tests (tests/unit/test_*.gd)
```

To eyeball a screen without clicking through the app:

```bash
tools/shot.sh res://ui/screens/ride_screen.tscn build/ride.png ride
```

This goes through the dev runner with `open`, which matters: macOS applies the Bluetooth
usage description only when the app is launched through LaunchServices. Executing
`RideDev.app/Contents/MacOS/Godot` directly still crashes with a TCC abort as soon as the
Devices autoload touches the radio.

## Riding on the simulator

Open the project in Godot and press Play, or run `tools/run-dev.sh`. Pick a workout,
set FTP, press "Ride on simulator". Keys on the ride screen: Space pause/resume,
S skip segment, Up/Down bias ±1%, E toggle ERG, Esc end, T tuning panel, F fast-forward (dev only),
Left/Right orbit the camera around the rider in 15° steps, 0 resets it.

## Rides, FIT files, and uploads

Rides are journalled one sample per second to `user://rides/<timestamp>.jsonl` (that is
`~/Library/Application Support/Godot/app_userdata/Ride/rides/` on macOS) and encoded to a
FIT file beside the journal when the ride ends. Unfinished journals are recovered on the
next launch. Uploads are queued in `user://uploads.cfg` and retried on launch; the
intervals.icu API key is stored encrypted in `user://secrets.cfg`.

`tools/make_test_fit.gd` writes a synthetic ride for checking that a service accepts our
FIT files.

## Scene

`scene/ride_scene.gd` renders the 3D world into a 240 px tall SubViewport and draws it
through `scene/post/pixel_post.gdshader` (dither, palette quantization, outlines). All
mesh geometry is built in code by `scene/world/mesh_lib.gd` with flat normals and vertex
colours from `scene/palette.gd`; Godot front faces are clockwise, which `MeshLib.tri`
handles. Preview the scene standalone:

```bash
tools/shot.sh x build/scene.png scene            # perspective, demo telemetry
tools/shot.sh x build/scene_top.png scene top    # top-down debug view
tools/shot.sh x build/scene.png scene nocull     # debug: cel shader without culling
```

## Assets (Quaternius, CC0)

Props come from Quaternius's Stylized Nature MegaKit (standard edition, CC0). The importer
keeps only base-colour textures, downscaled to 512 px. The cel shader does not use the
textures' hues: it reads their brightness and blends between two palette shades chosen by
material name (`MeshLib.shades_for_material`), then drops snow on upward-facing surfaces.
That is how the foliage gets its green-and-white mix while staying inside the palette. To add
models for another season:

```bash
tools/fetch-quaternius.sh                          # downloads/caches the kit, lists models
tools/fetch-quaternius.sh CommonTree_1 CommonTree_2 Bush_Common_Flowers
```

Files land in `assets/quaternius/`. Load one with `MeshLib.load_prop("res://assets/quaternius/Name.gltf")`
and add it to the variant lists in `scene/world/terrain_streamer.gd`. Model names in the kit:
Pine_1–5, CommonTree_1–5, TwistedTree_1–5, DeadTree_1–5, Rock_Medium_1–3, Pebble_*, Bush_*,
Grass_*, Flower_*, Plant_*, Mushroom_*, RockPath_*.

## Rider model

`assets/mixamo/Ch42_nonPBR.fbx` (Mixamo, embedded textures) is imported natively by Godot and
posed every frame by `scene/rider/mixamo_body.gd`: bones are reset to rest, the hips are placed
on the saddle with a forward lean, and two-bone IK aims thighs/shins to the pedals and
upper arms/forearms to the grips. Mixamo's Left limbs sit on +X, the bike's left is -X, so
the Rider hands the +X pedal and grip to the rig's Left side. Debug views:

```bash
tools/shot.sh x build/rider.png scene closeup          # three-quarter close-up, no post
tools/shot.sh x build/rider.png scene closeup lean=0.8 # try a different torso lean
```

## Bluetooth extension

`addons/gdble/` is GDBLE (MIT), a Rust GDExtension over btleplug. The macOS arm64
library is built from source at a pinned master commit, because the 0.5.5 release does
not report a device that disconnects on its own (unplugged trainer, strap out of range):

```bash
brew install rust        # once
tools/build-gdble.sh     # clones, builds, installs addons/gdble/libgdble.macos.arm64.dylib
```

The Windows, Linux, and Android binaries in `addons/gdble/` are still the 0.5.5 release
and must be rebuilt the same way when those platforms are tackled. It is the only native
code in the project and is only referenced from `devices/ble/ble_adapter.gd`. Everything
else in the device layer talks to the `BlePeripheral` abstraction, which `tests/fakes/`
implements in memory, so the FTMS handshake and reconnect logic are unit-tested.

Device roles are assigned from services: a peripheral with the Fitness Machine service
becomes the trainer, one with the Heart Rate service becomes the heart-rate sensor.
Paired devices are remembered in `user://devices.cfg` and auto-connected on launch.

"ERG off" sends FTMS simulation mode with a fixed grade (0–8 %), so the trainer feels
like a hill and power follows cadence and gear.

## Verified hardware

| Device | Result | Date |
|---|---|---|
| Wahoo KICKR CORE ("KICKR CORE 3AA5") | FTMS control, power range 0–2000 W, ERG hold verified at 100/150/200 W, live power and cadence. Indoor Bike Data flags 0x0044 (speed, cadence, power). Cadence is the trainer's own estimate and reads ~0 when the cassette is turned by hand rather than pedalled. Remote disconnect + rescan reconnect verified. | 2026-09-02 |
| Wahoo TICKR ("TICKR 4D4A") | Heart Rate service, pairs and auto-connects | 2026-09-02 |
