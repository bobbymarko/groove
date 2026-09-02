# Manual hardware tests

Run these on real hardware at the end of any milestone that touches the device layer.

## M0: Trainer connect and ERG control (passed 2026-09-02, KICKR CORE)

1. `tools/run-dev.sh`, allow the Bluetooth prompt.
2. Turn the pedals to wake the trainer. It should appear in the device list and connect automatically.
3. Expect in the log: FTMS service found, supported power range read, then `success` responses to
   Request Control (0x00), Start (0x07), and Set Target Power (0x05).
4. Pedal. Live power and cadence update on screen.
5. Press 200 W then 100 W. Resistance changes within about a second; each change logs a `success`.

## M2: Pairing, heart rate, and dropout recovery

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
