# Autoload "Swarm": lightweight enemies for huge counts (thousands at once).
#
# A swarm enemy is NOT a node. It's one entry in the swarm core's arrays, drawn as one
# instance of a MultiMesh (one draw per enemy type, not per enemy). There are no physics
# bodies: movement uses a crowd grid and a cached terrain height map, and bullets,
# explosions, lock-on, ricochet and chain lightning find swarm enemies through the query
# functions below.
#
# The heavy loops run in the native SwarmCore (C++, bin/swarm_core.gdextension). If that
# library isn't loaded, the GDScript copy (SwarmCoreGD) is used instead: same behavior,
# but it slows down past a few thousand enemies.
#
# Each enemy is handed out as a SwarmUnit, which has the same names as an Enemy node
# (dead, spawning, pos, take_damage(), get_aim_position()), so HitSystem, StatusEffects and
# on-hit items treat both the same.
#
# Which enemies become swarm enemies: any enemy scene whose root uses the plain Enemy script
# with Use Swarm on (forklift). Enemies with their own script (TankEnemy, future bosses)
# always spawn as normal nodes and keep working exactly as before.
extends Node

## Crowd and movement tuning, handed to the swarm core. Edit these to change how the swarm
## behaves (both the C++ and the GDScript core read the same names).
const TUNING := {
	# Crowd grid cell size (meters). Density pushing and all hit queries use this grid.
	"crowd_cell": 2.0,
	# Enemies that fit in one crowd cell before it counts as crowded.
	"crowd_capacity": 2,
	# Push away from crowded cells, in m/s per enemy of difference between neighbor cells.
	"crowd_push": 1.1,
	# How hard enemies in an over-full cell fan out inside it (m/s per extra enemy).
	"cell_spread": 0.8,
	# Within this distance of the player enemies also get exact one-on-one collision,
	# so the ring around the player stays clean.
	"close_range": 14.0,
	"max_neighbors": 6,
	"max_looked": 14,
	# Climbers pile up where the crowd overflows: each pile layer is this much of their height.
	"pile_layer": 0.75,
	# Climbers sharing a crowd cell stack this many per layer (1 = every extra one goes up
	# a layer, 2 = two side by side per layer, so lower, wider piles). Pile height is also
	# capped by each enemy's Max Climb Height export.
	"pile_capacity": 1,
	# How much climbers spread away from crowds compared to non-climbers (1 = same).
	# Lower = they bunch up and pile higher instead of spreading into a flat carpet.
	"climber_push_scale": 0.3,
	"gravity": 24.0,
	"step_up_speed": 10.0,
	"fall_kill_y": -100.0,
	"knock_decel": 40.0,
	"max_knock_speed": 40.0,
	"player_radius": 0.5,
	"player_half_height": 1.0,
	# Climbers won't start climbing a wall taller than this.
	"max_wall_climb": 30.0,
	# How quickly enemies turn to face where they're going (higher = snappier).
	"turn_rate": 10.0,
	# Each enemy re-decides its direction, crowd push and attack once per this many ticks
	# (spread out so only some think each tick). Movement itself happens every tick.
	"think_interval": 2,
	# Re-check the ground under each enemy every this many ticks.
	"ground_recheck": 8,
	# Terrain columns measured per tick: on demand, and in the background around the player.
	"fill_budget": 150,
	"prefill_budget": 60,
	"prefill_radius": 70,
}

## The GDScript core is much slower, so it thinks less often.
const GD_TUNING_OVERRIDES := {"think_interval": 3}

# Sound limits (all swarm enemies share them).
const MAX_DEATH_SOUNDS := 8
const MAX_HIT_SOUNDS := 16
const HIT_SOUND_MIN_GAP_MS := 30
const ENEMY_SFX_BUS := &"EnemySFX"
const WORLD_MASK := 1

const F_SPAWNING := 2
const F_CLIMBER := 4
const F_ELITE := 8

const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back;
uniform vec4 flash_color : source_color = vec4(1.0, 0.1, 0.1, 0.25);
void vertex() {
	// Not flashing: collapse the overlay copy to a point so it draws nothing.
	if (INSTANCE_CUSTOM.r < 0.5) { VERTEX = vec3(0.0); }
}
void fragment() {
	ALBEDO = flash_color.rgb;
	ALPHA = flash_color.a;
}
"""

## True when the fast C++ core is running.
var native := false
## Milliseconds the last swarm tick took inside the core (for profiling).
var last_tick_ms := 0.0

var _core : Object   # SwarmCore (C++) or SwarmCoreGD
var _types : Array[SwarmType] = []
var _type_by_path := {}
var _units : Array = []   # slot -> SwarmUnit
var _scene : Node
var _world_aabb := AABB()
var _flash_material : ShaderMaterial

var _active_death_sounds := 0
var _active_hit_sounds := 0
var _last_hit_sound_ms := 0


# ======================================================================
# Spawning
# ======================================================================

## True if this enemy scene spawns as a swarm enemy (plain Enemy script, Use Swarm on).
func can_swarm(scene: PackedScene) -> bool:
	return scene != null and _get_type(scene).valid


## Spawns one swarm enemy with its feet at `at`. Returns its handle, or null if the scene
## can't be a swarm enemy (spawn it as a node instead).
## elite: {} for a normal enemy, or {"size", "health", "damage", "speed"} multipliers.
func spawn(scene: PackedScene, at: Vector3, gold: int = 0, health_mult: float = 1.0,
		elite: Dictionary = {}) -> SwarmUnit:
	if _core == null or _scene != get_tree().current_scene:
		_setup_world()
	var t := _get_type(scene)
	if not t.valid:
		return null
	if t.mm_instance == null:
		t.core_index = _core.add_type()
		t.build_renderer(self, _flash_material, _world_aabb)

	var size := float(elite.get("size", 1.0))
	var dmg := float(elite.get("damage", 1.0))
	var spd := float(elite.get("speed", 1.0))
	var st := PackedFloat32Array()
	st.resize(SwarmCoreGD.S_COUNT)
	st[SwarmCoreGD.S_HEALTH] = t.max_health * maxf(health_mult, 0.01) * float(elite.get("health", 1.0))
	st[SwarmCoreGD.S_SPEED] = t.speed * spd
	st[SwarmCoreGD.S_RADIUS] = t.radius * size
	st[SwarmCoreGD.S_HEIGHT] = t.height * size
	st[SwarmCoreGD.S_STEP] = t.step_height * size
	st[SwarmCoreGD.S_CLIMB_SPEED] = t.climb_speed * spd
	st[SwarmCoreGD.S_MAX_CLIMB] = t.max_climb_height * size
	st[SwarmCoreGD.S_KB_RESIST] = t.knockback_resist
	st[SwarmCoreGD.S_ATTACK] = t.attack_damage * dmg
	st[SwarmCoreGD.S_ATTACK_CD] = t.attack_cooldown
	st[SwarmCoreGD.S_KB_FORCE] = t.knockback_force
	st[SwarmCoreGD.S_KB_UP] = t.knockback_up
	st[SwarmCoreGD.S_REACH] = t.attack_reach
	st[SwarmCoreGD.S_SCALE] = size
	st[SwarmCoreGD.S_AIM] = t.aim_height * size
	st[SwarmCoreGD.S_EMERGE_TIME] = t.emerge_time
	st[SwarmCoreGD.S_EMERGE_PAUSE] = t.emerge_pause
	st[SwarmCoreGD.S_EMERGE_DEPTH] = t.height * size + t.emerge_extra_depth
	st[SwarmCoreGD.S_FLASH_TIME] = t.flash_time

	var flags := 0
	if t.emerge_time > 0.0 or t.emerge_pause > 0.0:
		flags |= F_SPAWNING
	if t.can_climb:
		flags |= F_CLIMBER
	if not elite.is_empty():
		flags |= F_ELITE

	var s : int = _core.add_unit(t.core_index, at, st, flags, gold)
	if s < 0:
		return null
	var unit := SwarmUnit.new()
	unit.slot = s
	if s >= _units.size():
		_units.resize(maxi(s + 1, _units.size() * 2))
	_units[s] = unit
	return unit


## How many swarm enemies are alive.
func count() -> int:
	return _core.unit_count() if _core != null else 0


## Every live swarm enemy, as SwarmUnit handles.
func get_units() -> Array:
	var out : Array = []
	if _core == null:
		return out
	for s in _core.get_alive():
		out.append(_units[s])
	return out


## Removes every swarm enemy (no gold, no sounds). Also called when the scene changes.
func clear() -> void:
	for u in _units:
		if u != null:
			(u as SwarmUnit).dead = true
	_units.clear()
	for t in _types:
		t.free_renderer()
	_types.clear()
	_type_by_path.clear()
	_core = null
	_scene = null


# ======================================================================
# Handle accessors (used by SwarmUnit)
# ======================================================================

func is_alive(s: int) -> bool:
	return _core != null and _core.is_alive(s)

func is_spawning(s: int) -> bool:
	return _core != null and _core.is_spawning(s)

func is_elite(s: int) -> bool:
	return _core != null and _core.is_elite(s)

func get_pos(s: int) -> Vector3:
	return _core.get_pos(s) if _core != null else Vector3.ZERO

func get_aim_position(s: int) -> Vector3:
	return _core.get_aim_position(s) if _core != null else Vector3.ZERO

func get_height(s: int) -> float:
	return _core.get_height(s) if _core != null else 0.0

func get_knockback_resist(s: int) -> float:
	return _core.get_kb_resist(s) if _core != null else 1.0

func get_health(s: int) -> float:
	return _core.get_health(s) if _core != null else 0.0


# ======================================================================
# Damage, death, knockback
# ======================================================================

## Applies damage. Returns true if it killed the enemy. Call through HitSystem.deal_hit().
func damage(s: int, amount: float, is_crit: bool = false) -> bool:
	if _core == null:
		return false
	var result : int = _core.damage(s, amount, Time.get_ticks_msec())
	if result < 0:
		return false
	GameManager.enemy_damaged.emit(amount, is_crit)
	if result == 1:
		_kill(s, true)
		return true
	var now := Time.get_ticks_msec()
	if now - _last_hit_sound_ms >= HIT_SOUND_MIN_GAP_MS:
		_last_hit_sound_ms = now
		var t := _types_by_core_index(_core.get_type(s))
		if t != null:
			_play_sound(t.hit_sounds, _core.get_aim_position(s), t.hit_volume_db, true)
	return false


## Pushes a swarm enemy: `push` is horizontal velocity (m/s), `up` an upward pop (m/s).
func knock_back(s: int, push: Vector3, up: float) -> void:
	if _core != null:
		_core.knock_back(s, push, up)


func _kill(s: int, drops: bool) -> void:
	if not _core.is_alive(s):
		return
	if drops:
		var t := _types_by_core_index(_core.get_type(s))
		var at : Vector3 = _core.get_aim_position(s)
		if t != null:
			_play_sound(t.death_sounds, at, 0.0, false)
			_drop_gold(at, _core.get_gold(s), t.gold_coins)
	var u : SwarmUnit = _units[s] if s < _units.size() else null
	if u != null:
		u.dead = true
		_units[s] = null
	_core.remove_unit(s)


func _drop_gold(origin: Vector3, value: int, coins: int) -> void:
	Coins.drop(origin, value, coins)


func _play_sound(streams: Array[AudioStream], at: Vector3, volume_db: float, is_hit: bool) -> void:
	if streams.is_empty():
		return
	if is_hit:
		if _active_hit_sounds >= MAX_HIT_SOUNDS:
			return
		_active_hit_sounds += 1
	else:
		if _active_death_sounds >= MAX_DEATH_SOUNDS:
			return
		_active_death_sounds += 1
	var audio := AudioStreamPlayer3D.new()
	audio.stream = streams.pick_random()
	audio.volume_db = volume_db
	if is_hit:
		audio.max_db = -5.0
	audio.bus = ENEMY_SFX_BUS
	get_tree().current_scene.add_child(audio)
	audio.global_position = at
	audio.play()
	audio.finished.connect(_release_sound.bind(audio, is_hit))


func _release_sound(audio: AudioStreamPlayer3D, is_hit: bool) -> void:
	if is_hit:
		_active_hit_sounds -= 1
	else:
		_active_death_sounds -= 1
	audio.queue_free()


# ======================================================================
# Queries (bullets, explosions, lock-on, ricochet, chain lightning)
# ======================================================================

## First swarm enemy a straight line from `from` to `to` passes through.
## skip: Dictionary of SwarmUnits to ignore (e.g. enemies a ricochet already hit).
## Returns {} or {"unit", "position", "normal", "fraction"} (fraction 0-1 along the line).
func raycast(from: Vector3, to: Vector3, skip: Dictionary = {}) -> Dictionary:
	if _core == null:
		return {}
	var hit : Dictionary = _core.raycast(from, to, _skip_slots(skip))
	if hit.is_empty():
		return hit
	hit["unit"] = _units[hit["slot"]]
	return hit


## Every live swarm enemy whose body is within `radius` of `center` (explosions).
func query_sphere(center: Vector3, radius: float, max_results: int = 512) -> Array:
	var out : Array = []
	if _core == null:
		return out
	for s in _core.query_sphere(center, radius, max_results):
		out.append(_units[s])
	return out


## Closest live swarm enemy (by body center) within max_range, skipping units in `skip`.
## Returns [unit, distance_squared] or [] if none.
func find_nearest(from: Vector3, max_range: float, skip: Dictionary = {}) -> Array:
	if _core == null:
		return []
	var r : PackedFloat32Array = _core.find_nearest(from, max_range, _skip_slots(skip))
	if r.is_empty():
		return []
	return [_units[int(r[0])], r[1]]


## Lock-on candidates: swarm enemies within max_angle (radians) of `forward` and max_range
## of `origin`, best (most centered) first, at most `limit` of them. Each entry: [angle, unit].
func lock_candidates(origin: Vector3, forward: Vector3, max_angle: float, max_range: float, limit: int = 8) -> Array:
	var out : Array = []
	if _core == null:
		return out
	var r : PackedFloat32Array = _core.lock_candidates(origin, forward, max_angle, max_range, limit)
	var i := 0
	while i + 1 < r.size():
		out.append([r[i], _units[int(r[i + 1])]])
		i += 2
	return out


func _skip_slots(skip: Dictionary) -> PackedInt32Array:
	var slots := PackedInt32Array()
	for u in skip:
		if is_instance_valid(u) and u is SwarmUnit and not (u as SwarmUnit).dead:
			slots.append((u as SwarmUnit).slot)
	return slots


# ======================================================================
# Per tick
# ======================================================================

func _physics_process(delta: float) -> void:
	if _core == null:
		return
	if _scene != null and (not is_instance_valid(_scene) or _scene != get_tree().current_scene):
		clear()
		return
	var player := GameManager.player
	if player == null or not is_instance_valid(player):
		return

	_core.set_world(get_viewport().world_3d.direct_space_state, _exclude())
	_core.set_obstacles(_obstacle_list())
	var events : PackedInt32Array = _core.step(delta, player.global_position, Time.get_ticks_msec())
	last_tick_ms = _core.get_last_step_ms()

	var i := 0
	while i + 1 < events.size():
		var kind := events[i]
		var s := events[i + 1]
		i += 2
		if kind == 1:
			# Hit the player: same as Enemy.try_contact_attack.
			var atk : PackedFloat32Array = _core.get_attack(s)
			var push : Vector3 = player.global_position - _core.get_pos(s)
			player.take_damage(atk[0])
			player.apply_knockback(push, atk[1], atk[2])
		elif kind == 2:
			_kill(s, false)   # fell out of the world

	for t in _types:
		if t.multimesh == null:
			continue
		var cap : int = _core.get_instance_capacity(t.core_index)
		if t.multimesh.instance_count != cap:
			t.multimesh.instance_count = cap
		if cap == 0:
			continue
		t.multimesh.visible_instance_count = _core.get_visible_count(t.core_index)
		t.multimesh.set_buffer_interpolated(_core.get_buffer(t.core_index), _core.get_prev_buffer(t.core_index))


func _exclude() -> Array[RID]:
	var rids : Array[RID] = []
	if GameManager.player != null:
		rids.append(GameManager.player.get_rid())
	return rids


# Node enemies (tanks, bosses) as x, z, radius triples: the swarm flows around them.
func _obstacle_list() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in EnemyManager.enemies:
		if not e.dead:
			out.append(e.pos.x)
			out.append(e.pos.z)
			out.append(e.radius)
	return out


# ======================================================================
# Setup
# ======================================================================

func _get_type(scene: PackedScene) -> SwarmType:
	var key := scene.resource_path if not scene.resource_path.is_empty() else str(scene.get_instance_id())
	var t : SwarmType = _type_by_path.get(key)
	if t == null:
		t = SwarmType.from_scene(scene)
		_types.append(t)
		_type_by_path[key] = t
	return t


func _types_by_core_index(i: int) -> SwarmType:
	for t in _types:
		if t.core_index == i:
			return t
	return null


# Measures the level once: its bounds size the crowd grid and the terrain height cache.
func _setup_world() -> void:
	if _core != null:
		clear()
	_scene = get_tree().current_scene
	var bounds := AABB()
	var found := false
	for node in _scene.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		var body := cs.get_parent() as CollisionObject3D
		if cs.shape == null or not (body is StaticBody3D) or (body.collision_layer & WORLD_MASK) == 0:
			continue
		var box : AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	if not found:
		bounds = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))
	_world_aabb = bounds

	native = ClassDB.class_exists(&"SwarmCore")
	if native:
		_core = ClassDB.instantiate(&"SwarmCore")
		_core.set_tuning(TUNING)
	else:
		_core = SwarmCoreGD.new()
		_core.set_tuning(TUNING)
		_core.set_tuning(GD_TUNING_OVERRIDES)
		push_warning("Swarm: native SwarmCore not loaded, using the slower GDScript core")
	_core.set_world(get_viewport().world_3d.direct_space_state, _exclude())
	_core.setup(bounds)

	if _flash_material == null:
		var shader := Shader.new()
		shader.code = FLASH_SHADER
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = shader
	print("Swarm: %s core, level %s, crowd grid %s, terrain %s" % [
			"native" if native else "GDScript", bounds, _core.get_grid_size(), _core.get_terrain_size()])
