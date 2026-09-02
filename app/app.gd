extends Node
## Autoload "App". Carries state between screens and persists settings.

const SETTINGS_PATH := "user://settings.cfg"
const SECRETS_PATH := "user://secrets.cfg"
const INSTALL_KEY_PATH := "user://install.key"
const USER_WORKOUTS_DIR := "user://workouts"

var workout: Workout
var ftp: int = 200
var camera_shake := "low"   # off | low | high
var last_ride_journal := ""

var _cfg := ConfigFile.new()
var _secrets := ConfigFile.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_WORKOUTS_DIR))
	if _cfg.load(SETTINGS_PATH) == OK:
		ftp = int(_cfg.get_value("rider", "ftp", ftp))
		camera_shake = str(_cfg.get_value("scene", "camera_shake", camera_shake))
	_secrets.load_encrypted_pass(SECRETS_PATH, _install_key())
	Sync.configure_intervals.call_deferred(get_secret("intervals_api_key"))


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
		out.append({"journal": path, "fit": path.get_basename() + ".fit", "meta": j.meta, "samples": j.samples.size(), "finished": j.has("end")})
	return out


func save_settings() -> void:
	_cfg.set_value("rider", "ftp", ftp)
	_cfg.set_value("scene", "camera_shake", camera_shake)
	_cfg.save(SETTINGS_PATH)


## Bundled and user-added workout files.
func list_workout_files() -> Array[String]:
	var out: Array[String] = []
	for dir_path in ["res://workouts", USER_WORKOUTS_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() == "zwo":
				out.append(dir_path.path_join(f))
	out.sort()
	return out


func go_to(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)
