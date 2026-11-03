# Camp: a training session

**Status:** Draft for discussion with Bob, 2026-11-02. A playable prototype implements it (`camp/tools/run.sh ride`); numbers are starting points to tune by feel.

## The one rule

The workout is the level. Nothing in the game rewards riding less, easier or shorter than the plan.

## What you see

A side-scrolling trail, low-poly, at the time of day you're riding. The ground is the workout's power profile:

- **Recovery and endurance** are low, flat valleys.
- **Intervals** are plateaus. Harder blocks sit higher.
- **Warmups, cooldowns and ramps** are slopes.
- **Free ride and max effort** are open meadows with no fixed height.

The trail scrolls with workout time, not distance, so the level is exactly as long as the workout and everyone rides the same level. A few seconds of trail are visible ahead, and a strip across the top shows the whole workout with a marker, so the next climb never surprises you.

## What you do

With ERG on, the trainer holds your watts, so the skill is what ERG cannot do for you: keep turning the pedals, hold cadence, and finish every interval. With ERG off, matching the target power is the skill.

You forage as you ride. Everything you gather is a reward for being on target at that moment:

| Find | Where it appears | How you get it | Value |
|---|---|---|---|
| Berries | Bushes all along the trail, every few seconds | Pass the bush while your power is in the band | Cheapest, the steady trickle |
| Flowers | Steady blocks and intervals at tempo or harder | Pass the patch while in the band | Middling |
| Critters | Each VO2 or anaerobic interval | A critter darts out at the start; finish the interval averaging 95 % of target and it's yours | Rare |
| Honey | Max efforts and sprints | Watts above FTP fill the comb; more watts, more honey | Rare, effort-scaled |

**The band** is 90 % to 115 % of target, on smoothed three-second power. Over the band still forages; it only costs you. In free ride, any steady pedalling counts.

**Ripeness.** Berries and flowers picked on harder ground are worth more: endurance pays one, tempo two, threshold three, VO2 four. Without this, an easy spin would pay the same as a hard plateau, and ERG would make every workout equal.

Missing is visible but gentle. A bush you pass while out of the band stays full and shakes as you go by. A critter you don't catch runs off. Nothing is taken away.

## Ride controls change the haul

Bias and ripeness are fixed at the moment you pick something up.

| Action | Effect |
|---|---|
| Bias up (harder) | Finds are bigger and worth more |
| Bias down (easier) | Finds are smaller |
| Skip an interval | That stretch of trail is fogged; nothing grows there |
| Pause | The world stops with you |

## After the ride

You roll back into camp with your basket and drop it at the trading post. The trader tallies the haul in a short scene and pays coins. Pay is the haul's value plus a load bonus from the workout's training stress, so harder plans pay more even with ERG doing the watts.

The ride is recorded and synced exactly as in Groove. Camp is a game on top of a real training ride, never instead of one.

## Open questions for Bob

1. **Band width.** Is 90 to 115 % right, or should it be tighter on harder intervals?
2. **Cadence play.** Groove now scores cadence targets. Workouts with cadence targets could grow mushrooms that only pick at the right cadence. Worth it in the first version?
3. **Showing actual power.** The rider always rides the ground. Should actual power also show as something you can see, such as a glow on the bike or a dust trail that changes colour when you're in the band?
4. **Coach notes.** Groove shows the workout's text events. In Camp, should the trader deliver them, or a companion riding along?
5. **Economy scale.** A 60-minute VO2 workout pays about 4,500 coins in the prototype if every find is picked, most of it from ripe berries and flowers on the hard plateaus. The number only matters relative to store prices, which don't exist yet.
