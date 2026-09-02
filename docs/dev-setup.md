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
Right skip segment, Up/Down bias ±1%, E toggle ERG, Esc end, F fast-forward (dev only).

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
| Wahoo KICKR CORE ("KICKR CORE 3AA5") | FTMS control, power range 0–2000 W, ERG hold verified at 100/150/200 W, live power and cadence | 2026-09-02 |
