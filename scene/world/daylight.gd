class_name Daylight
extends RefCounted
## Time of day for the world. A world day lasts a quarter of a real one, so a
## one-hour ride sees four hours of light change. Sun arc by hour, warm low
## sun at the ends of the day, moonlight at night. Everything the scene needs
## for one moment comes back from state().

const DAY_SPEED := 4.0
const SUNRISE := 6.0
const SUNSET := 18.0

const NIGHT_SKY_TOP := Color("070b22")
const NIGHT_SKY_HORIZON := Color("182040")
const NIGHT_FOG := Color("141a34")
const NIGHT_AMBIENT := Color("2a3560")
const NIGHT_TINT := Color(0.34, 0.40, 0.62)     # multiplies unshaded things (mountains, snowflakes)
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const SUN_COLOR := Color(1.0, 0.96, 0.92)
const LOW_SUN_COLOR := Color(1.0, 0.62, 0.40)
const DUSK_HORIZON := Color("f2a56a")

## Fixed hours for the Settings choices; "live" follows the clock.
const MODES := {"live": -1.0, "morning": 7.5, "noon": 12.0, "sunset": 17.6, "night": 0.5}


## World hour right now: local wall-clock time, four times faster, wrapped to a day.
static func live_hour() -> float:
	var t := Time.get_time_dict_from_system()
	var secs := float(t.hour) * 3600.0 + float(t.minute) * 60.0 + float(t.second)
	var frac := fmod(Time.get_unix_time_from_system(), 1.0)
	return fmod((secs + frac) * DAY_SPEED / 3600.0, 24.0)


static func hour_for_mode(mode: String) -> float:
	var h := float(MODES.get(mode, -1.0))
	return live_hour() if h < 0.0 else h


## Lighting for an hour of the world day. noon_elev is the sun's height at noon
## (degrees), az_offset the azimuth at noon (the tuning "sun direction").
static func state(hour: float, noon_elev: float, az_offset: float) -> Dictionary:
	var day_t := (hour - SUNRISE) / (SUNSET - SUNRISE)      # 0 sunrise, 1 sunset, night outside
	var sun_elev := noon_elev * sin(PI * day_t)               # negative at night
	var daylight := clampf((sun_elev + 4.0) / 10.0, 0.0, 1.0) # 1 by day, 0 once the sun is 4° down
	var twilight := clampf(1.0 - absf(sun_elev) / 14.0, 0.0, 1.0) if sun_elev > -6.0 else 0.0
	var moon_up := clampf((-sun_elev - 2.0) / 6.0, 0.0, 1.0)  # moon takes over as the sun sinks
	var out := {"hour": hour, "daylight": daylight, "is_night": sun_elev < -2.0}
	if sun_elev >= -2.0:
		out["elev"] = maxf(sun_elev, 1.5)
		out["az"] = az_offset + (day_t - 0.5) * 180.0
		out["color"] = SUN_COLOR.lerp(LOW_SUN_COLOR, twilight)
		out["energy_mult"] = maxf(daylight, 0.05) * (0.55 + 0.45 * clampf(sun_elev / 25.0, 0.0, 1.0))
	else:
		out["elev"] = 20.0 + 25.0 * clampf(-sin(PI * day_t), 0.0, 1.0)   # moon highest at midnight
		out["az"] = az_offset + (day_t - 0.5) * 180.0 + 180.0
		out["color"] = MOON_COLOR
		out["energy_mult"] = 0.3 * moon_up
	out["ambient_mult"] = lerpf(0.4, 1.0, daylight)
	out["ambient_color"] = NIGHT_AMBIENT.lerp(Palette.SNOW_SHADOW, daylight)
	out["sky_top"] = NIGHT_SKY_TOP.lerp(Palette.SKY_TOP, daylight)
	out["sky_horizon"] = NIGHT_SKY_HORIZON.lerp(Palette.SKY_HORIZON.lerp(DUSK_HORIZON, twilight * 0.6), daylight)
	out["fog"] = NIGHT_FOG.lerp(Palette.FOG.lerp(DUSK_HORIZON, twilight * 0.35), daylight)
	out["tint"] = NIGHT_TINT.lerp(Color.WHITE.lerp(Color(1.0, 0.86, 0.72), twilight * 0.5), daylight)
	out["shadow_mult"] = lerpf(0.5, 1.0, daylight)
	return out
