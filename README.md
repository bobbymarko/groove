# Groove

A structured-workout trainer app for indoor cycling: load a workout, let it drive your smart trainer in ERG mode, and ride a pixel-art mountain-bike trail whose hills follow your intervals. Rides are saved as FIT files and can be posted to intervals.icu and Strava. Built with Godot 4.7 and GDScript; macOS first, cross-platform by design.

Working title. Product owner: Bobby Marko. The code is written by Claude following the AI-native SDLC playbook: `intent.md` says why, `spec.md` says what (requirements, architecture, milestones, decisions), `Design.md` says how it looks.

## What it does
- Opens `.zwo`, `.mrc`, `.erg` and FIT workout files, and shows your planned workouts from the intervals.icu calendar by day.
- Controls a Bluetooth FTMS trainer (tested on a Wahoo KICKR CORE) and reads a heart-rate strap, reconnecting after dropouts.
- Ride HUD with the plan drawn as a single coloured "groove", live metrics, a coach who reads the workout's text cues, and keyboard shortcuts.
- A procedural world with six scenes (Winter, Summer, Autumn, Spring, Desert, Birchwood), a day/night cycle that runs at four times real time, weather, tyre marks and dust.
- Records rides to FIT with power, cadence, heart rate and speed; summary with NP, IF, TSS, kcal and pizza slices; sharing to intervals.icu and Strava with a confirmation step; screenshots saved for manual posting.

## Running it
Requirements: macOS with Godot 4.7.2, a Rust toolchain for the Bluetooth extension, and a Bluetooth smart trainer for real rides (a simulator is built in).

```bash
tools/build-gdble.sh          # Bluetooth GDExtension, built from source once
tools/fetch-quaternius.sh Pine_1 Pine_2 Pine_3 Pine_4 Pine_5 Rock_Medium_1 Rock_Medium_2 Rock_Medium_3 DeadTree_1 DeadTree_2 DeadTree_3 DeadTree_4 DeadTree_5 Bush_Common CommonTree_1 CommonTree_2 CommonTree_3 CommonTree_4 CommonTree_5 TwistedTree_1 TwistedTree_2 TwistedTree_3 Bush_Common_Flowers Grass_Common_Tall Grass_Wispy_Tall Flower_3_Group Flower_4_Group Mushroom_Common
tools/fetch-quaternius-un.sh Cactus_1 Cactus_2 Cactus_3 Cactus_4 Cactus_5 CactusFlowers_2 CactusFlowers_3 CactusFlowers_4 CactusFlowers_5 PalmTree_1 PalmTree_2 PalmTree_3 PalmTree_4 Rock_1 Rock_2 Rock_3 Rock_4 Rock_5 Rock_6 Rock_7 BirchTree_1 BirchTree_2 BirchTree_3 BirchTree_4 BirchTree_5 Willow_1 Willow_2 Willow_3 Plant_1 Plant_2 Plant_3 TreeStump WoodLog Grass Flowers BushBerries_1
tools/run-dev.sh              # launches a patched Godot copy that macOS lets use Bluetooth
```

On macOS, Godot itself cannot open Bluetooth without a usage description in its bundle, so `tools/make-dev-runner.sh` builds a patched copy in `build/GrooveDev.app` and `run-dev.sh` launches it. Details in `docs/dev-setup.md`.

Connectors are configured in Settings: an intervals.icu personal API key, and your own Strava API application (client ID and secret, callback domain `localhost`). Secrets are stored encrypted in the app's user folder and never leave the machine except to those services.

## Developing
```bash
tools/test.sh                                             # 91 headless unit tests
tools/shot.sh res://ui/screens/home_screen.tscn build/home.png          # render a screen to a PNG
tools/shot.sh res://ui/screens/ride_screen.tscn build/ride.png ride     # simulated ride with live HUD
tools/relaunch-dev.sh                                     # restart the dev app unless a ride is in progress
```

Layout: `core/` (workout model and parsers, telemetry, FIT), `devices/` (Bluetooth, FTMS, heart rate, simulators), `connectors/` (intervals.icu, Strava, upload queue), `scene/` (world, rider, weather, shaders, presets), `ui/` (screens, sheets, HUD, style), `tools/` (scripts), `tests/`.

Manual hardware test procedures are in `tests/manual.md`.

## Assets and licences
- Quaternius Stylized Nature MegaKit and Ultimate Nature Pack: CC0.
- Lato font: SIL Open Font License.
- Rider model from Mixamo (Adobe), used under the Mixamo terms; not redistributed here as an asset kit.
- The coach portrait and menu background are Bob's.

Project licence: not decided yet.
