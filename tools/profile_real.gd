extends SceneTree
## Dev helper: where the realistic look's frame time goes. One launch; each
## feature is switched off in turn from the full scene and the median frame time
## printed (the display caps the low end at its refresh rate, 8.3 ms on ProMotion).
##   tools/profile.sh [preset=summer] [at=2000] [hour=14] [route=<path>] [quality=low|medium|high] [quick]
## "quick" prints only the moving and standing baselines.

var rs: RideScene


func _initialize() -> void:
	# Never outlive the job (a script error elsewhere must not leave this rendering for good).
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("profile timed out")
		quit(3))
	_run()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.trim_prefix(key + "=")
	return fallback


func _run() -> void:
	await process_frame
	rs = RideScene.new()
	rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rs.riding = true
	rs.power = 210.0
	rs.cadence = 88.0
	rs.look_override = "real"
	rs.quality_override = _arg("quality", "")
	rs.preset_override = _arg("preset", "summer")
	rs.distance = float(_arg("at", "2000"))
	rs.hour_override = float(_arg("hour", "14"))
	var route := _arg("route", "")
	if route != "":
		rs.route = RouteLibrary.load_route(route)
	root.add_child(rs)
	for i in 300:
		await process_frame
	var vp: SubViewport = rs._viewport
	rs.real.governor_enabled = false      # this run sets the render scale itself
	print("[prof] window %s, 3D viewport %s at render scale %.2f, preset %s%s, quality %s" % [root.size, vp.size, vp.scaling_3d_scale, rs.preset_override, ", route" if route != "" else "", RealQuality.tier])
	await _measure("moving (chunks streaming)", 400)
	rs.riding = false
	for i in 90:
		await process_frame
	await _measure("BASELINE (standing)")
	if OS.get_cmdline_user_args().has("quick"):
		quit(0)
		return
	if OS.get_cmdline_user_args().has("aa"):
		# The ways to upscale and anti-alias (the look uses MetalFX spatial + TAA).
		var mode0 := vp.scaling_3d_mode
		var taa0 := vp.use_taa
		var scale0 := vp.scaling_3d_scale
		rs.riding = OS.get_cmdline_user_args().has("aamove")    # "aamove": measured (and shot) while riding
		for row: Array in [[Viewport.SCALING_3D_MODE_METALFX_SPATIAL, true, 0.67, "MetalFX spatial + TAA"],
				[Viewport.SCALING_3D_MODE_METALFX_SPATIAL, true, 0.75, "MetalFX spatial + TAA"],
				[Viewport.SCALING_3D_MODE_FSR, true, 0.67, "FSR 1 + TAA"],
				[Viewport.SCALING_3D_MODE_BILINEAR, true, 0.67, "bilinear + TAA"],
				[Viewport.SCALING_3D_MODE_METALFX_SPATIAL, false, 0.67, "MetalFX spatial, no AA"],
				[Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, false, 0.5, "MetalFX temporal"],
				[Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, false, 0.67, "MetalFX temporal"]]:
			vp.use_taa = false          # (a temporal upscaler cannot go on while TAA runs)
			vp.scaling_3d_mode = row[0]
			vp.use_taa = row[1]
			vp.scaling_3d_scale = row[2]
			await _measure("%s at %.2f" % [row[3], row[2]])
			var shot := _arg("shots", "")
			if shot != "":
				root.get_texture().get_image().save_png("%s_%s_%d.png" % [shot, str(row[3]).to_snake_case().replace(",", "").replace("+", "").replace(" ", "_"), int(row[2] * 100.0)])
		vp.scaling_3d_mode = mode0
		vp.use_taa = taa0
		vp.scaling_3d_scale = scale0
		quit(0)
		return
	var env: Environment = rs.real.env
	var sun: DirectionalLight3D = rs.real.sun
	var sky: ShaderMaterial = rs.real.sky_mat
	var plants := rs.terrain.find_children("*", "MultiMeshInstance3D", true, false)
	var grass: Array = []
	for m: MultiMeshInstance3D in plants:
		if m.is_in_group("grass") or is_equal_approx(m.visibility_range_end, RealFlora.GRASS_VISIBLE):
			grass.append(m)
	for m: MultiMeshInstance3D in grass:
		m.visible = false
	await _measure("no grass")
	for m: MultiMeshInstance3D in plants:
		m.visible = false
	await _measure("no plants at all")
	for m: MultiMeshInstance3D in plants:
		m.visible = true
	if rs.terrain.grass:
		rs.terrain.grass._eye = Vector3.INF      # (the meadow sorts out again which of its tiles show)
	for i in 3:
		await process_frame
	sun.shadow_enabled = false
	await _measure("no sun shadows")
	sun.shadow_enabled = true
	var ssao := env.ssao_enabled
	env.ssao_enabled = false
	await _measure("no ambient occlusion")
	env.ssao_enabled = ssao
	var vfog := env.volumetric_fog_enabled
	env.volumetric_fog_enabled = false
	await _measure("no volumetric fog")
	env.volumetric_fog_enabled = vfog
	var steps: Variant = sky.get_shader_parameter("cloud_steps")
	sky.set_shader_parameter("cloud_steps", 0)
	await _measure("no clouds")
	sky.set_shader_parameter("cloud_steps", int(RealQuality.get_value("cloud_steps")) if steps == null else steps)
	var glow := env.glow_enabled
	env.glow_enabled = false
	await _measure("no bloom")
	env.glow_enabled = glow
	var mode := vp.scaling_3d_mode
	var scale := vp.scaling_3d_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	await _measure("bilinear upscale")
	vp.scaling_3d_mode = mode
	for s: float in [0.5, 0.67, 0.75, 1.0]:
		if not is_equal_approx(s, scale):
			vp.scaling_3d_scale = s
			await _measure("render scale %.2f" % s)
	vp.scaling_3d_scale = scale
	await _measure("BASELINE again")
	quit(0)


func _measure(label: String, frames := 300) -> void:
	for i in 45:
		await process_frame
	var dts: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		dts.append(float(now - last) / 1000.0)
		last = now
	dts.sort()
	var med := dts[dts.size() / 2]
	print("[prof] %-32s median %5.2f ms (%3.0f fps)  p95 %5.2f  max %6.2f | %.2fM triangles, %d draw calls" % [
		label, med, 1000.0 / med, dts[int(dts.size() * 0.95)], dts[-1],
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
