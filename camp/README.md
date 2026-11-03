# Camp

A cozy training game built on Groove's trainer control. The concept and decisions are in [intent.md](intent.md). This folder is the prototype, on the `camp` branch.

## Look at it

```bash
camp/tools/run.sh editor
```

The monster builder. Swap parts, drag the sliders, pick colours, drag the stage to spin. Save writes your rider to user data.

```bash
camp/tools/run.sh lab
```

The style lab scenes. Keys 1 to 5 switch between the trail, the rider lineup, the three-quarter view, camp, and the trading post.

Neither touches Bluetooth, so both are safe to open during a ride.

## How it's made

- `art/blender/*.py` build every model from code: `blender -b --factory-startup --python camp/art/blender/build_monster_kit.py` (also `build_bike.py`, `build_nature.py`, `build_camp.py`). Output lands in `art/models/`.
- Parts carry named attachment points and colour roles, so any body takes any head, eyes, horns or hat, and the editor can recolour anything.
- `rider/monster_rig.gd` assembles a monster from a recipe and bends generated limbs to whatever it holds. `monster_rider.gd` fits it to the bike like a real bike fit; `monster_stand.gd` stands or sits it.
- `shaders/lowpoly.gdshader` is the one surface shader: faceted, a dusk ambient, a warm rim.
- `tools/shot.sh <mode> build/out.png` renders a view headlessly for review (`frames=N` for a clip).

## Ride it

```bash
camp/tools/run.sh ride
```

A practice ride on the simulator: VO2 5x4 by default, nothing recorded. Add `workout=res://camp/ride/workouts/camp_sampler.zwo` for a two-minute ride through everything the trail grows. Keys: Space start and pause, S skip, Up and Down bias, E toggles ERG, Esc ends. Simulator only: `[` and `]` push your effort off target, Q stops pedalling, F runs twenty times faster.

```bash
camp/tools/run.sh ride real
```

A real ride on your paired trainer, recorded and saved like any Groove ride, with the sharing screen at the end. Close Groove first.

The rules are in [gameplay.md](gameplay.md).
