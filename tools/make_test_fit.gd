extends SceneTree
## Writes a short synthetic ride as a FIT file, for checking that services
## accept our files:  godot --headless --path . -s tools/make_test_fit.gd -- build/test-ride.fit

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "build/test-ride.fit"
	var start := int(Time.get_unix_time_from_system()) - 6 * 60
	var samples: Array = []
	for i in 300:
		var hard := i >= 60 and i < 120 or i >= 180 and i < 240
		samples.append({"t": start + i, "e": i, "p": (240 if hard else 110) + (i % 7) - 3,
			"c": 92 if hard else 84, "h": (152 if hard else 118) + (i % 3), "v": 32.0 if hard else 22.0, "tg": 0, "sg": 0})
	var meta := {"started_at": start, "ftp": 250, "workout": "Ride test file"}
	var bytes := FitEncoder.encode(meta, samples, RideMetrics.compute(samples, 250), true)
	var abs := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	var f := FileAccess.open(abs, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	print("wrote %s (%d bytes, %d records)" % [abs, bytes.size(), samples.size()])
	quit(0)
