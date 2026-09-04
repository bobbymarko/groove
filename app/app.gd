extends Node
## Autoload "App". Carries state between screens and persists settings.

const SETTINGS_PATH := "user://settings.cfg"
const SECRETS_PATH := "user://secrets.cfg"
const INSTALL_KEY_PATH := "user://install.key"
const USER_WORKOUTS_DIR := "user://workouts"

var workout: Workout
var ftp: int = 200
var camera_shake := "low"   # off | low | high
var look_mode := "16bit"    # "8bit" (palette, low-res) | "16bit" (posterized, higher-res) | "off" (native)
var show_fps := true
var last_ride_journal := ""
var prompt_upload := false   # the summary screen asks about sharing the ride just finished
var dry_run := false         # tooling: ride without recording, screenshots or uploads

## Scene look, adjustable in Settings and on the ride screen (T). Applied by RideScene.apply_tuning().
const TUNING_SPEC := [
	# key, label, min, max, step, default
	["shadow_strength", "Shadow strength", 0.0, 1.0, 0.01, 0.93],
	["sun_elevation", "Sun elevation (°)", 5.0, 75.0, 1.0, 10.0],
	["sun_azimuth", "Sun direction (°)", 0.0, 360.0, 1.0, 40.0],
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
		camera_shake = str(_cfg.get_value("scene", "camera_shake", camera_shake))
		look_mode = str(_cfg.get_value("scene", "look_mode", "8bit" if bool(_cfg.get_value("scene", "pixel_filter", true)) else "off"))
		show_fps = bool(_cfg.get_value("scene", "show_fps", show_fps))
		for key in scene_tuning:
			scene_tuning[key] = float(_cfg.get_value("scene_tuning", key, scene_tuning[key]))
	_secrets.load_encrypted_pass(SECRETS_PATH, _install_key())
	Sync.configure_intervals.call_deferred(get_secret("intervals_api_key"))
	Sync.configure_strava.call_deferred(get_secret("strava_client_id"), get_secret("strava_client_secret"))


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
	_cfg.set_value("scene", "camera_shake", camera_shake)
	_cfg.set_value("scene", "look_mode", look_mode)
	_cfg.set_value("scene", "show_fps", show_fps)
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
