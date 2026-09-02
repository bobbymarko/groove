extends Node
## Autoload "App". Carries state between screens and persists settings.

const SETTINGS_PATH := "user://settings.cfg"
const USER_WORKOUTS_DIR := "user://workouts"

var workout: Workout
var ftp: int = 200
var camera_shake := "low"   # off | low | high

var _cfg := ConfigFile.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_WORKOUTS_DIR))
	if _cfg.load(SETTINGS_PATH) == OK:
		ftp = int(_cfg.get_value("rider", "ftp", ftp))
		camera_shake = str(_cfg.get_value("scene", "camera_shake", camera_shake))


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
