# Spec: Groove — requirements and design

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
- R21. FTP, weight (kg or lbs; the unit choice also switches the HUD to mph and miles), Strava connection, paired devices, scene options. Rider weight plus a 14 kg fat bike is the mass in the speed model, so speed for a given power follows W/kg. (Camera shake setting removed 2026-09-03: Bob never turned it on and found it annoying. The 8-bit palette filter was removed the same day for looking broken; the pixel look is the posterized mode, on or off.)
- R22. Planned workouts: with an intervals.icu key set, the home screen fetches the next 14 days of Ride workouts from the athlete's calendar (one request, .zwo files come base64-encoded in the event list), caches them under `user://intervals/`, and shows them by day: Today first and highlighted, then Tomorrow and named days, then the local library. Runs, notes and races are skipped. The list refreshes on the home screen when older than five minutes; a fetch failure keeps the cached list and says so. (Bob, 2026-09-03.)
- R23. Home-screen sheets: Settings (Rider & sync / Look pages as cards), Devices (trainer and heart-rate cards side by side), Recent rides (list with a power-trace thumbnail per ride; a ride opens in place with a back arrow: trace with HR, metrics, sharing state, screenshots, Share and Finder buttons). The workout sheet shows the .zwo description as a note from the coach, avatar beside a speech bubble. (Bob, 2026-09-03.)
- R24. Workout files: .zwo, .mrc and .erg (CompuTrainer/TrainerRoad course text; .erg watts use the file's FTP or the rider's), and FIT workout files (messages 26/27, repeats expanded, power targets in % FTP, watts or zone; heart-rate and cadence steps become free ride). `WorkoutLoader` dispatches by extension. (Bob, 2026-09-03.)
- R25. Scenes: before a ride starts, a "Choose a scene" step in the workout sheet offers Winter, Summer, Autumn and Spring. A `ScenePreset` recolours the palette (sky, ground, trail, mountains, foliage), selects the Quaternius props to scatter, lifts the sun, and turns snowfall and snow-on-props on or off. The choice is remembered. Props come from two CC0 Quaternius packs: the Stylized Nature MegaKit (glTF, `tools/fetch-quaternius.sh`) and the Ultimate Nature Pack (OBJ, `tools/fetch-quaternius-un.sh`, fetched via itch.io's free-download handshake). Desert (cactus, palms, red rock, sparse) and Birchwood (birches, willows, stumps, berry bushes) were added 2026-09-04 from the second pack. (Bob, 2026-09-03.)
- R26. Time of day: the world day runs four times faster than the real one (a one-hour ride sees four hours of light). `Daylight` places the sun on an arc (noon height and direction come from the tuning sliders plus the preset's lift), warms it near the horizon, and hands over to a blue moon at night with darker sky, fog and ambient and softer shadows; the bike's bar light (a spot from the stem) comes on as daylight fades. Showers: presets carry a rain chance (spring 40 %, autumn 25 %, summer 10 %) rolled per eight-minute wall-clock window; rain greys the sky, dims the sun and thickens the fog. Settings → Look offers Live, Morning, Noon, Sunset, Night. (Bob, 2026-09-03.)
- R27. Ride detail: tyre marks fade behind the rear wheel; dust (dirt) or spray (snow) puffs up while rolling; the rider stands with one foot down when stopped and does not roll without power; the ride opens with the world fading in, then the HUD. (Bob, 2026-09-03.)
- R28. Apocalypse scene: ash ground, dead wood, rust sky. A horde spawns ahead at a rate that follows the target effort (nothing below 60 % FTP, about one every two seconds at threshold, nearly two a second at VO2), shambles toward the rider (running on hard blocks), and on contact is flung with a ballistic tumble scaled by speed and power, bounces on the terrain and dissolves. The rider kicks on each hit; kills show next to the reps counter. Model: "Animated Zombie" by Quaternius, CC BY 3.0 (attribution in assets/zombie/ATTRIBUTION.txt and the README). Power-ups: finishing a hard interval drops the next weapon on the trail 22 m ahead (baseball bat, machete, chainsaw); riding through it arms the rider, who swings instead of kicking, and each tier adds knock-back. Hits burst green blood, more and bigger drops per weapon tier, and the camera swings to the side and closes in for about a second. Zombies more than 14 m behind the rider are freed so the horde never dries up. (Bob, 2026-09-04.)
- R29. Library management: uploaded workouts carry a three-dot menu with Ride (straight to the scene picker) and Delete; Delete asks first and then moves the file to `user://workouts/deleted/` rather than erasing it. Bundled and calendar workouts have no menu. Without an intervals.icu key the Training plan area shows an onboarding card that points to Settings. (Bob, 2026-09-04.)
- R30. Bundled library: eight Groove-authored workouts ship with the app (Recovery Spin 30, Endurance 60, Sweet Spot 2x20, Threshold 3x10, VO2 5x4, Over-Unders 3x9, Tabata Sprints, Ramp Test), each with coach cues. The Library puts the Upload tile first and has a filter menu (duration under 30 / 30–60 / over 60; uploaded / bundled). Section titles on the home screen use display type so they sit above the day labels. (Bob, 2026-09-04.)
- R32. Distribution: public repo https://github.com/bobbymarko/groove (MIT); release v0.0.1 is a universal macOS zip exported with the macOS preset (ad-hoc signed, not notarized; Gatekeeper needs right-click Open). Export requires the Godot 4.7.2 templates and ETC2/ASTC import enabled. (2026-09-04.) `tools/release.sh <version>` exports both platforms and zips them; v0.0.2 (2026-09-08) adds auto-pause, Devices mid-ride, background rescan and the pixel-stable camera, with Bob's dither 0.03 and speed blur 0 as defaults.
- R33. Auto-pause (default on, Settings → Ride): while the workout runs, three seconds of zero watts pause it, and the first watts after that resume it; Start with a trainer reading zero waits at 0:00 for the pedals. A trainer silent for five seconds counts as zero. A manual Pause stays paused whatever the pedals do. Off for the simulator, which has no pedals to stop. Mirrors Zwift, where the workout stops when the rider stops. The coach shows "Start pedalling when you're ready" / "Paused. Pedal to carry on." (2026-09-08, from Bob's first week of riding.)
- R34. Devices mid-ride: the ride controls bar has a Devices button (also D) that opens the same Devices sheet as home over the running ride; the connection warning line is clickable too. Escape closes the sheet and never ends the ride while it is open. Background rescan: a remembered device that has not connected (strap put on late) is looked for again every 15 s for as long as the app runs, except while the simulator is chosen. (2026-09-08.)
- R35. Pixel stability: the low-res frame is drawn at a whole number of screen pixels per texel (factor chosen from the Render height slider), the camera's yaw and pitch are snapped to the texel grid before rendering, and the frame is shifted on screen by the sub-texel remainder (2-texel margin). Position is not snapped: in perspective a position step moves each depth by a different amount, so the 2D shift cannot undo it and the near ground jerked (Bob, 2026-09-08). MSAA 4× on the low-res viewport and a soft shadow edge stop thin branches and shadow bands flickering. Adapted from the 2D pixel-perfect smooth camera technique Bob researched. (2026-09-08.)
- R36. Updates: the app knows its version (`application/config/version` in project.godot, checked against the export presets by `tools/release.sh`). Autoload `Updates` asks GitHub's releases API for the latest release at most once a day (cached in user://updates.cfg; Settings → About has Check now). A newer release shows "Update to x.y.z" in the home footer, which opens the Update sheet with the release notes. macOS installs in-app: download the release zip to user://updates, verify GitHub's sha256 digest for the asset, unpack with ditto, move the running Groove.app to Groove.previous.app, move the new one into place, relaunch with `open -n`, and delete Groove.previous.app on the next start. Refused (with a download link instead) when not running from a Groove.app bundle, when App Translocation is active, or when the folder is not writable. Windows and Linux get a "Download from GitHub" button. Dev: `-- version=0.0.1` pretends to be older, `-- update=install` runs the update unattended. (2026-09-08.)
- R37. Cadence targets: read from .zwo (`Cadence`, `CadenceResting`, or a `CadenceLow`/`CadenceHigh` range at its middle) and from FIT workouts (cadence as the step's main or secondary target; a cadence-only step is ridden as a free ride at that rpm). The current-block box shows "AT 95 RPM"; live cadence turns green within 5 rpm of the target and orange outside it; block rows in the HUD and workout sheet end in the rpm. Each recorded second carries the target (`ct`), and the summary and ride detail show the share of targeted time spent on cadence. The simulator pedals at the target. A chosen simulator is no longer replaced by a remembered trainer that turns up during the start-up search. (Bob, 2026-11-02.)
- R38. Auto-start: with auto-pause on (R33), a workout waiting at Ready starts by itself on the first watts from the trainer, so getting on the bike and pedalling is enough; the coach shows "Start pedalling when you're ready." until then. Off, and on the simulator, only Start starts it. Mirrors Zwift. (Bob, 2026-11-20, after riding a few times without pressing Start.)
- R39. Realistic look (trial, `graphics` branch): Settings → Look offers Pixel, Smooth and Realistic. Realistic switches the renderer to Godot's Forward+ and rides in first person (eyes over the bars, a bar light at night; the view never sways or rolls: it turns slowly toward where the next 30 m of trail goes, so bends and bumps do not rock the screen — Bob found any sway made him motion sick, 2026-11-21). The sky and clouds are ported from Cloudscape (MIT): a physically based atmosphere and raymarched volumetric clouds, sunrise to moonlit night with stars. Trees (spruce, broadleaf, birch, bare), bushes, grass, flowers and rocks are generated from code in the manner of Abyssal Garden (MIT): seeded variants per biome, swaying in the wind, each tree drawn in less detail with distance and as a flat baked picture far off (R43). Ground is one shader (trail, field, rock) per biome: snow, grass or sand. Rendered below the window's resolution, antialiased by Godot's TAA and upscaled with MetalFX spatial (FSR 1 off the Mac; R43); about 60 fps or better on Bob's Mac in every biome. (Bob, 2026-11-20.)
- R40. Streams and bridges (realistic look, biomes with a river): a side stream comes down the hillside about every 1.1 km (the first at 420 m), passes under the trail in a gully on a timber footbridge (plank deck, rails, a trestle bent on each bank, stone ends) and runs down to the river. It pools calm under the bridge and runs as rapids where it is steep, with white water and boulders in its bed; frozen in winter, with snow on the deck. The rider rides the deck. H hides the whole ride HUD (panels, coach, groove, fps) for a clean view and H brings it back; it no longer goes home (the Home button does). (Bob, 2026-11-21.)
- R41. GPX routes (Bob, 2026-11-21): import a `.gpx` from the home screen (same Upload dialog; a Routes row of cards shows each route's height profile over a band coloured by its scenery). The route sheet offers a free ride (the trainer is put in FTMS simulation mode at the route's real grade × "hill feel", 50 % by default like Zwift; speed then follows power, weight and grade; the ride ends, completed, at the route's distance; the route profile replaces the groove) or a workout on the route (ERG as usual; the route gives the hills). Scenery: at import the app asks OpenStreetMap's public Overpass API once for land cover along the route (the route's coordinates are sent; patient retries across public servers; "Look up again" if it failed, with a climate-only guess meanwhile) and keeps it beside the GPX; at ride time latitude, elevation and the month turn it into biomes (woods, open fields, scrub, desert, snow above a latitude-dependent snow line or in a northern winter, birch woods up north, autumn colours in autumn), with rivers and lakes and creeks where water was found within 250 m. The realistic look blends biomes over 150 m (plants dither, the ground mixes, hills and water follow). Pixel and Smooth use the route's most common biome and its distance, hills and land cover on the usual winding trail; the realistic look rides the true map (R42). Route rides record position and altitude in the FIT, so uploads show the real map. Map data © OpenStreetMap contributors (ODbL), credited on the route sheet and in the README.
- R42. True-map route rides (Bob, 2026-11-21): in the realistic look a route is ridden on its real shape and real ground. The trail follows the GPX in a flat metre frame (corners rounded to a few metres; a loop carries on round past its end, a point-to-point route turns back); where the route rides the same road twice the passes become one road. Elevation tiles (AWS Terrain Tiles, terrarium PNGs, public, no key) are fetched once after the scenery lookup: zoom 14 within 1.2 km of the route, zoom 10 out to 8 km for the horizon; the trail's heights and the trainer's grade come from that ground along the path (smoothed over ~50 m), so what is felt is what is seen. The ground is 64 m tiles around the rider (2–8 m grid) and a far ring to 7 km; the trail itself is a fine ribbon with its groove and banks. The scenery lookup also keeps OpenStreetMap's shapes as a cover grid (20 m squares out to 1.2 km either side): woods (needle- or broadleaf where tagged) stand thick where they are mapped, fields stay open, scrub and bare rock where the map has them, the season and climate still choosing the plants. Lakes lie flat at their lowest ground, rivers follow their valley, both with their beds carved out; where the trail crosses water it runs onto a timber bridge (bents every ~12 m, the deck lifted clear of the water with ramps up to it), and a longer stretch over water becomes a raised causeway. Workouts can pick an imported route as their scene. Routes looked up before stage 2 keep the biome-based scenery until "Look up again". Elevation data credited in the README.
- R43. Scenery quality pass (Bob, 2026-11-21; realistic look). Goal: the scenery should stand beside a AAA title. Scenery first; a first-person cockpit (bars, hands, front wheel, the rider's shadow) is on hold. Measured start, summer strip at 2 pm on Bob's M4 Pro, 3024×1716 at 50 % render scale: 17.3 ms a frame (58 fps), 4.06 M triangles, about 2,000 draw calls; plants are 8.4 ms of it (grass 2.8), temporal upscaling 3.6, sun shadows 1.8, ambient occlusion 1.4, clouds 0.8, bloom 0.8 (`tools/profile.sh` repeats the measurement). Decisions: photo-scanned CC0 textures are allowed for the ground, rock and bark (Poly Haven, ambientCG; fetched by `tools/fetch-textures.sh`, 1K, credited in LICENSES.md and the README; the shaders fall back to their noise when a set is missing); plant shapes stay generated from code. The work, in order: (1) lighting with real contrast (a strong sun against the sky, a lower default sun, automatic exposure, a colour grade) and atmosphere (volumetric light shafts and valley mist); (2) trees rebuilt as leaf cards with three levels of detail, a flat baked picture of each tree beyond about 80 m so far hills carry forest, and grass rebuilt dense near the rider; (3) scanned surface materials with height blending; (4) a Quality setting (Low, Medium, High) and automatic render scale so R15 holds on smaller Macs, with the savings spent on a 67–75 % render scale; (5) shade under the canopy, cloud shadows drifting over the land, plants and rocks grounded where they meet the soil; (6) more undergrowth (ferns, logs, saplings, leaf litter). Budget on Bob's Mac: 12 ms or less at 67 % render scale on High. Never: camera sway or motion blur in first person (R39). Result (2026-11-22, `graphics` branch, all six items built): the same summer view is 13.3 ms a frame (75 fps) at 50 % render scale on High, 0.83 M triangles, about 790 draw calls, with far more in it (forest on the far hills, a dense meadow, undergrowth, scanned ground, light shafts, cloud shadows). The budget is missed: 67 % render scale costs 17.1 ms (58 fps), 75 % costs 19.0 ms. What is left is mostly fixed cost: MetalFX temporal upscaling is 3.1 ms, plants 3.7 (grass 1.4), sun shadows 1.2, clouds 0.4. The automatic render scale should therefore settle between 50 and 67 % on Bob's Mac to hold 60 fps (the rule is unit-tested; it has not yet been watched through a real ride). Measured on the same Mac, Low is about 10.0 ms and Medium about 11.7 ms at 50 %: Low is only about a fifth cheaper than High, so 60 fps on a base M1 or M2 is not shown and needs a test on one. Upscaler (decided by Bob, 2026-11-22): the look is antialiased by Godot's TAA and brought up to the window by MetalFX spatial (FSR 1 off the Mac), not by the temporal upscalers it began with (MetalFX temporal, FSR 2). Spatial with TAA measures about 2 ms a frame less at 67 % and is sharper in stills; Bob rode with a switch between the two, could not tell them apart, and both looked good (one seemed brighter, but measured from one view they are equally bright, within 3 %). The switch is gone; `tools/profile.sh aa` repeats the comparison. The frame-rate readout also shows the render scale in use. Tree versions (2026-11-22; Bob: trees changed shape oddly as they came nearer): a tree's middle-distance version must hold its close-up's outline, mass and colour, since the two cross-fade about 28 m away, where a tree is large in view. A spruce's now keeps every bough (one tent of needles, its skirt and hanging twigs each) where it kept every other bough as a broad plate; a broadleaf's keeps every other leaf card at 1.4 times the size where it kept every third at 1.85 (its leaves visibly grew), drawn in a little so the crown's outline holds; far trunks stand in their crown's shade as bark does; needle, leaf and wood tones are matched to the close-up by measurement. The far pictures are drawn from the middle version, so they follow. Frame time is unchanged (13.2 ms at 50 % on High, 0.83 M triangles). `lodview=near|mid|picture` on a preview draws every tree as one version, to compare them from one camera. Three more things Bob saw on that ride (2026-11-22). Wind: plants drifted in slow circles, each height out of step with the next, which read as weed under water; now a plant leans downwind as a gust crosses the land (the same gusts as the grass) and rocks a little at its own pace, in step up its stem, with boughs bobbing and leaves shivering small and quick on top; a tall tree's top moves under a hand's breadth. Clouds: their edges carried a static grain from the raymarch's dither, a fixed pattern on the screen. Changing the pattern every frame for the TAA to average was tried and Bob saw the clouds jitter from frame to frame instead; the fix is at the source: the march takes long strides through clear air and half-length ones inside a cloud (stepping back to go over its edge finely), which cuts the grain by a quarter (measured; a further halving measured no smoother), and the pattern stays fixed, so nothing flickers. It costs about 0.6 ms a frame. One spruce's trunk looked like a huge cone: a spruce trunk tapered evenly from a wide flared foot, which showed on the variants with a bare lower trunk; it is now a slimmer pole that holds its girth up to the crown and flares only at the root, and the dark solid filler inside the middle version's crown is a stack of see-through sprays. Brightness (Bob, same day: the scene's brightness changed abruptly from time to time): every step of the automatic render scale restarted Godot's automatic exposure, which flashed the picture about 2.7 times brighter and let it sink back over some ten seconds, and left it at a different brightness, because Godot meters a corner of the picture whose size depends on the render scale. The look now meters itself: a small light meter averages the finished picture (read back without stalling the frame) and the exposure eases toward the one that holds its mean brightness at what a clear summer midday shows, within the same limits as before (up to 1.5 stops brighter, half a stop darker; about 4 s). Measured across three scale changes the picture's brightness stays within 3 %. Frame time measured again with all of the above (same view, Bob's M4 Pro, High): 11.9 ms (84 fps) at 50 % render scale, 15.1 ms (66 fps) at 67 %, 16.8 ms (60 fps) at 75 %; 0.82 M triangles, about 515 draw calls; clouds are now about 1.5 ms of it, plants 3.5 (grass 1.4), sun shadows 1.5. Low is 8.9 ms and Medium 11.1 ms at 50 %. So High now holds 60 fps at 67 to 75 %; the 12 ms at 67 % budget is still missed. Grass (Bob, 2026-11-22: the groundcover changed its look at a certain distance from the rider): the meadow was three separate sets of tufts, one for each ring of distance, each rooted in different places with different blades; about 6 to 9 m ahead the middle ring's few broad tufts sank into the ground while the near ring's dense fine ones rose in their place, and again near 30 m. The rings are now one meadow: each ring's tuft slots are twice as far apart as the last's, and a farther ring's tuft is one of the nearer ring's own (same root, blades, lean, colour, flower). Coming nearer, more tufts stand up one by one between those already there and every blade narrows; no tuft is swapped for another, and where a ring ends the tufts that live on pass to the next ring's mesh at one distance, drawn the same by both. The middle ring is denser than it was (4 tufts a square metre, 5 blades each) and ends at 24 m, not 30; the ground takes a sixth of the meadow's colour where the near ring thins, and the mid-distance meadow now measures the same brightness as the near ring's blades drawn out that far (within 1 %; `grassnear=<m>` on a preview draws that reference). Bushes, logs and rocks were checked the same way and their two versions already match. Cost: the same as before (grass about 1.4 ms; measured as paired on/off samples while another ride was running, so the whole-frame figures above were not re-measured): tufts not standing where they are drawn, and flower heads not shown (most), now stop before the costly part of the vertex shader, and a flower head past the near ring is one five-sided disc. `lodback=<m>` on a preview draws the levels of detail as if the eye stood that much further back, so one fixed view shows what changes on approach. Details that changed from the plan: tree pictures take over at about 64 m (not 80); the trail gravel is drawn at 1.25 m a repeat, finer than its scan, with a packed ridden band; the pixel-style tyre track is not drawn in this look. Known rough spots: bracken fronds are flat plates within 3 m; pebbles are lit flat like the ground they lie on; summer leaf litter still reads as straw mats close up; sunset clouds are rose but low in contrast; cloud shadows barely show beyond about 1.5 km on route rides (the haze covers them); shade under open woods is subtle.
- R31. Rider model: Quaternius Universal Base Characters (Superhero male, CC0) replaces the Mixamo character so the repository is redistributable; the rig is posed by the same IK (`RiderBody`), the kit is painted by the cel shader's body zones, and the body sways with the pedal stroke (pelvis roll and shift, spine counter-roll, elbow flex). Mixamo files and prebuilt GDBLE binaries are untracked; history is to be rewritten before the first push. (Bob, 2026-09-04.)

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
- **Camera.** Third-person follow camera with layered noise on position and rotation for the handheld feel, tuned so it reads as lively and never as nauseating. Shake was removed 2026-09-03; the camera keeps its smoothed follow only.
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
- Camera shake was a three-level user setting; removed 2026-09-03 (see R21).

New from this spec, still open:
- Whether v1 needs a cadence sensor separate from the trainer. The KICKR CORE reports cadence itself, so proposed: no.
