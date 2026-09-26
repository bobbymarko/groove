# Intent: Camp (working title) — a cozy training game built on Groove

**Originator:** Bob Marko
**Date:** 2026-09-07, updated 2026-09-26
**Status:** Draft. Concept captured from Bob's description. Work started 2026-09-26 on the `camp` branch, art style and character editor first. Game dynamics still being discussed.
**Stage:** 1 — Plan (AI-native SDLC)
**Builds on:** `intent.md` and `spec.md` (Groove). Everything about trainer control, sensors, workout files, ride recording, FIT export and connectors carries over unchanged.

## Problem

Groove does the one thing well: load a workout, control the trainer, ride it, sync it. But there is nothing in it that helps it grow. Nobody comes back for a friend, and nobody tells a friend about it.

The social things that exist in this space are the wrong shape. Racing platforms mean cheaters, leaderboards and moderation, none of which sounds fun to build or to be in. The thing that actually motivates is smaller: a Strava feed of a core group of riders, seeing what they did today, and knowing what they are training for. Right now nothing shows that last part at all.

Zwift's garage is the closest existing idea, and it is a menu. It could be a place.

## Proposed outcome

A cozy training game in the spirit of Animal Crossing and its genre, where training is the game. You train, you get paid for it, you build a place of your own over time, and your friends' places sit next to yours.

Two worlds, one app:

1. **The trail (riding).** A side-scrolling level whose ground is the power profile of the workout. An interval block is a plateau you climb onto, a recovery is a drop back down. You ride a small stylised bike across it, hop up, hop down. Quasi-3D side-scroller in the spirit of Donkey Kong Country or Yoshi's Island, exact art still to be defined.
2. **Camp (between rides).** An isometric or top-down world, Pokémon or farm-sim style, that you walk around. Your van is here. Your friends' vans are parked next to yours. A trader is here too.

The loop:

- **Collect while you ride.** Along the trail you gather things of different value: berries at the cheap end, then flowers, then animals, and so on. What you gather is set by the difficulty of the workout. TSS and similar load metrics are the starting point; a harder ride yields more and better.
- **Drop off and get paid.** After each workout you hand your haul to the trader, a pioneer type who turns berries into jam and animals into meat and skins. A short scene tallies what you brought back and he pays you. Payout tracks workout difficulty.
- **Spend at the store.** Money buys gear and decor.
- **Build your van.** You start with a bare Volkswagen van. Paint it, change the exterior, furnish the interior. Make it yours.
- **See your friends.** Your core group's vans are parked next to yours, so you watch them evolve as they train. A signpost outside each van lists the events that rider is training for. That is the missing piece in the community today: knowing what your friends are aiming at.
- **Be yourself.** A character editor built into the game, with sliders that go well past what Zwift allows (fat, thin, and further into stylisation). Characters are generative, not chosen from a list of models. Whether they are people, monsters or something else is part of the art decision.

Later, a companion app for phones shows activities and what people are training for, without the trainer.

Success means people ride with Groove because their friends are there and because their van is not finished yet.

## Affected users and systems

**Users**
- Bob, first. Then a core group of riding friends, which is the real test of the social loop.
- The audience is predominantly male adult cyclists, so the style must be fun and stylised without being cutesy.
- Existing Groove users must lose nothing. The current experience keeps working while this is built.

**Systems**
- Everything Groove already owns: Bluetooth trainers and sensors, `.zwo`/`.erg`/`.mrc`/`.fit` workouts, ride recording, FIT export, intervals.icu and Strava.
- New: a per-player save (money, inventory, van, character) that lives on the device first.
- New, later: some way for friends to see each other's vans and events. This is the first thing in Groove that cannot be done with no backend, and it needs its own decision (see open questions).

## Constraints

Decided so far:

- **Training is the game.** Every mechanic sits on top of a real structured workout. Nothing rewards skipping or shortening the training.
- **No racing, no leaderboards, no anti-cheat.** The only person a cheater hurts is themselves. That is deliberate.
- **Not the real world, not real bikes.** Highly stylised world and gear, cool rather than realistic. The style has to be defined before art is made.
- **Groove is not broken by this.** The current app ships and keeps shipping. The new game is built alongside it in the same repository and shares the trainer, workout and sync layers rather than forking them.
- **Godot 4 with GDScript, one codebase**, same as Groove.
- **Same repository, `camp` branch.** Decided 2026-09-26. Camp code lives under `camp/` and shares `core/`, `devices/`, `connectors/` and the pairing and settings sheets with Groove. Trainer fixes land on `main` and merge into `camp`, never the other way round until Camp is ready.
- **Art style before mechanics.** Decided 2026-09-26. The first milestone proves a look that can carry the whole idea (trail, camp, van, trader, characters) and a character editor in that look. No gameplay is built until the style is agreed.
- **Character generation, not model hunting.** No searching for third-party character models. One parametric base with sliders and palettes, authored once.

## Open questions

These are the things to settle before a spec is written.

- **What does riding well look like on the trail?** The ground is the target profile. Where does actual power show? Proposal: collectibles hang at the target-power height, so you gather them only while holding the target. Under target and you ride below them and miss. Payout is then difficulty times compliance, and the moment-to-moment feedback is the pickup sound.
- **Progress axis.** Does the level scroll with time (the workout is a timeline) or with distance (speed from power)? Time is honest and simple; distance rewards big riders.
- **What is the yield curve?** TSS is easy to game by setting a low FTP. Since there is no competition, does that matter? Proposal: pay on TSS and intensity factor, cap per ride, bonus for compliance.
- **Art direction.** Candidates to mock up: the current pixel post-process applied to a side view (cheap, consistent with Groove); chunky flat-shaded low-poly in the Firewatch poster vein; thick-outline cel look. Needs a style sheet before any asset is built.
- **Who are the characters?** People, monsters, animals, robots. This decides the character editor's base mesh and how far the sliders can go.
- **Friends.** Options: a small hosted backend with accounts; a peer-shared "postcard" file exported from each player and imported by friends; or a read-only feed hosted somewhere simple. Accounts contradict Groove's no-backend constraint, so this needs a real decision and can be deferred behind the solo loop.
- **Events on the signpost.** Manually entered by the rider, pulled from the intervals.icu calendar, or both.
- **Name.** "Camp" is a placeholder.

## First milestone: style and character editor

The question this milestone answers: is there an art style that is fun, stylised, not cutesy, and cheap enough to produce that a small team (Bob and Claude) can fill a world with it?

Outcome Bob can judge:

1. **A style sheet.** One page per candidate style showing a rider on a bike, a van, the trader, a berry bush and a slice of trail, all in the same look. Bob picks one or asks for a blend.
2. **A character editor in Godot, in the chosen style.** One parametric base character with sliders (body shape and proportions at minimum, then head, colours and a few outfit pieces). Sliders go further than Zwift's, into caricature. The character sits on a bike and pedals, so the editor proves the body still works on the bike at every slider extreme.
3. **One trail and one camp vignette** rendered in the chosen style, to prove it holds up in both the side view and the isometric view.

Art pipeline, as proposed by Claude:

- **Concept art** from an AI image generator, steered by Bob's reference images, to explore styles quickly before anything is modelled.
- **Characters and bikes are built in Blender** by Claude through scripts, not generated. The editor needs one clean, rigged mesh with blend shapes that Godot can drive from sliders; AI 3D generators produce static meshes with messy topology that cannot deform that way.
- **Props and decor** (van items, collectibles, trail dressing) can come from an AI 3D generator or be modelled in Blender, whichever holds the style better. These are static, so generator output is usable after cleanup.
- **Licensing.** The repository is public and MIT. Every generated or downloaded asset is recorded in `LICENSES.md` with its source and terms. Reference images from other games stay out of the repository.

## Discussion notes

**Why not a fork** (agreed 2026-09-26, as a branch in the same repository). The trainer control, parsers, recorder, FIT writer and connectors are the parts that keep getting bug fixes, including whatever the Windows tester finds this week. A fork means applying every one of those twice. In the codebase today the only screen that is "the game" is the ride screen; home, summary, rides, settings and devices are the training-app shell. The new game replaces the ride screen with the trail and wraps the shell in the camp world, but it can call the same sheets for pairing, settings and the workout library. Build it in a `camp/` directory, launch it from a hidden switch, and if it becomes the product the current 3D scenes become one ride mode among others, or retire.

**Order of work, if the answers above go the obvious way.** Solo loop first: trail ride with collectibles, trader payout scene, van with a handful of purchasable items, character editor with a few sliders. That is playable and testable by Bob alone. Friends come after, because they are the one part that needs infrastructure.
