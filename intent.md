# Intent: Ride — structured indoor cycling workouts without the subscription

**Originator:** Bob Marko
**Date:** 2026-09-02
**Status:** Draft, awaiting originator review
**Stage:** 1 — Plan (AI-native SDLC)

## Problem

I use Zwift for structured cycling workouts, and that is all I use it for. I don't use the social features, the racing, or the virtual worlds. Paying $20 a month for the one slice I actually use doesn't make sense.

There is no lightweight, attractive app that just does that one thing well: load a structured workout, control the smart trainer, show me how I'm doing, and sync the finished ride to the services I already use.

I'm also a mountain biker. Zwift's virtual roads are boring and don't match the experience I actually have on a bike. The time on the trainer should feel like a trail ride, not a road ride.

## Proposed outcome

A cross-platform app, used primarily on Mac, that runs a structured cycling workout end to end:

1. **Load a workout.** The user loads a structured workout file and the app understands the intervals, targets, and durations.
2. **Ride it.** The app connects to a smart trainer and controls it so the trainer sets resistance to match the workout (ERG-style control). It reads power, cadence, and heart rate, and everything else Zwift supports in its workout mode.
3. **See progress.** A UI shows where you are in the workout, current and target numbers, and how you're doing against the plan.
4. **Enjoy it.** While riding, the user sees interesting animated scenes. The reference aesthetic is `game-aesthetic.mp4` in this folder: pixel art, third-person view from behind a rider climbing a snowy mountain trail, falling snow, pine trees, a soft blue and pink palette. The camera has a handheld feel, so the scene reads as lively and full of action rather than a static backdrop. Scenes are trails, not roads. That is a winter scene; scenes should be procedurally generated and cover other times of year too.
5. **Sync it.** When the workout finishes, the ride posts automatically to Strava and to any other connectors the user has set up, such as COROS and Garmin. Strava and COROS matter most to me personally (my bike computer is a COROS Dura).

Success means I can cancel Zwift and lose nothing I actually used, and that other riders with the same narrow need can do the same on their own platforms.

## Affected users and systems

**Users**
- Me, on Mac, as the first and primary user.
- Other cyclists who want structured indoor workouts without a full virtual-world subscription. This is meant to be a public product, so onboarding, reliability, and device compatibility matter.

**Systems and devices**
- Smart trainers: the app must both read from and control them. My Wahoo KICKR CORE, connected over Bluetooth with no dongle, is the reference device for the first version.
- Sensors: power meters, cadence sensors, heart-rate monitors, and other standard cycling sensors.
- Workout file formats: whatever people already have their structured workouts in (zwo to start).
- Fitness services: Strava, Garmin, COROS, and other connectors, for posting completed rides. Strava and Coros are most important for me personally.
- The user's desktop, with Mac first and other platforms to follow including windows, android, and ios.

## Constraints

Decided so far:

- **Bluetooth trainer control at launch.** The first version talks to the Wahoo KICKR CORE over Bluetooth, matching how I ride today. ANT+ and other trainer brands come later.
- **No backend or accounts in the first version.** Workouts, ride history, and connector tokens live on the device. Posting to Strava and COROS uses the user's own OAuth authorization from the app.
- **One codebase across platforms.** iOS and Android are further out, but adding them must not mean rebuilding the app. The workout engine, trainer abstraction, connectors, and scene rendering should be written once and reused, with only thin platform-specific layers.

The intent also implies these:

- **Cross-platform, Mac first.** The technology choice must not lock the app to macOS, but Mac is the platform that has to work on day one.
- **Real hardware control.** Trainer control is not optional. A workout that cannot drive resistance is not a replacement for Zwift's workout mode.
- **Automatic sync.** The finished ride must reach Strava and the other configured services without manual export.
- **Aesthetic direction is set.** The pixel-art look in `game-aesthetic.mp4` is the target style: handheld camera feel, mountain-bike trails, procedurally generated scenes rather than hand-authored ones.
- **No decisions yet** on tech stack, hosting, timeline, budget, or monetization.

## Open questions

- **Workout formats.** Zwift's `.zwo` is the launch format. Which others follow, and when? Common ones are `.fit`, `.erg`, and `.mrc`. Should the app also pull workouts from TrainerRoad, TrainingPeaks, or intervals.icu?
- **Connector list.** Strava and COROS are required for launch. Is Garmin also required at launch, and which others (Wahoo, TrainingPeaks, intervals.icu, Apple Health) come later?
- **Cross-platform framework.** Windows, Android, and iOS follow Mac, and the code must carry over. Which framework or engine best serves a Mac-first app that needs Bluetooth on all four platforms and a 2D procedural pixel-art renderer? Is Apple TV or a web build ever in scope?
- **Scene behavior.** Should the scene react to the workout, for example trail gradient, rider speed, or camera intensity changing with power and cadence, or is it ambient? Should the time of year follow the real calendar, be user-selected, or be random?
- **Riding without a plan.** Should there be a free-ride mode with no workout loaded, or is that out of scope?
- **COROS upload path.** Strava has a public upload API. COROS's third-party integration is partner-based and needs verifying before COROS sync is promised at launch. If direct upload is not available, is Strava-to-COROS sync or FIT file export an acceptable fallback?
- **Distribution and price.** Free, one-time purchase, or something else? App Store, direct download, or both?
- **Zwift parity.** Which specific Zwift workout-mode behaviors matter (ERG mode on/off, interval skip, workout bias adjustment, free-ride blocks, text prompts during intervals)?
