# Manual hardware tests

Run these on real hardware at the end of any milestone that touches the device layer.

## M0: Trainer connect and ERG control (passed 2026-09-02, KICKR CORE)

1. `tools/run-dev.sh`, allow the Bluetooth prompt.
2. Turn the pedals to wake the trainer. It should appear in the device list and connect automatically.
3. Expect in the log: FTMS service found, supported power range read, then `success` responses to
   Request Control (0x00), Start (0x07), and Set Target Power (0x05).
4. Pedal. Live power and cadence update on screen.
5. Press 200 W then 100 W. Resistance changes within about a second; each change logs a `success`.
