# Cached walkable heights for swarm enemies, so 10k enemies never raycast every tick.
#
# The level is split into 1 m columns. The first time a column is needed it's measured with a
# few downward rays: every surface top in it (up to MAX_LAYERS, e.g. a platform AND the ground
# under it) plus how much open space is above each top. After that it's just array lookups.
#
# A surface is walkable for an enemy if it's no higher than its feet + step height and has at
# least the enemy's height of open space above it. So:
#  - the ground under a big platform is walkable (open space up to the platform),
#  - the "ground" inside a building isn't (zero space: the building fills it),
#  - a wall is a column whose only walkable top is too high to step onto.
#
# Geometry is assumed static. Columns are measured on demand (a capped number per tick)
# and also pre-measured around the player in the background.
class_name SwarmTerrain
extends RefCounted

const CELL := 1.0
const MAX_LAYERS := 3
const UNKNOWN := 255
const WORLD_MASK := 1
## How far above a surface we look for a ceiling. More than any enemy is tall.
const CLEARANCE_CHECK := 30.0
## Columns measured on demand per physics tick at most (3 rays each, usually).
const FILL_BUDGET := 150
## Columns pre-measured in the background per physics tick, around the player.
const PREFILL_BUDGET := 60
const PREFILL_RADIUS := 70

var fill_budget := FILL_BUDGET
var prefill_budget := PREFILL_BUDGET
var prefill_radius := PREFILL_RADIUS

var origin_x := 0.0
var origin_z := 0.0
var width := 0          # columns along x
var depth := 0          # columns along z
var _top_y := 100.0     # rays start here
var _bottom_y := -100.0

var _count := PackedByteArray()       # layers per column, UNKNOWN = not measured yet
var _tops := PackedFloat32Array()     # col * MAX_LAYERS + layer
var _clear := PackedFloat32Array()    # open space above each top

var _space : PhysicsDirectSpaceState3D
var _exclude : Array[RID] = []
var _fills_left := FILL_BUDGET
var _down := PhysicsRayQueryParameters3D.new()
var _up := PhysicsRayQueryParameters3D.new()

# Background prefill: walks a square spiral of columns around the player.
var _prefill_center := Vector2i(-99999, -99999)
var _prefill_ring := 0
var _prefill_step := 0


func setup(bounds: AABB, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	bounds = bounds.grow(4.0)
	origin_x = bounds.position.x
	origin_z = bounds.position.z
	width = maxi(ceili(bounds.size.x / CELL), 1)
	depth = maxi(ceili(bounds.size.z / CELL), 1)
	_top_y = bounds.end.y + 5.0
	_bottom_y = bounds.position.y - 5.0
	_count.resize(width * depth)
	_count.fill(UNKNOWN)
	_tops.resize(width * depth * MAX_LAYERS)
	_clear.resize(width * depth * MAX_LAYERS)
	for q in [_down, _up]:
		q.collision_mask = WORLD_MASK
		q.collide_with_areas = false
	_down.hit_from_inside = false
	_up.hit_from_inside = true    # starting inside a solid = no open space at all
	set_space(space, exclude)


## The physics space to measure in. Call every physics tick (the space state is only
## valid during the physics step).
func set_space(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	_space = space
	_exclude = exclude
	_down.exclude = exclude
	_up.exclude = exclude


## Call once per physics tick before using the terrain.
func begin_tick(player_pos: Vector3) -> void:
	_fills_left = fill_budget
	if _space != null:
		_prefill(player_pos)


## Column index for a world position, or -1 outside the level.
func col_of(x: float, z: float) -> int:
	var cx := int(floorf((x - origin_x) / CELL))
	var cz := int(floorf((z - origin_z) / CELL))
	if cx < 0 or cz < 0 or cx >= width or cz >= depth:
		return -1
	return cx + cz * width


## Height an enemy standing at feet height `y` would stand on in this column, or -INF if it
## can't go there (a wall it can't step up, or no room for its body).
## Unmeasured columns that can't be measured this tick return NAN: treat as "unknown, keep going".
func ground(col: int, y: float, step: float, height: float) -> float:
	if col < 0:
		return -INF
	var n := _count[col]
	if n == UNKNOWN:
		if _fills_left <= 0 or _space == null:
			return NAN
		_fills_left -= 1
		_measure(col)
		n = _count[col]
	var best := -INF
	var base := col * MAX_LAYERS
	for i in n:
		var t := _tops[base + i]
		if t <= y + step and _clear[base + i] >= height and t > best:
			best = t
	return best


## Highest top in this column that's above `y + step` but still reachable by climbing it:
## tells a climber how high the wall in front of it goes. -INF if none / unknown.
func wall_top(col: int, y: float, step: float) -> float:
	if col < 0 or _count[col] == UNKNOWN:
		return -INF
	var lowest := INF
	var base := col * MAX_LAYERS
	for i in _count[col]:
		var t := _tops[base + i]
		if t > y + step and t < lowest:
			lowest = t
	return lowest if lowest < INF else -INF


func is_known(col: int) -> bool:
	return col >= 0 and _count[col] != UNKNOWN


func _measure(col: int) -> void:
	var cx := col % width
	var cz := col / width
	var x := origin_x + (cx + 0.5) * CELL
	var z := origin_z + (cz + 0.5) * CELL
	var from_y := _top_y
	var layers := 0
	var base := col * MAX_LAYERS
	while layers < MAX_LAYERS and from_y > _bottom_y:
		_down.from = Vector3(x, from_y, z)
		_down.to = Vector3(x, _bottom_y, z)
		var hit := _space.intersect_ray(_down)
		if hit.is_empty():
			break
		var t: float = hit.position.y
		_up.from = Vector3(x, t + 0.05, z)
		_up.to = Vector3(x, t + 0.05 + CLEARANCE_CHECK, z)
		var up := _space.intersect_ray(_up)
		var clearance: float = CLEARANCE_CHECK if up.is_empty() else (up.position.y - (t + 0.05))
		_tops[base + layers] = t
		_clear[base + layers] = clearance
		layers += 1
		from_y = t - 0.05
	_count[col] = layers


# Measures a few unknown columns per tick in a growing square around the player, so the
# area enemies are heading into is usually ready before they arrive.
func _prefill(player_pos: Vector3) -> void:
	var center := Vector2i(int(floorf((player_pos.x - origin_x) / CELL)), int(floorf((player_pos.z - origin_z) / CELL)))
	if (center - _prefill_center).length_squared() > 100:
		_prefill_center = center   # moved a lot: restart the spiral here
		_prefill_ring = 0
		_prefill_step = 0
	var budget := prefill_budget
	var tries := 0
	while budget > 0 and _prefill_ring <= prefill_radius and tries < 4000:
		tries += 1
		var cell := _ring_cell(_prefill_ring, _prefill_step)
		_prefill_step += 1
		if _prefill_step >= maxi(_prefill_ring * 8, 1):
			_prefill_step = 0
			_prefill_ring += 1
		var cx := _prefill_center.x + cell.x
		var cz := _prefill_center.y + cell.y
		if cx < 0 or cz < 0 or cx >= width or cz >= depth:
			continue
		var col := cx + cz * width
		if _count[col] == UNKNOWN:
			_measure(col)
			budget -= 1


# The step-th cell on the square ring at distance r from the center (r = 0 is the center).
static func _ring_cell(r: int, step: int) -> Vector2i:
	if r == 0:
		return Vector2i.ZERO
	var side := r * 2
	var edge := step / side
	var along := step % side
	match edge:
		0: return Vector2i(-r + along, -r)
		1: return Vector2i(r, -r + along)
		2: return Vector2i(r - along, r)
		_: return Vector2i(-r, r - along)
