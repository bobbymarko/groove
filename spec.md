# Spec: Ride — requirements and design

**Input:** `intent.md` (approved 2026-09-02)
**Author:** Claude, with Bob Marko as product owner
**Date:** 2026-09-02
**Status:** Approved by product owner, 2026-09-02
**Stage:** 2 — Design (AI-native SDLC)

This document turns the intent into a buildable design. It records what the first version must do, how it is structured, what is deliberately deferred, and the concerns that need a decision before or during the build. It is paired with `intent.md`; where the two disagree, fix the intent first.

---

## 1. Scope

### 1.1 First version (v1, Mac)

A rider can do this end to end with no other software:

1. Open the app, pair a Wahoo KICKR CORE and a heart-rate strap over Bluetooth.
2. Set their FTP.
3. Load a `.zwo` workout file.
4. Ride it. The trainer holds target power in ERG mode. The HUD shows the interval plan, time, target and actual power, cadence, and heart rate. A winter mountain-bike trail scene plays with a handheld camera.
5. Finish. The ride is saved as a FIT file on disk and uploaded to intervals.icu. The FIT file is imported into COROS, which forwards it to Strava.

### 1.2 Explicitly deferred

| Deferred | Target |
|---|---|
| Windows build | v1.1, once Mac is stable. Same codebase. |
| Other seasons and workout-reactive scene | v1.1 |
| Terrain that follows the workout: hard intervals climb, recoveries descend | v1.1, part of the reactive scene (Bob, 2026-09-02) |
| Spoken coach notes: text events read aloud with text-to-speech | Later (Bob, 2026-09-02) |
| COROS direct upload | When COROS grants API access. Fallback in 4.5. |
| Garmin, Wahoo, TrainingPeaks, intervals.icu connectors | Later |
| `.fit`, `.erg`, `.mrc` workout import; pulling workouts from services | Later |
| ANT+ and non-FTMS trainers | Later |
| Free-ride mode with no workout | Later, cheap once the engine exists |
| iOS and Android | Later; architecture must not block them |
| Accounts, cloud sync, backend | Not planned |

---

## 2. Requirements

### 2.1 Functional

**Devices**
- R1. Scan for and connect to Bluetooth LE trainers exposing the Fitness Machine Service (FTMS), and to heart-rate, cycling-power, and speed/cadence sensors.
- R2. Control trainer resistance in ERG mode: set a target power in watts and have the trainer hold it.
- R3. Read power, cadence, and heart rate at least once per second while riding.
- R4. Remember paired devices and reconnect automatically on launch and after a dropout, without ending the ride.
- R5. Provide a simulated trainer so the full app runs with no hardware. Required for development and automated tests.

**Workouts**
- R6. Parse Zwift `.zwo` files: `Warmup`, `Cooldown`, `SteadyState`, `IntervalsT`, `Ramp`, `FreeRide`, `MaxEffort`, and `textevent`. Power values are fractions of FTP and are scaled by the user's FTP.
- R7. Run the workout as a timeline: current segment, time remaining in segment and workout, target power at every second (ramps interpolate).
- R8. Ride controls: start, pause, resume, skip to next interval, adjust workout intensity up or down in steps (Zwift calls this bias), toggle ERG off to ride an interval on resistance mode, end early.
- R9. Show text events at their scheduled time.

**Ride display (HUD)**
- R10. Show the whole workout as a bar graph of segments with a playhead, plus the current and next segment.
- R11. Show target power, actual power (3-second smoothed), cadence, heart rate, elapsed and remaining time, and interval countdown, readable from a bike two meters away.
- R12. Show a compliance cue: actual versus target power, colored by how close the rider is.

**Scene**
- R13. Render a procedural mountain-bike trail in a pixel-art style matching `game-aesthetic.mp4`: low internal resolution, limited palette, outlines, falling snow, pines, layered mountains.
- R14. Third-person camera behind a rider on a bike, with a handheld feel. Rider pedals at the measured cadence, wheels turn, and the rider leans through turns.
- R15. Scene runs at a steady 60 frames per second on any Apple silicon Mac and does not interfere with device timing.

**Recording and sync**
- R16. Record a sample every second: timestamp, power, cadence, heart rate, target power, and segment index.
- R17. Journal samples to disk during the ride so a crash or power loss loses at most a few seconds.
- R18. On finish, write a FIT activity file and show a summary: duration, average and normalized power, average heart rate, kilojoules, intensity factor, and training stress score.
- R19. Connectors: intervals.icu (personal API key) and Strava (user's own API app, OAuth in the browser with a loopback redirect, token refresh, FIT upload with processing poll). When a ride ends, the summary screen asks which connected services to post to; uploads go through a retry queue. Screenshots are captured at the hardest interval and at the finish and saved beside the FIT for manual posting, because Strava's API accepts photos only from partner apps. (Bob took a Strava subscription 2026-09-03 after confirming COROS does not forward imported rides.)
- R20. Keep all ride files in a local library the user can open in Finder.

**Settings**
- R21. FTP, weight, units, Strava connection, paired devices, camera shake (off, low, high), scene options.
- R22. Planned workouts: with an intervals.icu key set, the home screen fetches the next 14 days of Ride workouts from the athlete's calendar (one request, .zwo files come base64-encoded in the event list), caches them under `user://intervals/`, and shows them by day: Today first and highlighted, then Tomorrow and named days, then the local library. Runs, notes and races are skipped. The list refreshes on the home screen when older than five minutes; a fetch failure keeps the cached list and says so. (Bob, 2026-09-03.)
- R23. Home-screen sheets: Settings (Rider & sync / Look pages as cards), Devices (trainer and heart-rate cards side by side), Recent rides (list with a power-trace thumbnail per ride; a ride opens in place with a back arrow: trace with HR, metrics, sharing state, screenshots, Share and Finder buttons). The workout sheet shows the .zwo description as a note from the coach, avatar beside a speech bubble. (Bob, 2026-09-03.)
- R24. Workout files: .zwo, .mrc and .erg (CompuTrainer/TrainerRoad course text; .erg watts use the file's FTP or the rider's), and FIT workout files (messages 26/27, repeats expanded, power targets in % FTP, watts or zone; heart-rate and cadence steps become free ride). `WorkoutLoader` dispatches by extension. (Bob, 2026-09-03.)
- R25. Scenes: before a ride starts, a "Choose a scene" step in the workout sheet offers Winter, Summer, Autumn and Spring. A `ScenePreset` recolours the palette (sky, ground, trail, mountains, foliage), selects the Quaternius props to scatter (pines, common trees, twisted trees, dead trees, grass, flowers, mushrooms), lifts the sun, and turns snowfall and snow-on-props on or off. The choice is remembered. (Bob, 2026-09-03.)

### 2.2 Non-functional

- N1. **Never lose a ride.** Device dropouts, app crashes, and upload failures must not lose recorded data.
- N2. **ERG responsiveness.** A new target reaches the trainer within one second of the segment change.
- N3. **Local only.** No server owned by this project. All data stays on the user's machine. Connector tokens are stored encrypted.
- N4. **Portable core.** No platform-specific code outside the device adapter and packaging. GDScript everywhere else.
- N5. **Testable without hardware.** Every layer above the Bluetooth adapter is exercised by automated tests using the simulated trainer.
- N6. **Distributable.** The Mac build is signed and notarized so it opens without warnings.

---

## 3. Architecture

Godot 4.7 (latest stable), GDScript, Compatibility renderer. One Godot project. The Bluetooth layer is the only native code.

```
ride/
  project.godot
  core/
    workout/     zwo parser, Workout model, WorkoutRunner (timeline + controls)
    telemetry/   RideRecorder (1 Hz samples, disk journal), Metrics (NP, IF, TSS)
    export/      FitEncoder
  devices/
    interfaces/  Trainer, PowerSensor, CadenceSensor, HeartRateSensor
    ble/         BleAdapter (wraps GDBLE), profiles: FTMS, CPS, CSC, HRM
    sim/         SimulatedTrainer, SimulatedHeartRate
    DeviceManager  scan, pair, remember, reconnect
  connectors/
    Connector interface, StravaConnector (OAuth + upload), UploadQueue
  ui/
    screens: Home, Devices, Settings, Ride, Summary
    hud/     WorkoutGraph, PowerDial, Metrics
  scene/
    world/     TerrainGenerator, TrailSpline, Scatter (trees, rocks), Weather
    rider/     Rider (low-poly), PedalIK, Lean
    camera/    HandheldCamera
    post/      PixelViewport, palette + dither + outline shaders
    seasons/   palette and weather presets (winter only in v1)
  addons/
    gdble/     third-party Bluetooth extension
  tests/       gdUnit4 tests
```

### 3.1 Layer rules

- `core` depends on nothing else in the project. It is plain data and logic.
- `devices/interfaces` are abstract classes. `ble` and `sim` implement them. Nothing outside `devices` imports GDBLE.
- `ui` and `scene` consume signals from `WorkoutRunner` and `DeviceManager`. They never talk to devices directly.
- `connectors` consume a finished FIT file and a token store. They know nothing about rides in progress.

### 3.2 Device layer

The trainer interface is small on purpose. Anything that implements it works with the rest of the app.

```
Trainer
  signals: connected, disconnected, power(watts), cadence(rpm), speed(kph), status(dict)
  connect(), disconnect()
  set_target_power(watts)        ERG
  set_resistance(level)          resistance mode (ERG off)
  supported_power_range() -> (min, max)
```

FTMS mapping used by the Bluetooth implementation:

| Purpose | Service | Characteristic |
|---|---|---|
| Trainer telemetry (power, cadence, speed) | Fitness Machine 0x1826 | Indoor Bike Data 0x2AD2 (notify) |
| Trainer control | 0x1826 | Control Point 0x2AD9 (write, indicate) |
| Trainer status | 0x1826 | Machine Status 0x2ADA (notify) |
| Power limits | 0x1826 | Supported Power Range 0x2AD8 (read) |
| Power meter | Cycling Power 0x1818 | Measurement 0x2A63 (notify) |
| Cadence sensor | Speed and Cadence 0x1816 | Measurement 0x2A5B (notify) |
| Heart rate | Heart Rate 0x180D | Measurement 0x2A37 (notify) |

Control point sequence: Request Control (0x00), then Start (0x07), then Set Target Power (0x05, signed 16-bit watts) on every target change. Every write waits for the indication response before the next write.

The Bluetooth adapter wraps GDBLE's `BluetoothManager` and `BleDevice` behind six calls: scan, connect, discover, subscribe, read, write. GDBLE's `ble_event` signal is demultiplexed into per-characteristic callbacks. Only this file changes when the extension changes or an iOS adapter is added.

### 3.3 Workout engine

`Workout` is a list of segments, each with a duration and a power function of time (constant or linear ramp), optional cadence target, and optional text events. `IntervalsT` expands into alternating segments. `FreeRide` segments have no target and put the trainer into resistance mode.

`WorkoutRunner` is a state machine (`idle`, `ready`, `running`, `paused`, `finished`) driven by a one-second tick. Each tick it computes target power from the timeline, the user's FTP, and the current bias, emits `target_changed` when it differs from the last one, and emits `segment_changed` and `text_event` as they occur. Controls in R8 mutate the timeline position or the bias.

### 3.4 Recording and FIT

`RideRecorder` subscribes to the runner and the devices, samples once per second, and appends each sample as a line to a journal file in `user://rides/<id>.jsonl`. On finish, `FitEncoder` reads the journal and writes a FIT activity: file header, `file_id`, `device_info`, `event` start, one `record` per sample, `event` stop, `lap`, `session` (sport cycling, sub-sport virtual activity, so Strava tags it as a Virtual Ride like Zwift does), `activity`, and the CRC. If the app is relaunched with an unfinished journal, it offers to recover the ride.

FIT is written by hand in GDScript. It is a well-documented binary format and the activity subset is small. Output is validated in tests against the reference FIT SDK's CSV tool.

### 3.5 Strava connector

Desktop OAuth: the app opens the Strava authorization page in the system browser, listens on a loopback port with Godot's `TCPServer` for the redirect, exchanges the code for tokens, and stores them encrypted in `user://`. Scope `activity:write`. Upload is a multipart POST to the uploads endpoint with `data_type=fit`, then polling the upload status. Failures go into a persisted queue retried on launch and on demand. See concern C2 on the client secret.

### 3.6 Scene and rendering

- **Pixel pipeline.** The 3D world renders into a `SubViewport` at a fixed internal height of 240 pixels (width follows the window aspect). It is drawn to the window with nearest-neighbor scaling at an integer factor where possible. A post-process shader quantizes to a per-season palette of roughly 24 colors, applies ordered dithering on gradients, and draws single-pixel outlines from depth and normal edges. Lighting is two-band cel shading with flat colors and no textures.
- **World.** A heightmap from layered noise, with a trail carved along a spline that meanders and climbs. Trees, rocks, and stumps are scattered as instanced low-poly meshes with density by slope and distance from the trail. Terrain streams ahead of the rider in chunks and is recycled behind. Snow is a particle system; ground snow is a shader layer.
- **Rider.** A low-poly rider and bike built from primitives, about 40 internal pixels tall on screen. Wheels and cranks rotate with measured cadence. Legs follow the pedals with `SkeletonIK3D`. The rider leans with trail curvature. Speed along the trail comes from power via a simple physics model so harder intervals visibly move faster.
- **Camera.** Third-person follow camera with layered noise on position and rotation for the handheld feel, tuned so it reads as lively and never as nauseating. The user chooses one of three shake levels: off, low, or high. The amplitude behind each level is tuned during development and is not user-editable.
- **Seasons.** A season is a palette, a weather preset, a scatter preset, and a ground shader preset. Winter ships in v1; the data structure is in place so spring, summer, and autumn are content, not code.
- **Reactivity (v1.1).** Hooks exist from day one for gradient, speed, and camera amplitude to respond to power and interval type. Only speed is wired in v1. The intended design: the trail's grade tracks the workout, so a hard interval is a climb and a recovery is a descent. The terrain generator should therefore take the upcoming target profile as input, not just noise.
- **Spoken coach notes (later).** Text events are read aloud with text-to-speech, using the OS voices Godot exposes through `DisplayServer.tts_*`, with an on/off setting.

### 3.7 UI flow

Home (workout library, recent rides, device status) → Devices (scan, pair, forget) → Ride (scene full-screen, HUD overlay) → Summary (metrics, upload status, open file) → back to Home. Settings is reachable from Home.

---

## 4. Concerns flagged for decision

- **C1. Resolved 2026-09-02.** Milestone 0 drove the KICKR CORE from macOS through GDBLE: FTMS control granted, ERG targets acknowledged and felt, live power and cadence received. The stack stands.
- **C9. Strava's API now requires a paid Strava subscription (found 2026-09-02).** Since June 2026 the standard developer tier needs an active Strava subscription (about $12/month), which undercuts the point of replacing a $20 Zwift subscription. Strava is therefore no longer a direct launch connector. **Update 2026-09-03:** COROS did not forward the imported ride to Strava, so Bob subscribed to Strava and a direct Strava connector was built (see R19). **Decided 2026-09-02:** intervals.icu is the first automatic connector (free open API, personal API key, direct FIT upload). Every ride is also saved as a FIT file for import into the COROS app; Bob has COROS→Strava sync enabled, so a ride that reaches COROS reaches Strava. The COROS partner API application makes that step automatic later. intervals.icu confirms it cannot push to Strava itself, and its "keep Strava in sync" option only matches rides that already exist on Strava.
- **C2. Strava has no PKCE, so token exchange needs a client secret.** (Moot for launch if C9 removes Strava as a direct connector.) Shipping the secret inside a desktop binary is common practice for indie apps but is extractable. The alternative is a tiny stateless token-exchange function hosted somewhere, which is a backend in miniature. Recommendation: ship the secret in v1 for personal use, decide before public release.
- **C3. New Strava API apps are limited to one connected athlete.** Fine for personal use. Public release requires requesting a capacity increase from Strava, which takes review time. Start that request early.
- **C4. COROS inbound sync requires partner API approval.** COROS accepts applications through a form and grants OAuth access to platforms meeting their requirements. Submit early. Until approved, COROS support means the user imports the FIT file through the COROS app manually, which COROS supports.
- **C5. macOS Bluetooth permission and notarization.** Confirmed during milestone 0: the stock Godot editor has no Bluetooth usage description, so development runs through a patched copy built by `tools/make-dev-runner.sh` (see `docs/dev-setup.md`). Exported builds must set the usage description in the export preset. Distribution outside the App Store requires a Developer ID and notarization.
- **C6. Token storage.** Godot has no keychain access. Tokens will be encrypted with a key derived from a per-install secret stored in `user://`. This is adequate for v1 and weaker than the OS keychain. A native keychain shim is a later improvement.
- **C8. GDBLE 0.5.5 does not report remote disconnects.** Found in the milestone 2 hardware test: unplugging the trainer produced no event, because the 0.5.5 release only emits `disconnected` for disconnects it initiated. Mitigation shipped: the trainer and heart-rate profiles run a data watchdog (6 s and 10 s of silence respectively) and treat silence as a dropout, which also protects against any future backend with the same gap. Resolved the same day by building GDBLE from source at master commit 65f03b3 (`tools/build-gdble.sh`), which reports radio-level disconnects. The watchdog stays as a safety net for other backends.
- **C7. iOS Bluetooth adapter.** GDBLE does not build for iOS, though the library beneath it does. Options when iOS arrives: an iOS build of GDBLE, SwiftGodot with CoreBluetooth, or SimpleBLE (commercial license terms to check). No decision needed now; the adapter boundary keeps it contained.

---

## 5. Milestones

Riskiest first. Each milestone ends with something that runs.

| # | Milestone | Done when |
|---|---|---|
| 0 | **Bluetooth spike** ✅ 2026-09-02 | A bare Godot scene connects to the KICKR CORE via GDBLE on the Mac, prints live power and cadence, and holds 150 W then 200 W in ERG. Go/no-go for the stack. **Passed.** Spike lives in `spike/`; the KICKR also exposes Cycling Power (0x1818) and Wahoo's proprietary service, neither needed. |
| 1 | **Engine on simulator** ✅ 2026-09-02 | Load a `.zwo`, ride it against the simulated trainer with a text-only HUD. All R6 to R9 controls work. Tests cover the parser and runner. **Done.** 27 unit tests pass headless via `tools/test.sh`. Fixture is Bob's real "Cadence: Corner Exit" workout. |
| 2 | **Real devices** ✅ 2026-09-02 | Pairing screen, real trainer and heart-rate strap, auto-reconnect, dropout does not end the ride. Device layer: `BleAdapter` (only GDBLE user), `BlePeripheral` abstraction with a test fake, `FtmsTrainer`, `BleHeartRate`, `Devices` manager with remembered devices. 24 new tests. Manual procedure in `tests/manual.md`. **Passed on KICKR CORE + TICKR:** pairing, auto-connect on launch, and an unplug mid-ride recovered in a few seconds via rescan and reconnect. Required building GDBLE from source (C8) and three reconnect fixes found only on hardware. |
| 3 | **Record and upload** 🔄 built 2026-09-02, awaiting real-ride test | Journal, FIT export, summary screen, intervals.icu API key and upload with retry, rides folder for COROS import. First real workout ridden and posted to intervals.icu; FIT imported into COROS and seen on Strava. Built: `RideRecorder` (1 Hz JSONL journal, crash recovery), `RideMetrics` (NP/IF/TSS), `FitEncoder` (hand-rolled, verified by an independent reader in tests), `IntervalsConnector`, `Sync` upload queue, summary and settings screens. 16 new tests. |
| 4 | **Scene v1** ✅ 2026-09-02 (look approved by Bob; leg animation and a frame-rate check remain as polish) | Winter trail, rider pedaling at real cadence, handheld camera, pixel post-process. 60 fps. HUD overlaid on the scene. Built: 240 px SubViewport + palette/dither/outline shader; chunked flat-shaded terrain with trail carve and MultiMesh props; Trail grade driven by upcoming workout targets (hard efforts climb, recoveries descend, already wired); primitive rider with crank/wheel animation, leg IK and lean; trail-anchored handheld camera with off/low/high; CPU snow; far ridges. Lesson: Godot front faces are clockwise, MeshLib emits accordingly. Props are Quaternius CC0 models (pines, dead trees, rocks) recoloured by the palette shader with normal-based snow; `tools/fetch-quaternius.sh` pulls more for other seasons. Rider is Bob's Mixamo character (assets/mixamo/Ch42_nonPBR.fbx, ~50k tris) posed on the procedural bike by per-frame IK (MixamoBody: hips on saddle, spine lean, legs to pedals, arms to grips), clothes colourized to the palette; block rider remains as fallback when the FBX is absent. Look decisions from review: no outlines, no dither (flat colour, smoother motion), hard shadows from a 10° sun, groomed 1.5 m groove trail, five unlit mountain layers, exaggerated grades (threshold ≈ 14 %). Scene tuning sliders live in Settings and under T on the ride screen; Bob's values are the defaults. |
| 5 | **Polish and ship Mac** | Settings, library, workout graph HUD, signed and notarized build. Cancel Zwift. |
| 6 | **Windows** | Same project exported to Windows, Bluetooth verified on one Windows machine. |
| 7 | **Seasons and reactivity** 🔄 presets built 2026-09-03 | Spring, summer, autumn presets (see R25; Bob to review the looks). Gradient and camera respond to intervals. |

---

## 6. Testing and feedback loop

- Unit tests run headless with `tools/test.sh`. Milestone 1 shipped a 60-line in-repo runner (`tests/run_tests.gd`, `tests/test_case.gd`) instead of gdUnit4 to avoid a dependency download; swap to gdUnit4 if the suite outgrows it.
- The simulated trainer makes the full ride flow testable: parser, runner, recorder, FIT output, upload queue.
- Golden files: known `.zwo` inputs with expected target-power timelines; FIT outputs decoded by the FIT SDK CSV tool and compared to expected samples.
- Manual test script for hardware milestones, kept in `tests/manual.md`.

---

## 7. Open questions carried forward

From the intent, still open and not blocking v1: platform order after Windows, workout formats beyond `.zwo`, scene reactivity design, free-ride mode, distribution and price, the exact Zwift parity list, the iOS adapter choice.

Decided during review (2026-09-02):
- Rides are always tagged as Virtual Ride in the FIT file. No setting.
- Camera shake is a three-level user setting: off, low, high. The amplitudes behind low and high are tuned by the team while riding.

New from this spec, still open:
- Whether v1 needs a cadence sensor separate from the trainer. The KICKR CORE reports cadence itself, so proposed: no.
