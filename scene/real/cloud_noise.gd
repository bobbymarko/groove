class_name CloudNoise
extends Node
## Bakes the cloud noise textures on the graphics card, once per app run: each
## is drawn by cloud_bake.gdshader into its own SubViewport (a 3D texture as an
## atlas of slices), read back, and kept in static vars for every later ride.

signal baked

static var shape: ImageTexture3D       ## 128^3, Perlin-Worley base shape
static var detail: ImageTexture3D      ## 64^3, Alligator erosion
static var weather: ImageTexture        ## 512^2, coverage and cloud type
static var curl: ImageTexture           ## 128^2, turbulence offsets

const JOBS := [
	# mode, atlas size, slice size (0 = plain 2D), atlas columns
	[0, Vector2i(2048, 1024), 128, 16],
	[1, Vector2i(512, 512), 64, 8],
	[2, Vector2i(512, 512), 0, 0],
	[3, Vector2i(128, 128), 0, 0],
]


static func ready_now() -> bool:
	return shape != null


func _ready() -> void:
	if ready_now():
		baked.emit.call_deferred()
		return
	var views: Array[SubViewport] = []
	var shader := load("res://scene/real/cloud_bake.gdshader") as Shader
	for job in JOBS:
		var vp := SubViewport.new()
		vp.size = job[1]
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var rect := ColorRect.new()
		rect.size = Vector2(job[1])
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("mode", job[0])
		rect.material = mat
		vp.add_child(rect)
		add_child(vp)
		views.append(vp)
	await RenderingServer.frame_post_draw
	for i in JOBS.size():
		var job: Array = JOBS[i]
		var img := views[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		match int(job[0]):
			0: shape = _stack(img, job[2], job[3])
			1: detail = _stack(img, job[2], job[3])
			2: weather = ImageTexture.create_from_image(img)
			3: curl = ImageTexture.create_from_image(img)
		views[i].queue_free()
	baked.emit()


## Cut the atlas into its slices and stack them into a 3D texture.
static func _stack(atlas: Image, size: int, cols: int) -> ImageTexture3D:
	var slices: Array[Image] = []
	for layer in size:
		var r := Rect2i((layer % cols) * size, (layer / cols) * size, size, size)
		slices.append(atlas.get_region(r))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, size, size, size, false, slices)
	return tex
