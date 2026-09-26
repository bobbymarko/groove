class_name CampSave
extends RefCounted
## The player's rider, saved as JSON in user data. Colours are stored as hex.

const RIDER_PATH := "user://camp/rider.json"


static func load_rider() -> Dictionary:
	if not FileAccess.file_exists(RIDER_PATH):
		return MonsterPresets.FUZZ.duplicate(true)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIDER_PATH))
	if not data is Dictionary:
		return MonsterPresets.FUZZ.duplicate(true)
	return _decode(data)


static func save_rider(recipe: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RIDER_PATH.get_base_dir()))
	var f := FileAccess.open(RIDER_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(_encode(recipe), "\t"))
	return OK


static func _encode(v: Variant) -> Variant:
	if v is Color:
		return "#" + (v as Color).to_html(false)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _encode(v[k])
		return out
	if v is Array:
		return (v as Array).map(_encode)
	return v


static func _decode(v: Variant) -> Variant:
	if v is String and (v as String).begins_with("#") and (v as String).length() == 7:
		return Color(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _decode(v[k])
		return out
	if v is Array:
		return (v as Array).map(_decode)
	return v
