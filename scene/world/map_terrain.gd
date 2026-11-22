class_name MapTerrain
extends TerrainStreamer
## The real ground around a route (R42): square tiles of elevation data around
## the rider (finer near, coarser far), the trail cut or filled into it along
## the route's real shape, a fine ribbon for the trail itself, and a far ring
## out to the horizon. Plants come from the same biomes as the strip world,
## placed in world space. Uses TerrainStreamer's materials and plant meshes.

const TILE := 64.0
const REACH := 704.0          ## tiles kept within this distance of the rider
const FLORA_REACH := 330.0    ## tiles with plants (trees fade out by ~300 m)
const BED := 4.0              ## within this of the path the ground is the trail's bed
const BLEND_OUT := 16.0       ## ...blending back to the real ground by here
const FAR_IN := 640.0
const FAR_OUT := 7000.0

var rt: RouteTrail
var dem: RouteDem
var _tiles: Dictionary = {}       ## Vector2i -> {node, lod, flora}
var _queue: Array = []            ## [{key, lod, flora, d}] nearest first
var _job: Thread
var _ribbon: MeshInstance3D
var _ring: MeshInstance3D
var _ring_at := Vector2(INF, INF)
var _rider := Vector2.ZERO
var _first := true


func _init(t: RouteTrail, d: RouteDem) -> void:
	super(t)
	rt = t
	dem = d


func height(x: float, z: float, _t: Trail = null) -> float:
	var h := dem.height(x, z)
	var n := rt.nearest(x, z, BLEND_OUT)
	if n.z == 0.0:
		return h
	var a := absf(n.y)
	var groove := 0.0
	if a < TRAIL_HALF_WIDTH:
		groove = -GROOVE_DEPTH * (1.0 - pow(a / TRAIL_HALF_WIDTH, 2.0))
	elif a < TRAIL_HALF_WIDTH + BANK_WIDTH:
		groove = 0.09 * sin(PI * (a - TRAIL_HALF_WIDTH) / BANK_WIDTH)
	var bed := rt.h_at(n.x) + groove
	return lerpf(bed, h, smoothstep(BED, BLEND_OUT, a))


func surface(x: float, z: float, t: Trail = null) -> float:
	return height(x, z, t)


func rebuild() -> void:
	for k in _tiles.keys():
		(_tiles[k].node as Node).queue_free()
	_tiles.clear()
	_queue.clear()


func _lod_for(d: float) -> float:
	return 2.0 if d < 192.0 else (4.0 if d < 416.0 else 8.0)


func update_around(z: float) -> void:
	var p := rt.position_at(z)
	_rider = Vector2(p.x, p.z)
	var c := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	var r := int(ceil(REACH / TILE))
	var want := {}
	for ix in range(c.x - r, c.x + r + 1):
		for iz in range(c.y - r, c.y + r + 1):
			var centre := Vector2((ix + 0.5) * TILE, (iz + 0.5) * TILE)
			var d := centre.distance_to(_rider)
			if d > REACH:
				continue
			var key := Vector2i(ix, iz)
			var lod := _lod_for(d)
			var fl := d < FLORA_REACH
			want[key] = true
			var have: Variant = _tiles.get(key)
			# Rebuild only when the detail must rise, or plants must appear;
			# coarser-than-needed far tiles are kept a while (no churn).
			if have == null or lod < float(have.lod) or (fl and not have.flora) or lod > float(have.lod) * 2.0:
				_enqueue(key, lod, fl, d)
	for key in _tiles.keys():
		if not want.has(key):
			(_tiles[key].node as Node).queue_free()
			_tiles.erase(key)
	if _first:
		_first = false
		# The ground under the rider must exist on the first frame.
		for q in _queue.duplicate():
			if q.d < 100.0:
				_finish_tile(_build_tile(q.key, q.lod, q.flora))
				_queue.erase(q)
	_update_ribbon(z)
	_update_far()
	_pump_tiles()


func _enqueue(key: Vector2i, lod: float, fl: bool, d: float) -> void:
	for q in _queue:
		if q.key == key:
			q.lod = lod
			q.flora = fl
			q.d = d
			return
	_queue.append({"key": key, "lod": lod, "flora": fl, "d": d})


func _pump_tiles() -> void:
	if _job != null:
		if _job.is_alive():
			return
		var res: Dictionary = _job.wait_to_finish()
		_job = null
		_apply_job(res)
	if _queue.is_empty():
		return
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var q: Dictionary = _queue.pop_front()
	_job = Thread.new()
	_job.start(_build_tile.bind(q.key, q.lod, q.flora))


func _apply_job(res: Dictionary) -> void:
	match res.get("kind", "tile"):
		"tile":
			_finish_tile(res)
		"ribbon":
			_finish_ribbon(res)
		"far":
			_finish_far(res)


func _process(_delta: float) -> void:
	if _job != null and not _job.is_alive():
		_pump_tiles()


func _exit_tree() -> void:
	if _job != null:
		_job.wait_to_finish()


# --- tiles ------------------------------------------------------------------------

## Worker: one tile's ground (with skirts) and, near the rider, its plants.
func _build_tile(key: Vector2i, lod: float, with_flora: bool) -> Dictionary:
	var x0 := key.x * TILE
	var z0 := key.y * TILE
	var n := int(TILE / lod)
	var W := n + 3                       # one extra ring for normals
	var hs := PackedFloat32Array()
	hs.resize(W * W)
	for j in W:
		for i in W:
			var x := x0 + (i - 1) * lod
			var z := z0 + (j - 1) * lod
			hs[j * W + i] = height(x, z) - _under_ribbon(x, z)
	var centre := rt.nearest_far(x0 + TILE * 0.5, z0 + TILE * 0.5)
	var pair := _ground_pair(centre.x)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var lat := PackedFloat32Array()
	var share := PackedFloat32Array()
	lat.resize((n + 1) * (n + 1))
	share.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := x0 + i * lod
			var z := z0 + j * lod
			var near := rt.nearest(x, z, 60.0)
			# Unsigned: a side flip between grid points would interpolate through 0
			# and paint a thin false path across the field.
			lat[j * (n + 1) + i] = minf(absf(near.y), 60.0) if near.z > 0.0 else 60.0
			share[j * (n + 1) + i] = _ground_b_share(near.x if near.z > 0.0 else centre.x, pair)
	for j in n + 1:
		for i in n + 1:
			var h := hs[(j + 1) * W + i + 1]
			verts.append(Vector3(x0 + i * lod, h, z0 + j * lod))
			var dx := hs[(j + 1) * W + i + 2] - hs[(j + 1) * W + i]
			var dz := hs[(j + 2) * W + i + 1] - hs[j * W + i + 1]
			norms.append(Vector3(-dx, 2.0 * lod, -dz).normalized())
			uvs.append(Vector2(lat[j * (n + 1) + i], share[j * (n + 1) + i]))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])
	# Skirts: a strip hanging 3 m down from each edge hides seams between detail levels.
	for side in 4:
		var start_v := verts.size()
		for k in n + 1:
			var ii: int = k if side < 2 else (n if side == 2 else 0)
			var jj: int = (0 if side == 0 else n) if side < 2 else k
			var v := verts[jj * (n + 1) + ii]
			verts.append(v)
			norms.append(norms[jj * (n + 1) + ii])
			uvs.append(uvs[jj * (n + 1) + ii])
			verts.append(v - Vector3(0, 3.0, 0))
			norms.append(norms[jj * (n + 1) + ii])
			uvs.append(uvs[jj * (n + 1) + ii])
		for k in n:
			var a := start_v + k * 2
			idx.append_array([a, a + 2, a + 1, a + 2, a + 3, a + 1, a, a + 1, a + 2, a + 2, a + 1, a + 3])   # both faces
	var out := {"kind": "tile", "key": key, "lod": lod, "flora": with_flora, "pair": pair,
		"verts": verts, "norms": norms, "uvs": uvs, "idx": idx}
	if with_flora and flora:
		out["plants"] = _scatter_tile(x0, z0, centre.x)
	return out


func _finish_tile(r: Dictionary) -> void:
	var key: Vector2i = r.key
	if _tiles.has(key):
		(_tiles[key].node as Node).queue_free()
	var root := Node3D.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = r.verts
	a[Mesh.ARRAY_NORMAL] = r.norms
	a[Mesh.ARRAY_TEX_UV] = r.uvs
	a[Mesh.ARRAY_INDEX] = r.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _chunk_ground_material(r.pair)
	root.add_child(mi)
	if r.has("plants"):
		for id in r.plants:
			_add_tile_flora(root, r.plants[id], floras.get(id, flora))
	add_child(root)
	_tiles[key] = {"node": root, "lod": r.lod, "flora": r.flora}


## How far the ground mesh sinks under the trail ribbon: the ribbon carries
## the groove and banks, which a 2-8 m grid cannot, so the grid stays just
## beneath it instead of poking through.
func _under_ribbon(x: float, z: float) -> float:
	var n := rt.nearest(x, z, 3.0)
	if n.z == 0.0:
		return 0.0
	return 0.35 * (1.0 - smoothstep(1.6, 2.4, absf(n.y)))


## Plants for one tile from the biomes around its nearest trail point.
func _scatter_tile(x0: float, z0: float, s: float) -> Dictionary:
	var out := {}
	var ids: Array[String] = []
	for zz in [s - BiomeMap.BLEND, s, s + BiomeMap.BLEND]:
		var w := biome_map.at(zz)
		for sg in [w.a, w.b]:
			if not ids.has(sg.id):
				ids.append(sg.id)
	var map := biome_map
	var trail_ref := rt
	for id in ids:
		var own := Callable()
		if map.segments.size() > 1:
			own = func(x: float, z: float) -> Vector3:
				var nn := trail_ref.nearest(x, z, 400.0)
				var sz := nn.x if nn.z > 0.0 else s
				var sg := map.owner(x, sz)
				var mix := 1.0 if sg.mix == "conifer" else (2.0 if sg.mix == "broad" else 0.0)
				return Vector3(1.0 if sg.id == id else 0.0, float(sg.trees), mix)
		var near := func(x: float, z: float) -> float:
			var nn := trail_ref.nearest(x, z, 80.0)
			return absf(nn.y) if nn.z > 0.0 else 999.0
		out[id] = (floras[id] as RealFlora).scatter_area(x0, z0, TILE, near, height.bind(null), own, TRAIL_HALF_WIDTH + BANK_WIDTH)
	return out


func _add_tile_flora(root: Node3D, placed: Dictionary, fl: RealFlora) -> void:
	for mi in placed:
		var xfs: Array[Transform3D] = placed[mi][0]
		var tints: Array[Color] = placed[mi][1]
		if xfs.is_empty():
			continue
		var idx: Array = range(xfs.size())
		var mid := Vector3.ZERO
		for t in xfs:
			mid += t.origin
		mid /= float(xfs.size())
		_flora_band(root, mi, xfs, tints, idx, mid, fl)


# --- the trail ribbon -------------------------------------------------------------

## The trail surface itself, fine enough for the groove and banks (0.25 m
## across), on every part of the route within RIBBON_R of the rider (a route
## that passes a junction twice shows both roads). Rebuilt every 300 m.
const RIBBON_R := 700.0
var _ribbon_at := Vector2(INF, INF)


func _update_ribbon(_z: float) -> void:
	if _ribbon != null and _rider.distance_to(_ribbon_at) < 300.0:
		return
	_ribbon_at = _rider
	_finish_ribbon(_build_ribbon(_rider))


func _build_ribbon(c: Vector2) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var across := 18
	var half := 2.2
	var n := rt.sample_count()
	var r2 := (RIBBON_R + 300.0) * (RIBBON_R + 300.0)
	var i := 0
	while i < n:
		# One run of consecutive samples near the rider.
		if rt.sample_xz(i).distance_squared_to(c) > r2:
			i += 1
			continue
		var rows := 0
		var base := verts.size()
		var z := rt.sample_z(i)
		while i < n and rt.sample_xz(i).distance_squared_to(c) <= r2:
			var near_rider := rt.sample_xz(i).distance_to(c) < 160.0
			var sub := 4 if near_rider else 1          # 0.5 m rows close by, 2 m beyond
			for k in sub:
				var zz := z + k * (RouteTrail.STEP_R / sub)
				var p := rt.position_at(zz)
				var hd := rt.heading_at(zz)
				var side := Vector3(-hd.z, 0.0, hd.x).normalized()
				var pair := _ground_pair(zz)
				for a in across + 1:
					var o := lerpf(-half, half, float(a) / across)
					var q := p + side * o
					verts.append(Vector3(q.x, height(q.x, q.z) + 0.03, q.z))
					norms.append(Vector3.UP)
					uvs.append(Vector2(o, _ground_b_share(zz, pair)))
				rows += 1
			i += 1
			z = rt.sample_z(i)
		for row in rows - 1:
			for a in across:
				var v := base + row * (across + 1) + a
				var w := v + across + 1
				idx.append_array([v, v + 1, w + 1, v, w + 1, w])
	return {"kind": "ribbon", "verts": verts, "norms": norms, "uvs": uvs, "idx": idx,
		"pair": _ground_pair(rt.nearest_far(c.x, c.y).x)}


func _finish_ribbon(r: Dictionary) -> void:
	if (r.verts as PackedVector3Array).is_empty():
		return
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = r.verts
	a[Mesh.ARRAY_NORMAL] = r.norms
	a[Mesh.ARRAY_TEX_UV] = r.uvs
	a[Mesh.ARRAY_INDEX] = r.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if _ribbon == null:
		_ribbon = MeshInstance3D.new()
		_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ribbon)
	_ribbon.mesh = m
	_ribbon.material_override = _chunk_ground_material(r.pair)


# --- the far ring -----------------------------------------------------------------

## Real hills out to the horizon: a ring of rings around the rider, rebuilt
## every 600 m. Sits a little low so the near tiles always win where they overlap.
func _update_far() -> void:
	if _ring != null and _rider.distance_to(_ring_at) < 600.0:
		return
	_ring_at = _rider
	_finish_far(_build_far(_rider))


func _build_far(c: Vector2) -> Dictionary:
	var rings := 40
	var segs := 120
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for ri in rings + 1:
		var r := FAR_IN * pow(FAR_OUT / FAR_IN, float(ri) / rings)
		for si in segs:
			var a := TAU * si / segs
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			verts.append(Vector3(x, dem.height(x, z) - 1.5, z))
			uvs.append(Vector2(60.0, 0.0))
	for ri in rings:
		for si in segs:
			var a := ri * segs + si
			var b := ri * segs + (si + 1) % segs
			var cc := a + segs
			var d := b + segs
			idx.append_array([a, cc, d, a, d, b])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	return {"kind": "far", "mesh_arrays": st.commit_to_arrays()}


func _finish_far(r: Dictionary) -> void:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.mesh_arrays)
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	_ring.mesh = m
	_ring.material_override = _material
