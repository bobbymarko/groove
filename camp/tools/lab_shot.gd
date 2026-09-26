extends SceneTree
## Render Camp's style lab to PNG, then quit.
##   -- <mode> <out.png> [frames=N] [t=seconds]
## With frames=N it writes out_000.png ... at 30 fps for a clip.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("no-radio"):
		args.remove_at(args.find("no-radio"))
	if args.size() < 2:
		push_error("usage: -- <mode> <out.png> [frames=N] [t=seconds]")
		quit(2)
		return
	_run(args)


func _run(args: PackedStringArray) -> void:
	await process_frame
	var frames := 1
	var t := 0.3
	for a in args:
		if a.begins_with("frames="):
			frames = int(a.trim_prefix("frames="))
		elif a.begins_with("t="):
			t = float(a.trim_prefix("t="))
	var lab := StyleLab.new()
	lab.mode = args[0]
	root.add_child(lab)
	for i in 4:
		await process_frame
	var out: String = args[1]
	for f in frames:
		lab.set_time(t + f / 30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := out if frames == 1 else out.get_basename() + "_%03d.png" % f
		img.save_png(path)
	print("screenshot %s -> %s (%d frames)" % [args[0], out, frames])
	quit(0)
