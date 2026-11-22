class_name CoverGrid
extends RefCounted
## What the land is, square by square, around a route (R42 stage 2): 20 m cells
## over everything within ~1.2 km of the route, in the route's Geo frame, from
## OpenStreetMap's shapes (RouteLandCover rasterises each stretch's answer).
## Kept as 64 x 64-cell blocks (1.28 km), only where the route goes, and saved
## zstd-compressed beside the route. Read-only once loaded, so terrain workers
## may sample it freely.

const CELL := 20.0
const BLOCK := 64
const BLOCK_M := CELL * BLOCK
const VERSION := 1

## Cell kinds (one byte each).
const NONE := 0
const OPEN := 1           ## fields, meadow, grassland, wetland
const FOREST_MIXED := 2
const FOREST_CONIFER := 3
const FOREST_BROAD := 4
const SCRUB := 5
const BARREN := 6         ## bare rock, scree, sand, beach
const SNOW := 7           ## glacier
const LAKE := 8           ## standing water: one flat level per lake
const RIVER := 9          ## flowing water: its level follows the valley

const KIND_NAMES := {"open": OPEN, "forest_mixed": FOREST_MIXED, "forest_conifer": FOREST_CONIFER,
	"forest_broad": FOREST_BROAD, "scrub": SCRUB, "barren": BARREN, "snow": SNOW}

var _blocks: Dictionary = {}      ## Vector2i block -> PackedByteArray (BLOCK * BLOCK)
var _levels: Dictionary = {}      ## Vector2i cell -> water surface height (after compute_levels)


static func is_water(k: int) -> bool:
	return k == LAKE or k == RIVER


static func is_forest(k: int) -> bool:
	return k == FOREST_MIXED or k == FOREST_CONIFER or k == FOREST_BROAD


## Which kind wins where shapes overlap: water over everything (a lake in a
## wood is a lake), then woods, scrub, rock, fields.
static func rank(k: int) -> int:
	return [0, 2, 6, 6, 6, 4, 3, 7, 9, 8][k]


func is_empty() -> bool:
	return _blocks.is_empty()


func block_count() -> int:
	return _blocks.size()


# --- cells ------------------------------------------------------------------------

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


func kind(c: Vector2i) -> int:
	var b: Variant = _blocks.get(Vector2i(c.x >> 6, c.y >> 6))
	if b == null:
		return NONE
	return (b as PackedByteArray)[(c.y & 63) * BLOCK + (c.x & 63)]


func kind_at(x: float, z: float) -> int:
	return kind(cell_of(x, z))


## Paint a cell with k where k outranks what is there.
func paint(c: Vector2i, k: int) -> void:
	var key := Vector2i(c.x >> 6, c.y >> 6)
	var b: PackedByteArray = _blocks.get(key, PackedByteArray())
	if b.is_empty():
		b.resize(BLOCK * BLOCK)
	var i := (c.y & 63) * BLOCK + (c.x & 63)
	if rank(k) > rank(b[i]):
		b[i] = k
		_blocks[key] = b          # packed arrays are values: store the change back


## Make sure the blocks under a box exist (so the land there reads as known, if empty).
func cover_box(box: Rect2) -> void:
	for bx in range(floori(box.position.x / BLOCK_M), floori(box.end.x / BLOCK_M) + 1):
		for bz in range(floori(box.position.y / BLOCK_M), floori(box.end.y / BLOCK_M) + 1):
			if not _blocks.has(Vector2i(bx, bz)):
				var b := PackedByteArray()
				b.resize(BLOCK * BLOCK)
				_blocks[Vector2i(bx, bz)] = b


## Fill an area given as edge pairs (all its rings: even-odd, so holes stay
## out), only inside clip. A cell is in when its centre is.
func fill_polygon(edges: PackedVector2Array, k: int, clip: Rect2) -> void:
	if edges.size() < 6:
		return
	var lo := edges[0]
	var hi := edges[0]
	for v in edges:
		lo = lo.min(v)
		hi = hi.max(v)
	var box := Rect2(lo, hi - lo).intersection(clip)
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	var cz0 := floori(box.position.y / CELL)
	var cz1 := floori(box.end.y / CELL)
	var cx0 := floori(box.position.x / CELL)
	var cx1 := floori(box.end.x / CELL)
	var xs := PackedFloat32Array()
	for cz in range(cz0, cz1 + 1):
		var y := (cz + 0.5) * CELL
		xs.clear()
		for i in range(0, edges.size(), 2):
			var a := edges[i]
			var b := edges[i + 1]
			if (a.y > y) != (b.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		if xs.size() < 2:
			continue
		xs.sort()
		for j in range(0, xs.size() - 1, 2):
			var from := maxi(ceili(xs[j] / CELL - 0.5), cx0)
			var to := mini(floori(xs[j + 1] / CELL - 0.5), cx1)
			for cx in range(from, to + 1):
				paint(Vector2i(cx, cz), k)


## Paint a line (a river's centre line) width metres wide (at least one cell), inside clip.
func draw_line(points: PackedVector2Array, width: float, k: int, clip: Rect2) -> void:
	var r := maxf(width * 0.5, CELL * 0.5)
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var lo := a.min(b) - Vector2(r, r)
		var hi := a.max(b) + Vector2(r, r)
		var box := Rect2(lo, hi - lo).intersection(clip)
		if box.size.x <= 0.0 or box.size.y <= 0.0:
			continue
		for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
				var p := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= r:
					paint(Vector2i(cx, cz), k)


# --- water --------------------------------------------------------------------------

## How much of (x, z) is water, 0..1, blended between cell centres (so shores
## are smooth curves, not 20 m steps).
func water_at(x: float, z: float) -> float:
	var fx := x / CELL - 0.5
	var fz := z / CELL - 0.5
	var cx := floori(fx)
	var cz := floori(fz)
	var tx := fx - cx
	var tz := fz - cz
	var w00 := 1.0 if is_water(kind(Vector2i(cx, cz))) else 0.0
	var w10 := 1.0 if is_water(kind(Vector2i(cx + 1, cz))) else 0.0
	var w01 := 1.0 if is_water(kind(Vector2i(cx, cz + 1))) else 0.0
	var w11 := 1.0 if is_water(kind(Vector2i(cx + 1, cz + 1))) else 0.0
	return lerpf(lerpf(w00, w10, tx), lerpf(w01, w11, tx), tz)


## The water surface near (x, z): the level of the water cell under it or the
## nearest one around; NAN when there is none within a cell.
func level_at(x: float, z: float) -> float:
	var c := cell_of(x, z)
	var v: Variant = _levels.get(c)
	if v != null:
		return float(v)
	var best := INF
	var out := NAN
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var lv: Variant = _levels.get(c + Vector2i(dx, dz))
			if lv == null:
				continue
			var d := Vector2((c.x + dx + 0.5) * CELL - x, (c.y + dz + 0.5) * CELL - z).length_squared()
			if d < best:
				best = d
				out = float(lv)
	return out


## Water surface heights from the ground data: each lake one flat level (its
## lowest ground; elevation data is flattened over water), rivers the lowest
## ground of the river around each cell. Call once after loading.
func compute_levels(height: Callable) -> void:
	_levels.clear()
	var ground := {}
	for key in _blocks:
		var b: PackedByteArray = _blocks[key]
		for i in b.size():
			if is_water(b[i]):
				var c := Vector2i(key.x * BLOCK + (i & 63), key.y * BLOCK + (i >> 6))
				ground[c] = float(height.call((c.x + 0.5) * CELL, (c.y + 0.5) * CELL))
	var seen := {}
	for c in ground:
		if seen.has(c):
			continue
		if kind(c) == LAKE:
			# One lake: flood it, its level is its lowest ground.
			var stack: Array[Vector2i] = [c]
			var cells: Array[Vector2i] = []
			seen[c] = true
			var low := INF
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				cells.append(q)
				low = minf(low, float(ground[q]))
				for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var m: Vector2i = q + n
					if not seen.has(m) and kind(m) == LAKE:
						seen[m] = true
						stack.append(m)
			for q in cells:
				_levels[q] = low
		else:
			var low := float(ground[c])
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var g: Variant = ground.get(c + Vector2i(dx, dz))
					if g != null and kind(c + Vector2i(dx, dz)) == RIVER:
						low = minf(low, float(g))
			_levels[c] = low - 0.3


## Every water cell (with a level) inside the box.
func water_cells(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
		for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			var c := Vector2i(cx, cz)
			if _levels.has(c):
				out.append(c)
	return out


func has_water() -> bool:
	return not _levels.is_empty()


## Any water cell within the box (plus a cell)?
func water_in(box: Rect2) -> bool:
	for cz in range(floori(box.position.y / CELL) - 1, floori(box.end.y / CELL) + 2):
		for cx in range(floori(box.position.x / CELL) - 1, floori(box.end.x / CELL) + 2):
			if is_water(kind(Vector2i(cx, cz))):
				return true
	return false


# --- saving -------------------------------------------------------------------------

func save(path: String) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_32(VERSION)
	f.store_32(_blocks.size())
	for key in _blocks:
		f.store_32(key.x & 0xFFFFFFFF)
		f.store_32(key.y & 0xFFFFFFFF)
		f.store_buffer(_blocks[key])
	f.close()
	return true


static func load_from(path: String) -> CoverGrid:
	var g := CoverGrid.new()
	if not FileAccess.file_exists(path):
		return g
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null or f.get_32() != VERSION:
		return g
	var n := f.get_32()
	for i in n:
		var bx := _signed(f.get_32())
		var bz := _signed(f.get_32())
		var b := f.get_buffer(BLOCK * BLOCK)
		if b.size() == BLOCK * BLOCK:
			g._blocks[Vector2i(bx, bz)] = b
	return g


static func _signed(v: int) -> int:
	return v - 0x100000000 if v >= 0x80000000 else v
