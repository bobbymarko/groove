class_name WorkoutLoader
extends RefCounted
## Opens any supported workout file by extension.

const EXTENSIONS := ["zwo", "mrc", "erg", "fit"]
const FILTER := "*.zwo, *.mrc, *.erg, *.fit ; Workout files"

static var last_error := ""


static func supported(path: String) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS


static func load_file(path: String, ftp: int) -> Workout:
	var w: Workout = null
	match path.get_extension().to_lower():
		"zwo":
			w = ZwoParser.parse_file(path)
			last_error = ZwoParser.last_error
		"mrc", "erg":
			w = ErgParser.parse_file(path, ftp)
			last_error = ErgParser.last_error
		"fit":
			w = FitWorkoutParser.parse_file(path, ftp)
			last_error = FitWorkoutParser.last_error
		_:
			last_error = "Unsupported file type .%s" % path.get_extension()
	return w
