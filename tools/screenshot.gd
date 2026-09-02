extends SceneTree
## Dev helper: render a scene for a few frames and save a PNG, then quit.
##   godot --path . -s tools/screenshot.gd -- res://ui/screens/home_screen.tscn build/home.png [ride]
## With "ride" as the third argument the workout is loaded onto the simulator and
## fast-forwarded a little so the HUD has live numbers.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <scene.tscn> <out.png> [ride]")
		quit(2)
		return
	_run(args[0], args[1], args.size() > 2 and args[2] == "ride")


func _run(scene_path: String, out_path: String, ride: bool) -> void:
	await process_frame
	var app: Node = root.get_node("App")
	var devices: Node = root.get_node("Devices")
	if ride:
		app.workout = ZwoParser.parse_file("res://workouts/cadence_today.zwo")
		devices.use_simulated_devices()
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	if ride:
		await process_frame
		var runner: WorkoutRunner = scene.get_node("WorkoutRunner")
		runner.time_scale = 60.0
		runner.start()
		for i in 60:
			await process_frame
		# One trainer tick so power/cadence labels are populated.
		devices.trainer.step(1.0)
		devices.trainer.step(1.0)
		devices.heart_rate.step(1.0)
	for i in 5:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var abs := ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path
	var err := img.save_png(abs)
	print("screenshot %s -> %s" % [scene_path, abs if err == OK else error_string(err)])
	quit(0 if err == OK else 1)
