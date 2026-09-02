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
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1280x800 \
  -s tools/screenshot.gd -- res://ui/screens/ride_screen.tscn build/ride.png ride
```

## Riding on the simulator

Open the project in Godot and press Play, or run `tools/run-dev.sh`. Pick a workout,
set FTP, press "Ride on simulator". Keys on the ride screen: Space pause/resume,
Right skip segment, Up/Down bias ±1%, E toggle ERG, Esc end, F fast-forward (dev only).

## Bluetooth extension

`addons/gdble/` is GDBLE 0.5.5 (MIT), a Rust GDExtension over btleplug. Prebuilt
binaries for macOS, Windows, Linux, and Android are checked in. It is the only native
code in the project and is only referenced from `devices/ble/`.

## Verified hardware

| Device | Result | Date |
|---|---|---|
| Wahoo KICKR CORE ("KICKR CORE 3AA5") | FTMS control, power range 0–2000 W, ERG hold verified at 100/150/200 W, live power and cadence | 2026-09-02 |
