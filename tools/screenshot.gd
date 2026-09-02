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
	_run(args[0], args[1], args[2] if args.size() > 2 else "")


func _run(scene_path: String, out_path: String, mode: String) -> void:
	await process_frame
	var app: Node = root.get_node("App")
	var devices: Node = root.get_node("Devices")
	var ride := mode == "ride"
	if ride:
		app.workout = ZwoParser.parse_file("res://workouts/cadence_today.zwo")
		devices.use_simulated_devices()
	if mode == "summary":
		# Synthesize a finished 20-minute ride so the summary has data.
		var rec := RideRecorder.new()
		rec.name = "RideRecorder"
		root.add_child(rec)
		rec.begin("Cadence: Corner Exit", 250, 1756800000)
		for i in 1200:
			var hard := (i / 60) % 3 == 1
			rec.on_power((265 if hard else 125) + (i % 9) - 4)
			rec.on_cadence(95 if hard else 85)
			rec.on_heart_rate((160 if hard else 128) + (i % 4))
			rec.on_speed(34.0 if hard else 24.0)
			rec.record_sample(float(i), 1756800000 + i)
		rec.finish(true, 1756800000 + 1200)
		var metrics := RideMetrics.compute(rec.samples, 250)
		var f := FileAccess.open(rec.fit_path(), FileAccess.WRITE)
		f.store_buffer(FitEncoder.encode(rec.meta, rec.samples, metrics, true))
		f.close()
		app.last_ride_journal = rec.journal_path()
	var scene: Node
	if mode == "scene":
		# Standalone scene preview with demo telemetry.
		var rs := RideScene.new()
		rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rs.riding = true
		rs.power = 210.0
		rs.cadence = 88.0
		rs.debug_top_down = OS.get_cmdline_user_args().has("top")
		for opt in ["nocull", "plain"]:
			if OS.get_cmdline_user_args().has(opt):
				rs.debug_material = opt
		scene = rs
		root.add_child(scene)
		for i in 240:
			await process_frame
		var rp: Vector3 = rs.rider.global_position
		print("[dbg] rider %s heading %s grade %.1f speed %.1f" % [rp, rs.trail.heading_at(rs.distance), rs.trail.grade_at(rs.distance), rs.physics.speed])
		print("[dbg] camera %s" % rs.camera.global_position)
		print("[dbg] chunks: %s" % str(rs.terrain._chunks.keys()))
		for key in rs.terrain._chunks:
			var mi: MeshInstance3D = rs.terrain._chunks[key].get_child(0)
			print("[dbg] chunk %d aabb %s" % [key, mi.get_aabb()])
		for dz in [-8.0, -4.0, 0.0, 4.0, 12.0]:
			var z: float = rs.distance + float(dz)
			var tx := rs.trail.x_at(z)
			print("[dbg] z=%.1f trail x=%.2f h=%.2f | terrain h(trail)=%.2f h(-6)=%.2f h(+6)=%.2f h(-30)=%.2f h(+30)=%.2f" % [
				z, tx, rs.trail.h_at(z), rs.terrain.height(tx, z), rs.terrain.height(tx - 6.0, z), rs.terrain.height(tx + 6.0, z), rs.terrain.height(tx - 30.0, z), rs.terrain.height(tx + 30.0, z)])
	else:
		scene = load(scene_path).instantiate()
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
	if mode == "summary":
		# Do not leave the synthetic ride in the real library.
		var rec: RideRecorder = root.get_node("RideRecorder")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rec.journal_path()))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rec.fit_path()))
	var abs := ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path
	var err := img.save_png(abs)
	print("screenshot %s -> %s" % [scene_path, abs if err == OK else error_string(err)])
	quit(0 if err == OK else 1)
