# Manual hardware tests

Run these on real hardware at the end of any milestone that touches the device layer.

## M0: Trainer connect and ERG control (passed 2026-09-02, KICKR CORE)

1. `tools/run-dev.sh`, allow the Bluetooth prompt.
2. Turn the pedals to wake the trainer. It should appear in the device list and connect automatically.
3. Expect in the log: FTMS service found, supported power range read, then `success` responses to
   Request Control (0x00), Start (0x07), and Set Target Power (0x05).
4. Pedal. Live power and cadence update on screen.
5. Press 200 W then 100 W. Resistance changes within about a second; each change logs a `success`.

## M2: Pairing, heart rate, and dropout recovery (passed 2026-09-02, KICKR CORE + TICKR)

Needs the KICKR CORE and a Bluetooth heart-rate strap.

1. `tools/run-dev.sh`. On Home, press "Devices…". Press Scan. Turn the pedals and put the strap on.
2. Select the trainer, press "Connect selected". Card shows "Connected" and live watts within a few seconds.
3. Select the strap, connect. Card shows "Connected" and live bpm.
4. Home shows both devices and the button reads "Ride". Start the workout. Target power is felt in the pedals,
   and heart rate appears in the HUD.
5. **Dropout:** unplug the trainer (or walk the strap out of range) mid-ride. The HUD shows a red
   "disconnected, reconnecting…" line and the timer keeps running. Plug it back in. Within about
   10 seconds the line clears and resistance returns to the current target.
6. Quit the app and relaunch. Home shows "Looking for …". Within about 20 seconds both devices connect
   without visiting the Devices screen.
7. On Devices, "Forget" a device. It is no longer auto-connected on the next launch.

## M3: Record, FIT export, intervals.icu upload, COROS/Strava chain

Status 2026-09-02: step 1 imported into COROS fine; Strava forwarding still being watched. Step 2 passed (green). Steps 3–5 pending.

1. **COROS import test (no ride needed).** Generate a test file with
   `godot --headless --path . -s tools/make_test_fit.gd -- build/ride-test-5min.fit`, AirDrop it to the
   phone, import it in the COROS app. Expect: activity appears in COROS with power, cadence, HR; then
   appears on Strava as a Virtual Ride within a few minutes. Delete both afterwards.
2. **intervals.icu key.** Settings → paste personal API key → Test shows "Connected as <name>" → Save.
3. **Real ride.** Ride a workout on the trainer. Finish (or End). Expect: summary screen with metrics,
   "intervals.icu: uploaded", FIT file in the rides folder. Check the activity on intervals.icu.
4. **Crash recovery.** Start a ride, record for a minute, force-quit the app. Relaunch. Home reports a
   recovered ride; it is in Recent rides with a FIT file.
5. **Offline upload.** Turn Wi-Fi off, finish a ride: summary shows "waiting to upload". Turn Wi-Fi on,
   press "Upload to intervals.icu" (or relaunch): upload completes.

## Planned workouts from intervals.icu

1. Settings → intervals.icu key set and green. Add a bike workout to today's date on the intervals.icu calendar and one a few days out.
2. Reopen the home screen (or wait five minutes and revisit). Expect a highlighted **Today** section with the workout card, a day-named section for the later one, then **Library**.
3. Click a planned card: the side sheet shows the plan and **Ride** starts it like a library workout.
4. Disconnect the network and revisit home: cached cards stay, a status line reports the failed refresh.

## Recorded values (regression for the 2026-09-04 zero-ride bug)

1. Ride a minute on the simulator or trainer while pedalling, End, open the ride in Recent rides.
2. Avg power, cadence and heart rate must be non-zero and the trace must show your power. A journal full of `"p":0` means the recorder was not attached to the devices.

## Auto-pause (R33)

1. Trainer connected, not pedalling. Open a workout, Ride, press Start. Expect: clock stays at 0:00, the coach says "Start pedalling when you're ready", the rider stands with a foot down.
2. Pedal. Expect: the clock starts within a second, the coach note goes.
3. Stop pedalling mid-block. Expect: after about three seconds "Paused. Pedal to carry on." and the clock stops; pedalling again resumes it.
4. Press Pause, then pedal. Expect: it stays paused until Resume.
5. Settings → Ride → Auto-pause Off: step 1 starts the clock immediately.

## Devices during a ride (R34)

1. Start a ride with the heart-rate strap off. Put the strap on. Expect: within about 30 s the bpm appears without touching anything (background rescan).
2. Press Devices (or D) during a ride: the sheet opens over the ride, the ride keeps running, Escape closes the sheet and does not end the ride.

## Updates (R36)

1. Settings → About shows the running version; Check now reports "Up to date" against GitHub.
2. Launch the release build with `--args -- version=0.0.1`: the home footer shows "Update to <latest>"; the sheet shows the release notes and Download and install.
3. macOS: Download and install. Expect: progress to 100 %, "Verifying", "Unpacking", "Installing", the app relaunches as the new version, and `Groove.previous.app` beside it disappears on that launch. A copy in `~/Downloads` that macOS translocated is refused with "Move Groove to Applications first".
4. Windows: the sheet offers Download from GitHub and opens the release page.
