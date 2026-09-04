extends Node
## Autoload "App". Carries state between screens and persists settings.

const SETTINGS_PATH := "user://settings.cfg"
const SECRETS_PATH := "user://secrets.cfg"
const INSTALL_KEY_PATH := "user://install.key"
const USER_WORKOUTS_DIR := "user://workouts"

var workout: Workout
var ftp: int = 200
var weight_kg := 80.0          # rider weight, always stored in kg
var units := "metric"          # "metric" (kg, km/h) | "imperial" (lbs, mph)
const BIKE_KG := 14.0          # fat bike, added to the rider for the speed model
var look_mode := "16bit"    # "16bit" (pixel look) | "off" (native). The 8-bit palette mode was removed 2026-09-03.
var show_fps := true
var scene_preset := "winter"   # ScenePreset id chosen before a ride
var time_of_day := "live"      # Daylight.MODES key: live (¼-speed real day), morning, noon, sunset, night
var last_ride_journal := ""
var prompt_upload := false   # the summary screen asks about sharing the ride just finished
var dry_run := false         # tooling: ride without recording, screenshots or uploads

## Scene look, adjustable in Settings and on the ride screen (T). Applied by RideScene.apply_tuning().
const TUNING_SPEC := [
	# key, label, min, max, step, default
	["shadow_strength", "Shadow strength", 0.0, 1.0, 0.01, 0.93],
	["sun_elevation", "Noon sun height (°)", 5.0, 75.0, 1.0, 25.0],
	["sun_azimuth", "Noon sun direction (°)", 0.0, 360.0, 1.0, 40.0],
	["sun_energy", "Sun brightness", 0.2, 1.6, 0.01, 0.8],
	["ambient_energy", "Ambient light", 0.0, 1.2, 0.01, 0.4],
	["shade_band", "Shaded-side brightness", 0.3, 1.0, 0.01, 0.66],
	["fog_density", "Fog", 0.0, 0.012, 0.0001, 0.0006],
	["dither", "Dither", 0.0, 0.15, 0.005, 0.0],
	["outline", "Outline", 0.0, 0.6, 0.01, 0.0],
	["camera_distance", "Camera distance (m)", 3.0, 14.0, 0.1, 4.0],
	["camera_height", "Camera height (m)", 1.0, 5.0, 0.1, 2.0],
	["tree_density", "Tree density", 0.2, 3.0, 0.05, 2.0],
	["internal_height", "Render height (px)", 144.0, 400.0, 8.0, 264.0],
	["speckle", "Snow speckle", 0.0, 0.4, 0.01, 0.1],
	["highlight", "Sun highlight", 0.0, 0.5, 0.01, 0.15],
	["sharpen", "Sharpen", 0.0, 1.5, 0.05, 0.4],
	["tree_snow", "Snow on trees", 0.0, 1.0, 0.02, 0.5],
	["motion_blur", "Speed blur at edges", 0.0, 1.0, 0.02, 0.6],
]
var scene_tuning: Dictionary = {}

var _cfg := ConfigFile.new()
var _secrets := ConfigFile.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_WORKOUTS_DIR))
	for row in TUNING_SPEC:
		scene_tuning[row[0]] = float(row[5])
	if _cfg.load(SETTINGS_PATH) == OK:
		ftp = int(_cfg.get_value("rider", "ftp", ftp))
		weight_kg = float(_cfg.get_value("rider", "weight_kg", weight_kg))
		units = str(_cfg.get_value("rider", "units", units))
		look_mode = str(_cfg.get_value("scene", "look_mode", look_mode))
		if look_mode == "8bit":
			look_mode = "16bit"
		show_fps = bool(_cfg.get_value("scene", "show_fps", show_fps))
		scene_preset = str(_cfg.get_value("scene", "preset", scene_preset))
		time_of_day = str(_cfg.get_value("scene", "time_of_day", time_of_day))
		for key in scene_tuning:
			scene_tuning[key] = float(_cfg.get_value("scene_tuning", key, scene_tuning[key]))
	_secrets.load_encrypted_pass(SECRETS_PATH, _install_key())
	Sync.configure_intervals.call_deferred(get_secret("intervals_api_key"))
	Sync.configure_strava.call_deferred(get_secret("strava_client_id"), get_secret("strava_client_secret"))
	# Dev launch option: `-- summary=latest` (or a journal path) opens that ride's summary.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("summary="):
			var which := arg.trim_prefix("summary=")
			var rides := list_rides()
			if which == "latest" and not rides.is_empty():
				last_ride_journal = str(rides[0].journal)
			elif which != "latest":
				last_ride_journal = which
			if last_ride_journal != "":
				go_to("res://ui/screens/summary_screen.tscn")


## Secrets (API keys) are stored encrypted with a random per-install key kept
## next to them. This keeps them out of plain text; it is not a keychain (spec C6).
func get_secret(name: String) -> String:
	return str(_secrets.get_value("secrets", name, ""))


func set_secret(name: String, value: String) -> void:
	_secrets.set_value("secrets", name, value)
	_secrets.save_encrypted_pass(SECRETS_PATH, _install_key())


func _install_key() -> String:
	if FileAccess.file_exists(INSTALL_KEY_PATH):
		var f := FileAccess.open(INSTALL_KEY_PATH, FileAccess.READ)
		if f:
			return f.get_as_text().strip_edges()
	var key := Crypto.new().generate_random_bytes(32).hex_encode()
	var f := FileAccess.open(INSTALL_KEY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(key)
	return key


## Finished rides, newest first: [{journal, fit, meta}].
func list_rides() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(RideRecorder.RIDES_DIR)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	files.reverse()
	for f in files:
		if not f.ends_with(".jsonl"):
			continue
		var path := RideRecorder.RIDES_DIR.path_join(f)
		var j := RideRecorder.load_journal(path)
		if j.is_empty() or j.samples.is_empty():
			continue
		out.append({"journal": path, "fit": path.get_basename() + ".fit", "meta": j.meta, "samples": j.samples.size(),
			"trace": j.samples, "completed": bool(j.get("end", {}).get("completed", false)), "finished": j.has("end")})
	return out


func save_settings() -> void:
	_cfg.set_value("rider", "ftp", ftp)
	_cfg.set_value("rider", "weight_kg", weight_kg)
	_cfg.set_value("rider", "units", units)
	_cfg.set_value("scene", "look_mode", look_mode)
	_cfg.set_value("scene", "show_fps", show_fps)
	_cfg.set_value("scene", "preset", scene_preset)
	_cfg.set_value("scene", "time_of_day", time_of_day)
	for key in scene_tuning:
		_cfg.set_value("scene_tuning", key, scene_tuning[key])
	_cfg.save(SETTINGS_PATH)


func reset_tuning() -> void:
	for row in TUNING_SPEC:
		scene_tuning[row[0]] = float(row[5])
	save_settings()


## Bundled and user-added workout files.
func list_workout_files() -> Array[String]:
	var out: Array[String] = []
	for dir_path in ["res://workouts", USER_WORKOUTS_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if WorkoutLoader.supported(f):
				out.append(dir_path.path_join(f))
	out.sort()
	return out


func go_to(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)


func imperial() -> bool:
	return units == "imperial"


## Speed in the user's unit from m/s, and the unit label.
func speed_text(mps: float) -> String:
	return "%d" % int(round(mps * (2.23694 if imperial() else 3.6)))


func speed_unit() -> String:
	return "MPH" if imperial() else "KM/H"


func distance_text(metres: float, decimals := 1) -> String:
	return ("%.*f" % [decimals, metres / (1609.344 if imperial() else 1000.0)])


func distance_unit() -> String:
	return "MI" if imperial() else "KM"
