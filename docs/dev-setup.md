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

## Bluetooth extension

`addons/gdble/` is GDBLE 0.5.5 (MIT), a Rust GDExtension over btleplug. Prebuilt
binaries for macOS, Windows, Linux, and Android are checked in. It is the only native
code in the project and is only referenced from `devices/ble/`.

## Verified hardware

| Device | Result | Date |
|---|---|---|
| Wahoo KICKR CORE ("KICKR CORE 3AA5") | FTMS control, power range 0–2000 W, ERG hold verified at 100/150/200 W, live power and cadence | 2026-09-02 |
