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
	print("[dbg] mode '%s' user args %s" % [mode, OS.get_cmdline_user_args()])
	var app: Node = root.get_node("App")
	var devices: Node = root.get_node("Devices")
	var ride := mode == "ride"
	if ride:
		var wpath := "res://workouts/cadence_today.zwo"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("workout="):
				wpath = a.trim_prefix("workout=")
		app.workout = ZwoParser.parse_file(wpath)
		app.dry_run = true   # never record preview rides into the real library
		devices.use_simulated_devices()
	var fake: RideRecorder = null
	if mode == "summary" and OS.get_cmdline_user_args().has("latest"):
		# The real latest ride (it has screenshots); nothing synthetic.
		var rides: Array = app.list_rides()
		if not rides.is_empty():
			app.last_ride_journal = str(rides[0].journal)
	elif mode == "summary" or OS.get_cmdline_user_args().has("fake"):
		fake = _fake_ride()
		if mode == "summary":
			app.last_ride_journal = fake.journal_path()
	var scene: Node
	if mode == "scene":
		# Standalone scene preview with demo telemetry.
		var rs := RideScene.new()
		rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rs.riding = true
		rs.power = 210.0
		rs.cadence = 88.0
		if OS.get_cmdline_user_args().has("stopped"):
			rs.power = 0.0
			rs.cadence = 0.0
		rs.debug_top_down = OS.get_cmdline_user_args().has("top")
		rs.debug_closeup = OS.get_cmdline_user_args().has("closeup") or OS.get_cmdline_user_args().has("hands")
		rs.debug_hands = OS.get_cmdline_user_args().has("hands")
		for a in OS.get_cmdline_user_args():
			if a.begins_with("preset="):
				rs.preset_override = a.trim_prefix("preset=")
			if a.begins_with("hour="):
				rs.hour_override = float(a.trim_prefix("hour="))
			if a.begins_with("rain="):
				rs.rain_override = float(a.trim_prefix("rain="))
				rs._rain = rs.rain_override
			if a.begins_with("effort="):
				rs.effort = float(a.trim_prefix("effort="))
		for opt in ["nocull", "plain"]:
			if OS.get_cmdline_user_args().has(opt):
				rs.debug_material = opt
		scene = rs
		root.add_child(scene)
		if OS.get_cmdline_user_args().has("nofilter"):
			rs.set_look_mode("off")
		for a in OS.get_cmdline_user_args():
			if a.begins_with("look="):
				rs.set_look_mode(a.trim_prefix("look="))
			if a.begins_with("fog="):
				var tuned: Dictionary = root.get_node("App").scene_tuning.duplicate()
				tuned["fog_density"] = float(a.trim_prefix("fog="))
				rs.apply_tuning(tuned)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("lean="):
				rs.rider.lean_amount = float(a.trim_prefix("lean="))
			if a.begins_with("faxis="):
				var mb1 := rs.rider.find_child("RiderBody", true, false)
				var v := a.trim_prefix("faxis=")
				var ax := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK, "-x": Vector3.LEFT, "-y": Vector3.DOWN, "-z": Vector3.FORWARD}
				if mb1 and ax.has(v):
					mb1.finger_axis = ax[v]
			if a.begins_with("sign="):
				var mb0 := rs.rider.find_child("RiderBody", true, false)
				if mb0:
					mb0.lean_sign = float(a.trim_prefix("sign="))
		for a in OS.get_cmdline_user_args():
			if a.begins_with("horde=") and rs.horde:
				for i in int(a.trim_prefix("horde=")):
					rs.horde.spawn(rs.distance, 4.0 + 2.5 * i)
			if a.begins_with("weapon="):
				await process_frame   # the rig poses on its first frame; attach after
				rs.rider.set_weapon(int(a.trim_prefix("weapon=")))
				if rs.horde:
					rs.horde.weapon_tier = int(a.trim_prefix("weapon="))
		for i in 240:
			await process_frame
			if i == 228:
				for a in OS.get_cmdline_user_args():
					if a.begins_with("punch="):
						rs.camera.punch(float(a.trim_prefix("punch=")))   # ~0.6 s before capture: mid-swing
		var rp: Vector3 = rs.rider.global_position
		print("[dbg] rider %s heading %s grade %.1f speed %.1f" % [rp, rs.trail.heading_at(rs.distance), rs.trail.grade_at(rs.distance), rs.physics.speed])
		print("[dbg] camera %s fov %.1f dist %.1f height %.1f" % [rs.camera.global_position, rs.camera.fov, rs.camera.follow_distance, rs.camera.follow_height])
		print("[dbg] rider scale %s; rear wheel %s" % [rs.rider.global_transform.basis.get_scale(), rs.rider.get_child(1).global_position])
		var mb := rs.rider.find_child("RiderBody", true, false)
		if mb and mb.skeleton:
			print("[dbg] skeleton xform %s" % mb.skeleton.global_transform)
			for bn in ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftArm", "LeftForeArm", "LeftHand"]:
				print("[dbg] bone %-12s pose %s  rest %s" % [bn, mb.skeleton.get_bone_global_pose(mb._bones[bn]).origin, mb.skeleton.get_bone_global_rest(mb._bones[bn]).origin])
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
		if OS.get_cmdline_user_args().has("unlinked"):
			root.get_node("Sync").intervals().api_key = ""   # render only; the saved key is untouched
			root.get_node("Sync").calendar.preview = true
		if mode == "calendar":
			# Fake intervals.icu planned workouts so the home screen shows its day sections.
			var sync: Node = root.get_node("Sync")
			if not sync.intervals().is_configured():
				sync.intervals().api_key = "preview"
			var t: String = IntervalsCalendar.today()
			var z := "res://workouts/cadence_today.zwo"
			var rows: Array[Dictionary] = [
				{"id": "1", "date": t, "name": "Today", "type": "Ride", "path": z},
				{"id": "2", "date": IntervalsCalendar.date_offset(t, 1), "name": "Tomorrow", "type": "Ride", "path": z},
				{"id": "3", "date": IntervalsCalendar.date_offset(t, 3), "name": "Later", "type": "Ride", "path": z},
				{"id": "4", "date": IntervalsCalendar.date_offset(t, 3), "name": "Later 2", "type": "Ride", "path": z},
			]
			sync.calendar.set_preview(rows)
		scene = load(scene_path).instantiate()
		root.add_child(scene)
		if mode == "" or mode == "plain":
			for i in 80:   # let the home tiles finish cascading in
				await process_frame
		if mode == "sheet":
			await process_frame
			scene.get_node("WorkoutSheet").open(ZwoParser.parse_file("res://workouts/cadence_today.zwo"))
			for i in 30:
				await process_frame
			if OS.get_cmdline_user_args().has("scenes"):
				scene.get_node("WorkoutSheet").choose_scene(false)
				for i in 30:
					await process_frame
		if OS.get_cmdline_user_args().has("unlinked"):
			root.get_node("Sync").intervals().api_key = ""   # render only; the saved key is untouched
			root.get_node("Sync").calendar.preview = true
		if mode == "calendar":
			for i in 110:
				await process_frame
		if mode in ["settings", "devices", "rides", "licenses"]:
			await process_frame
			scene.call("open_" + mode)
			for i in 30:
				await process_frame
			if mode == "settings" and OS.get_cmdline_user_args().has("look"):
				scene.find_child("SettingsPanel", true, false).show_page(1)
			if mode == "rides" and OS.get_cmdline_user_args().has("detail"):
				var rides: Array = root.get_node("App").list_rides()
				print("[dbg] rides %d, sheet visible %s" % [rides.size(), scene.get_node("SideSheet").visible])
				if not rides.is_empty():
					# Loaded at run time: this script compiles before the autoloads RidesPanel refers to exist.
					load("res://ui/panels/rides_panel.gd").open_ride(scene.get_node("SideSheet"), rides[0])
					print("[dbg] detail opened, sheet visible %s" % scene.get_node("SideSheet").visible)
			for i in 40:
				await process_frame
	if ride:
		await process_frame
		var runner: WorkoutRunner = scene.get_node("WorkoutRunner")
		runner.time_scale = 60.0
		var rs: RideScene = scene.get_node("RideScene")
		rs.time_scale = 60.0
		runner.start()
		# "climb": run into the first hard rep (~10.5 min in) so the grade shows.
		var frames := 640 if OS.get_cmdline_user_args().has("climb") else 60
		for a in OS.get_cmdline_user_args():
			if a.begins_with("frames="):
				frames = int(a.trim_prefix("frames="))
		for i in frames:
			await process_frame
		rs.time_scale = 1.0
		if OS.get_cmdline_user_args().has("coach"):
			scene.find_child("CoachDialog", true, false).say("Rep 2 — strong and smooth, full recovery earns the next one.")
			for i in 90:
				await process_frame
		# One trainer tick so power/cadence labels are populated.
		if devices.trainer is SimulatedTrainer:
			devices.trainer.step(1.0)
			devices.trainer.step(1.0)
		if devices.heart_rate is SimulatedHeartRate:
			devices.heart_rate.step(1.0)
		# The recorder must be hearing the devices, or rides save as zeros.
		print("[dbg] recorder hears %s" % str(scene.get_node("RideRecorder").live_values()))
	for i in 5:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if fake:
		# Do not leave the synthetic ride in the real library.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fake.journal_path()))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fake.fit_path()))
	var abs := ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path
	var err := img.save_png(abs)
	print("screenshot %s -> %s" % [scene_path, abs if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


## A finished 20-minute ride with 3-minute hard reps, dated so it sorts first.
func _fake_ride() -> RideRecorder:
	var rec := RideRecorder.new()
	rec.name = "RideRecorder"
	root.add_child(rec)
	var start := int(Time.get_unix_time_from_system())
	rec.begin("Cadence: Corner Exit", 250, start)
	for i in 1200:
		var hard := (i / 60) % 3 == 1
		rec.on_power((265 if hard else 125) + (i % 9) - 4)
		rec.on_cadence(95 if hard else 85)
		rec.on_heart_rate((160 if hard else 128) + (i % 4))
		rec.on_speed(34.0 if hard else 24.0)
		rec.record_sample(float(i), start + i)
	rec.finish(true, start + 1200)
	var metrics := RideMetrics.compute(rec.samples, 250)
	var f := FileAccess.open(rec.fit_path(), FileAccess.WRITE)
	f.store_buffer(FitEncoder.encode(rec.meta, rec.samples, metrics, true))
	f.close()
	return rec
