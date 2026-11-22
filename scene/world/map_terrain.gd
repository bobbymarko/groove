class_name MapTerrain
extends TerrainStreamer
## The real ground around a route (R42): square tiles of elevation data around
## the rider (finer near, coarser far), the trail cut or filled into it along
## the route's real shape, a fine ribbon for the trail itself, and a far ring
## out to the horizon. Plants come from the same biomes as the strip world,
## placed in world space. Uses TerrainStreamer's materials and plant meshes.
## With a cover grid (stage 2) woods, fields and scrub stand where the map has
## them, lakes and rivers are water with their beds carved out, and the trail
## crosses on timber bridges.

const TILE := 64.0
const REACH := 704.0          ## tiles kept within this distance of the rider
const FLORA_REACH := 448.0    ## tiles with plants (trees, as flat pictures, dither away over the last 60 m)
const BED := 4.0              ## within this of the path the ground is the trail's bed
const BLEND_OUT := 16.0       ## ...blending back to the real ground by here
const DETAIL_RANGE := 60.0    ## real trees within this, flat pictures beyond (a full circle of them, not a strip)
const DECK_IN := 3.0          ## the trail's bed and ribbon run this far under each end of a bridge deck
const FAR_IN := 640.0
const FAR_OUT := 7000.0

var rt: RouteTrail
var dem: RouteDem
var grid: CoverGrid               ## null: plants by the route's biomes alone
var _bridges: Dictionary = {}     ## index in rt.bridges -> MeshInstance3D
var _tiles: Dictionary = {}       ## Vector2i -> {node, lod, flora}
var _queue: Array = []            ## [{key, lod, flora, d}] nearest first
var _job: Thread
var _ribbon: MeshInstance3D
var _ring: MeshInstance3D
var _ring_water: MeshInstance3D
var _ring_at := Vector2(INF, INF)
var _rider := Vector2.ZERO
var _rider_s := 0.0               ## the rider's distance along the trail
var _first := true


func _init(t: RouteTrail, d: RouteDem, g: CoverGrid = null) -> void:
	super(t)
	rt = t
	dem = d
	grid = g if g != null and not g.is_empty() else null


func use_real_ground(kind: String, plants: RealFlora) -> void:
	super(kind, plants)
	# Trees are gone before the tile that would bring them in can appear (a tile's corner is 45 m nearer than its middle).
	RealFlora.set_ranges(DETAIL_RANGE, FLORA_REACH - 48.0)
	if grid != null and grid.has_water() and _water_material == null:
		_make_water_materials("river")


func height(x: float, z: float, _t: Trail = null) -> float:
	return _height_near(x, z, rt.nearest(x, z, BLEND_OUT))


## The ground at (x, z), given the trail's nearest point n (RouteTrail.nearest).
func _height_near(x: float, z: float, n: Vector3) -> float:
	var h := dem.height(x, z)
	if grid != null:
		h = _wet(h, x, z)
	if n.z == 0.0 or absf(n.y) >= BLEND_OUT:
		return h
	# On a bridge the ground below is the river's; the deck carries the trail.
	var keep := 1.0 - smoothstep(DECK_IN, DECK_IN + 3.0, rt.bridge_depth(n.x))
	if keep <= 0.0:
		return h
	var a := absf(n.y)
	var groove := 0.0
	if a < TRAIL_HALF_WIDTH:
		groove = -GROOVE_DEPTH * (1.0 - pow(a / TRAIL_HALF_WIDTH, 2.0))
	elif a < TRAIL_HALF_WIDTH + BANK_WIDTH:
		groove = 0.09 * sin(PI * (a - TRAIL_HALF_WIDTH) / BANK_WIDTH)
	var bed := rt.h_at(n.x) + groove
	return lerpf(h, lerpf(bed, h, smoothstep(BED, BLEND_OUT, a)), keep)


## For RealGrass (see TerrainStreamer.grass_at): real ground, the trail's
## groove left out; no grass in water, thin grass on bare rock and snow.
func grass_at(x: float, z: float) -> Vector4:
	var n := rt.nearest(x, z, 30.0)
	var ad := absf(n.y) if n.z > 0.0 else 30.0
	var h := _height_near(x, z, n)
	if ad < BLEND_OUT and rt.bridge_depth(n.x) <= 0.0:
		h -= _groove(ad) * (1.0 - smoothstep(BED, BLEND_OUT, ad))
	var sg: Dictionary = biome_map.segments[0]
	if biome_map.segments.size() > 1:
		# Away from the trail: the biome where the rider is (a wide search for every spot would cost too much).
		sg = biome_map.owner(x, n.x if n.z > 0.0 else _rider_s)
	var id: String = sg.id
	var thick := float(RealFlora.BIOMES[id].grass_density)
	if grid != null:
		thick *= 1.0 - smoothstep(0.05, 0.2, grid.water_at(x, z))
		var k := grid.kind_at(x, z)
		if k == CoverGrid.BARREN or k == CoverGrid.SNOW:
			thick *= 0.1
	if n.z > 0.0 and rt.bridge_depth(n.x) > 0.0 and ad < 3.0:
		thick = 0.0
	return Vector4(h, ad, thick, float(maxi(_grass_ids.find(id), 0)))


## What the wheels roll on: the deck on a bridge, else the ground.
func surface(x: float, z: float, t: Trail = null) -> float:
	if not rt.bridges.is_empty():
		var n := rt.nearest(x, z, BridgeGen.DECK_HALF)
		if n.z > 0.0 and rt.bridge_depth(n.x) > 0.0:
			return rt.h_at(n.x)
	return height(x, z, t)


## Ground under and beside water: a lake or river bed 1.2 m down, its shore
## held just above the water so the two never shimmer through each other.
func _wet(h: float, x: float, z: float) -> float:
	var w := grid.water_at(x, z)
	if w <= 0.0:
		return h
	var lv := grid.level_at(x, z)
	if is_nan(lv):
		return h
	var g := maxf(h, lv + 0.1 * smoothstep(0.0, 0.1, w) * (1.0 - smoothstep(0.2, 0.3, w)))
	return lerpf(g, minf(g, lv - 1.2), smoothstep(0.2, 0.5, w))


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
	_rider_s = z
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
	_update_bridges()
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
	if grid != null and grid.water_in(Rect2(x0, z0, TILE, TILE)):
		out["water"] = _lake_arrays(x0, z0, maxf(lod, 4.0))
		out["frozen"] = _frozen_at(centre.x)
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
	if r.has("water") and not (r.water.verts as PackedVector3Array).is_empty():
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = r.water.verts
		wa[Mesh.ARRAY_NORMAL] = r.water.norms
		wa[Mesh.ARRAY_TEX_UV] = r.water.uvs
		wa[Mesh.ARRAY_INDEX] = r.water.idx
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wm
		wmi.material_override = _ice_material if r.frozen else _water_material
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wmi)
	if r.has("plants"):
		for id in r.plants:
			_add_tile_flora(root, r.plants[id], floras.get(id, flora), float(r.lod) <= 2.0)
	add_child(root)
	_tiles[key] = {"node": root, "lod": r.lod, "flora": r.flora}


## Worker: the water surface over one tile, step metres a square, wherever
## any corner is wet. Flat at each lake's level; rivers follow their valley.
func _lake_arrays(x0: float, z0: float, step: float) -> Dictionary:
	var n := int(TILE / step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var wet := PackedFloat32Array()
	var lvl := PackedFloat32Array()
	wet.resize((n + 1) * (n + 1))
	lvl.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := x0 + i * step
			var z := z0 + j * step
			wet[j * (n + 1) + i] = grid.water_at(x, z)
			lvl[j * (n + 1) + i] = grid.level_at(x, z)
	for j in n:
		for i in n:
			var c := [j * (n + 1) + i, j * (n + 1) + i + 1, (j + 1) * (n + 1) + i, (j + 1) * (n + 1) + i + 1]
			var any := false
			var level := NAN
			for k in c:
				if wet[k] > 0.15:
					any = true
				if not is_nan(lvl[k]):
					level = lvl[k] if is_nan(level) else minf(level, lvl[k])
			if not any or is_nan(level):
				continue
			var base := verts.size()
			for k in 4:
				var vi: int = c[k]
				var y := lvl[vi] if not is_nan(lvl[vi]) else level
				verts.append(Vector3(x0 + (i + (k & 1)) * step, y, z0 + (j + (k >> 1)) * step))
				norms.append(Vector3.UP)
				uvs.append(Vector2(verts[-1].x, verts[-1].z) * 0.1)
			idx.append_array([base, base + 1, base + 3, base, base + 3, base + 2])
	return {"verts": verts, "norms": norms, "uvs": uvs, "idx": idx}


## How far the ground mesh sinks under the trail ribbon: the ribbon carries
## the groove and banks, which a 2-8 m grid cannot, so the grid stays just
## beneath it instead of poking through.
func _under_ribbon(x: float, z: float) -> float:
	var n := rt.nearest(x, z, 3.0)
	if n.z == 0.0 or rt.bridge_depth(n.x) > 0.0:
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
	var cover := grid
	for id in ids:
		var own := Callable()
		if cover != null:
			own = func(x: float, z: float) -> Vector3:
				var nn := trail_ref.nearest(x, z, 400.0)
				var sz := nn.x if nn.z > 0.0 else s
				var sg := map.owner(x, sz)
				if sg.id != id or cover.water_at(x, z) > 0.15:
					return Vector3.ZERO
				return _cover_plants(cover.kind_at(x, z), sg)
		elif map.segments.size() > 1:
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


## Vector3(1, tree density, tree mix) for a cover square: woods thick (and
## needle- or broadleaf where the map says), fields open, scrub scattered.
static func _cover_plants(k: int, sg: Dictionary) -> Vector3:
	var mix := 1.0 if sg.mix == "conifer" else (2.0 if sg.mix == "broad" else 0.0)
	match k:
		CoverGrid.FOREST_CONIFER:
			return Vector3(1.0, RealFlora.WOODS, 1.0)
		CoverGrid.FOREST_BROAD:
			return Vector3(1.0, RealFlora.WOODS, 2.0)
		CoverGrid.FOREST_MIXED:
			return Vector3(1.0, RealFlora.WOODS, mix)
		CoverGrid.OPEN:
			return Vector3(1.0, 0.12, mix)
		CoverGrid.SCRUB:
			return Vector3(1.0, 0.5, mix)
		CoverGrid.BARREN, CoverGrid.SNOW:
			return Vector3(1.0, 0.05, 1.0)
	return Vector3(1.0, float(sg.trees), mix)


## One tile's plants. Far tiles (built coarse; they are built again, finer,
## before the rider is near) carry only the trees' flat pictures. In a near
## tile each quarter gets the real versions it can need: the close-up only
## beside the trail, the middle version and its shadow within their range of it.
func _add_tile_flora(root: Node3D, placed: Dictionary, fl: RealFlora, near_tile: bool) -> void:
	var pic_xfs: Array[Transform3D] = []
	var pic_custom: Array[Color] = []
	for mi in placed:
		var xfs: Array[Transform3D] = placed[mi][0]
		var tints: Array[Color] = placed[mi][1]
		if xfs.is_empty():
			continue
		var tree := fl.picture_mesh != null and fl.picture_rows.has(mi)
		if tree:
			for i in xfs.size():
				var c := tints[i]
				c.a = float(fl.picture_rows[mi]) + 1.0
				pic_xfs.append(xfs[i])
				pic_custom.append(c)
		if not near_tile and (tree or fl.kinds[mi] != "tree"):
			continue
		var cells: Dictionary = {}
		for i in xfs.size():
			var o := xfs[i].origin
			var cell := Vector2i(floori(o.x / (TILE * 0.5)), floori(o.z / (TILE * 0.5)))
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(i)
		for cell in cells:
			var idx: Array = cells[cell]
			var mid := Vector3.ZERO
			for i in idx:
				mid += xfs[i].origin
			mid /= float(idx.size())
			var n := rt.nearest(mid.x, mid.z, 160.0)
			var off := absf(n.y) if n.z > 0.0 else 999.0       # this quarter's distance from the trail
			if tree and off > RealFlora.detail_range + RealFlora.TREE_FADE * 0.5 + BAND_PAD:
				continue
			if not tree and off > RealFlora.SMALL_FAR + BAND_PAD:
				continue
			_flora_band(root, mi, xfs, tints, idx, mid, fl, off < RealFlora.NEAR_RANGE + RealFlora.NEAR_FADE * 0.5 + BAND_PAD,
					off < RealFlora.SHADE_RANGE + RealFlora.SHADE_FADE * 0.5 + BAND_PAD)
	_picture_band(root, pic_xfs, pic_custom, fl, near_tile)


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
		# One run of consecutive samples near the rider (road a later pass
		# repeats is drawn by the first pass only, or the two flicker).
		if rt.sample_xz(i).distance_squared_to(c) > r2 or rt.is_repeat(i) or rt.bridge_depth(rt.sample_z(i)) > DECK_IN:
			i += 1
			continue
		var rows := 0
		var base := verts.size()
		var z := rt.sample_z(i)
		while i < n and rt.sample_xz(i).distance_squared_to(c) <= r2 and not rt.is_repeat(i) and rt.bridge_depth(rt.sample_z(i)) <= DECK_IN:
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
				idx.append_array([v, w + 1, v + 1, v, w, w + 1])   # facing up
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


# --- bridges ----------------------------------------------------------------------

## A timber bridge wherever the trail crosses water, built as the rider nears it.
func _update_bridges() -> void:
	for k in rt.bridges.size():
		var b: Dictionary = rt.bridges[k]
		if b.repeat:
			continue
		var zc := (float(b.from) + float(b.to)) * 0.5 + rt.start
		var p := rt.position_at(zc)
		var near := Vector2(p.x, p.z).distance_to(_rider) < RIBBON_R
		if near and not _bridges.has(k):
			var half := (float(b.to) - float(b.from)) * 0.5
			var ground := func(x: float, z: float, _t: Trail) -> float: return height(x, z)
			var mi := MeshInstance3D.new()
			mi.mesh = BridgeGen.mesh(BridgeGen.build(zc, half, 0.0, maxf(half - RouteTrail.BANK * RouteTrail.STEP_R, 1.0), rt, ground))
			mi.material_override = _wood_material
			add_child(mi)
			_bridges[k] = mi
		elif not near and _bridges.has(k):
			(_bridges[k] as Node).queue_free()
			_bridges.erase(k)


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
	var out := {"kind": "far", "mesh_arrays": st.commit_to_arrays()}
	if grid != null and grid.has_water():
		out["water"] = _far_water(c)
	return out


## Lakes and rivers beyond the tiles, out to the cover grid's edge: a flat
## square per water cell at its level (where it overlaps a tile's water the two
## are the same surface).
func _far_water(c: Vector2) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var h := CoverGrid.CELL * 0.5
	for cell in grid.water_cells(Rect2(c - Vector2(1300, 1300), Vector2(2600, 2600))):
		var p := Vector2((cell.x + 0.5) * CoverGrid.CELL, (cell.y + 0.5) * CoverGrid.CELL)
		var d := p.distance_to(c)
		if d < FAR_IN - 100.0 or d > 1300.0:
			continue
		var lv := grid.level_at(p.x, p.y)
		var base := verts.size()
		for k in 4:
			verts.append(Vector3(p.x + (h if k & 1 else -h), lv, p.y + (h if k >> 1 else -h)))
			norms.append(Vector3.UP)
			uvs.append(Vector2(verts[-1].x, verts[-1].z) * 0.1)
		idx.append_array([base, base + 1, base + 3, base, base + 3, base + 2])
	return {"verts": verts, "norms": norms, "uvs": uvs, "idx": idx}


func _finish_far(r: Dictionary) -> void:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.mesh_arrays)
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	_ring.mesh = m
	_ring.material_override = _material
	if r.has("water"):
		if _ring_water == null:
			_ring_water = MeshInstance3D.new()
			_ring_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_ring_water)
		_ring_water.visible = not (r.water.verts as PackedVector3Array).is_empty()
		if _ring_water.visible:
			var wa := []
			wa.resize(Mesh.ARRAY_MAX)
			wa[Mesh.ARRAY_VERTEX] = r.water.verts
			wa[Mesh.ARRAY_NORMAL] = r.water.norms
			wa[Mesh.ARRAY_TEX_UV] = r.water.uvs
			wa[Mesh.ARRAY_INDEX] = r.water.idx
			var wm := ArrayMesh.new()
			wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
			_ring_water.mesh = wm
			_ring_water.material_override = _ice_material if _frozen_at(rt.nearest_far(_ring_at.x, _ring_at.y).x) else _water_material
