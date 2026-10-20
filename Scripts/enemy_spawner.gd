extends Node3D
class_name EnemySpawner

## Seconds between waves.
@export var spawnRate = 15
## Seconds of game time for each difficulty increase.
@export var difficulty_interval := 60.0
## Each tier spawns its own enemies on the waves it's set to, sized by its own rules.
@export var tiers : Array[SpawnTier]

@export_group("Placement")
## Rays start this far above the spawner and point down.
@export var ray_height := 60.0
## How far below the spawner the ray keeps looking.
@export var ray_depth := 200.0
## Random positions to try per enemy before giving up on that enemy.
@export var max_attempts := 10
## Surfaces flatter than this count as floor (same rule as FloorPickup).
@export_range(0.0, 1.0) var min_floor_normal_y := 0.7

@export_group("Elites")
## Chance for each enemy in a wave to spawn as an elite, at difficulty 1 (0.02 = 2%).
@export_range(0.0, 1.0, 0.001) var elite_base_chance := 0.02
## Added to the chance for every difficulty above 1 (0.005 = +0.5% per difficulty).
@export_range(0.0, 1.0, 0.001) var elite_chance_per_difficulty := 0.005
## The chance never goes above this, no matter the difficulty.
@export_range(0.0, 1.0, 0.01) var elite_max_chance := 0.2
## Most elites a single wave can contain at difficulty 1 (shared across all tiers).
@export var elite_base_cap := 1
## How many difficulty increases it takes to raise the cap.
@export_range(1, 100) var elite_cap_difficulty_step := 3
## How much the cap rises each time that many increases happen.
@export var elite_cap_per_step := 1
@export_subgroup("Elite Multipliers")
## Size of an elite compared to the normal enemy (also scales its collision circle and height).
@export_range(0.1, 10.0, 0.05) var elite_size_mult := 1.5
@export_range(0.1, 100.0, 0.1) var elite_health_mult := 4.0
## Contact damage, and projectile damage for ranged enemies like the tank.
@export_range(0.1, 100.0, 0.1) var elite_damage_mult := 2.0
@export_range(0.1, 10.0, 0.05) var elite_speed_mult := 1.2
## Gold an elite drops compared to a normal enemy of its tier.
@export_range(0.0, 100.0, 0.1) var elite_gold_mult := 3.0

@export_group("Swarms")
## Seconds of game time from the start of one swarm to the start of the next.
@export var swarm_interval := 300.0
## How long each swarm lasts, in seconds.
@export var swarm_duration := 60.0
## During a swarm, wave sizes are multiplied by this (only for tiers with Boosted By Swarms on).
@export_range(1.0, 500.0, 0.5) var swarm_count_mult := 50.0
## Most enemies a single swarm wave can add up to, across all boosted tiers. 0 = no cap.
## A wave is never made smaller than it would be without the swarm.
@export var swarm_max_wave_size := 200
## During a swarm, waves come this many times as often. 1 = normal wave timing.
@export_range(0.1, 10.0, 0.1) var swarm_wave_rate_mult := 1.0
## Spawn a wave the moment a swarm starts, instead of waiting for the next wave timer.
@export var swarm_starts_with_wave := true

@export_group("Performance")
## Wave spawning pauses while this many enemies are alive. Debug buttons ignore it.
@export var max_alive_enemies := 1000
## Wave enemies spawn spread over several frames, at most this many per frame, so a
## big wave doesn't freeze the game for a moment.
@export var max_spawns_per_frame := 40

signal swarm_started
signal swarm_ended

## ROLL: normal wave rules. NEVER / ALWAYS: used by the Tab menu debug buttons.
enum EliteMode { ROLL, NEVER, ALWAYS }

var elapsedTime = 0.0
## How many waves have spawned so far. The next wave is wave_number + 1.
var wave_number := 0
## Elites rolled so far in the current wave (checked against the cap).
var _elites_this_wave := 0

## True for the duration of a swarm. Readable by the HUD, music, etc.
var swarm_active := false
var _time_to_next_swarm := 0.0
var _swarm_time_left := 0.0

## Wave enemies waiting to spawn: { "tier": SpawnTier, "left": int }, spawned a few per frame.
var _queue: Array[Dictionary] = []
var _limit_warned := false


func _ready() -> void:
	_time_to_next_swarm = swarm_interval


func _process(delta: float) -> void:
	# Pushed every frame so changing it in the inspector while the game runs takes effect.
	GameManager.difficulty_interval = difficulty_interval
	if GameManager.timer_paused:
		return
	_update_swarm(delta)
	var wave_time := float(spawnRate)
	if swarm_active:
		wave_time /= swarm_wave_rate_mult
	if elapsedTime >= wave_time:
		spawn_wave()
		elapsedTime = 0
	elapsedTime += delta
	_drain_queue()


# ---------- Swarms ----------

func _update_swarm(delta: float) -> void:
	_time_to_next_swarm -= delta
	if _time_to_next_swarm <= 0.0:
		_time_to_next_swarm += maxf(swarm_interval, 1.0)
		start_swarm()
	if swarm_active:
		_swarm_time_left -= delta
		if _swarm_time_left <= 0.0:
			end_swarm()


## Starts a swarm now (also used by the Tab menu). Calling it during a swarm restarts its timer.
func start_swarm() -> void:
	_swarm_time_left = swarm_duration
	if swarm_active:
		return
	swarm_active = true
	print("SWARM started (x%s waves for %ds)" % [swarm_count_mult, swarm_duration])
	swarm_started.emit()
	if swarm_starts_with_wave:
		spawn_wave()
		elapsedTime = 0


## Ends the current swarm. Enemies already queued still finish spawning.
func end_swarm() -> void:
	if not swarm_active:
		return
	swarm_active = false
	_swarm_time_left = 0.0
	print("SWARM ended")
	swarm_ended.emit()


## Seconds until the next swarm starts (for a future HUD countdown).
func get_time_to_next_swarm() -> float:
	return _time_to_next_swarm


# ---------- Waves ----------

## One full wave: every tier scheduled for this wave queues its count for the current difficulty.
## The queue is spawned over the next few frames by _drain_queue.
func spawn_wave() -> void:
	wave_number += 1
	_elites_this_wave = 0
	_limit_warned = false
	var summary := PackedStringArray()

	# Normal counts first, then the swarm-boosted counts for tiers that get them.
	var active_tiers: Array[SpawnTier] = []
	var normal: Array[int] = []
	var boosted: Array[int] = []
	var boosted_sum := 0
	for tier in tiers:
		if tier == null or not tier.spawns_on_wave(wave_number):
			continue
		var count := tier.get_count(GameManager.difficulty)
		var swarm_count := count
		if swarm_active and tier.boosted_by_swarms:
			swarm_count = roundi(count * swarm_count_mult)
			boosted_sum += swarm_count
		active_tiers.append(tier)
		normal.append(count)
		boosted.append(swarm_count)

	# Over the cap: shrink every boosted tier by the same ratio, so their mix stays the same.
	var shrink := 1.0
	if swarm_max_wave_size > 0 and boosted_sum > swarm_max_wave_size:
		shrink = float(swarm_max_wave_size) / boosted_sum

	for i in active_tiers.size():
		var tier := active_tiers[i]
		var total := boosted[i]
		if total != normal[i]:   # this tier was boosted
			total = maxi(roundi(total * shrink), normal[i])
		var clumps := _make_clumps(tier, total)
		if total > 0:
			_queue.append({"tier": tier, "left": total, "clumps": clumps, "done": 0})
		var clump_note := " in %d clumps" % clumps.size() if clumps.size() > 1 else ""
		summary.append("%s %d%s" % [tier.tier_name, total, clump_note])
	if summary.is_empty():
		summary.append("no tiers this wave")
	var tag := " [SWARM]" if swarm_active else ""
	print("Wave ", wave_number, tag, " (difficulty ", GameManager.difficulty, "): ", ", ".join(summary))


func _drain_queue() -> void:
	var budget := max_spawns_per_frame
	while budget > 0 and not _queue.is_empty():
		var room := max_alive_enemies - EnemyManager.enemies.size()
		if room <= 0:
			# At the limit: drop what's left of this wave rather than spawning it later.
			if not _limit_warned:
				_limit_warned = true
				print("Enemy limit reached (", max_alive_enemies, "): rest of the wave skipped")
			_queue.clear()
			return
		var entry: Dictionary = _queue[0]
		var left: int = entry["left"]
		var n := mini(mini(budget, left), room)
		var done: int = entry["done"]
		_spawn_tier(entry["tier"], n, EliteMode.ROLL, entry["clumps"], done)
		entry["left"] = left - n
		entry["done"] = done + n
		budget -= n
		if left - n <= 0:
			_queue.pop_front()


## Chance for each enemy to roll as an elite at this difficulty.
func get_elite_chance(difficulty: int) -> float:
	var chance := elite_base_chance + elite_chance_per_difficulty * float(difficulty - 1)
	return clampf(chance, 0.0, elite_max_chance)


## Most elites one wave can contain at this difficulty.
func get_elite_cap(difficulty: int) -> int:
	var steps := floori(float(difficulty - 1) / float(elite_cap_difficulty_step))
	return maxi(elite_base_cap + steps * elite_cap_per_step, 0)


## Used by the Tab menu button: spawns an exact amount from the first tier (Minor).
## With no amount it spawns a normal wave.
func spawn_enemies(amount: int = -1) -> void:
	if amount < 0:
		spawn_wave()
	elif not tiers.is_empty() and tiers[0] != null:
		_spawn_tier(tiers[0], amount, EliteMode.NEVER)


## Spawns an exact amount from the tier with this name (used by the Tab menu debug buttons).
## Debug spawns ignore the elite chance and cap: all normal, or all elite with as_elites.
func spawn_from_tier(tier_name: String, amount: int, as_elites := false) -> int:
	for tier in tiers:
		if tier != null and tier.tier_name == tier_name:
			var mode: EliteMode = EliteMode.ALWAYS if as_elites else EliteMode.NEVER
			var spawned := _spawn_tier(tier, amount, mode, _make_clumps(tier, amount))
			print("Spawned ", spawned, "/", amount, " from tier ", tier_name, " (elite)" if as_elites else "")
			return spawned
	push_warning("EnemySpawner: no tier named '%s'" % tier_name)
	return 0


func _roll_elite(tier: SpawnTier, mode: EliteMode) -> bool:
	match mode:
		EliteMode.ALWAYS:
			return true
		EliteMode.NEVER:
			return false
	if not tier.allow_elites or _elites_this_wave >= get_elite_cap(GameManager.difficulty):
		return false
	return randf() < get_elite_chance(GameManager.difficulty)


## clumps: from _make_clumps (empty = spread evenly around the ring).
## first_index: how many of this wave's enemies were already spawned, so a wave that
## spawns over several frames keeps dealing enemies out to its clumps in turn.
func _spawn_tier(tier: SpawnTier, total: int, elite_mode: EliteMode, clumps: Array = [], first_index := 0) -> int:
	var spawned := 0
	var gold := tier.get_gold(GameManager.difficulty)
	var health_mult := tier.get_health_multiplier(GameManager.difficulty)
	for i in total:
		var scene_to_spawn := tier.pick()
		if scene_to_spawn == null:
			break   # tier has no enemies assigned
		var clump: Dictionary = clumps[(first_index + i) % clumps.size()] if not clumps.is_empty() else {}
		var point = _find_spawn_point(tier, clump)
		if point == null:
			continue   # no valid spot found this time; skip this enemy
		var enemy : Node3D = scene_to_spawn.instantiate()
		if enemy is Enemy:
			var e := enemy as Enemy
			# Set before add_child so the enemy's _ready sees them.
			e.gold_value = gold
			e.health_multiplier = health_mult
			if _roll_elite(tier, elite_mode):
				e.gold_value = roundi(gold * elite_gold_mult)
				e.make_elite(elite_size_mult, elite_health_mult, elite_damage_mult, elite_speed_mult)
				if elite_mode == EliteMode.ROLL:
					_elites_this_wave += 1
					print("Elite ", tier.tier_name, " spawned (wave ", wave_number, ")")
		get_tree().root.add_child(enemy)
		enemy.global_position = point
		enemy.reset_physics_interpolation()
		spawned += 1
	return spawned


# ---------- Placement ----------

## Picks where this wave's clumps of a tier go. Returns [{ "center": Vector2, "radius": float }],
## with center as an offset from the spawner. Empty = this tier doesn't clump.
func _make_clumps(tier: SpawnTier, total: int) -> Array[Dictionary]:
	var clumps: Array[Dictionary] = []
	if tier.enemies_per_clump <= 1 or total <= 0:
		return clumps
	var count := clampi(ceili(float(total) / tier.enemies_per_clump), 1, maxi(tier.max_clumps, 1))
	# Clumps bigger than enemies_per_clump (swarms) grow in area, so they stay about as dense.
	var per_clump := float(total) / count
	var radius := tier.clump_radius * sqrt(maxf(per_clump / tier.enemies_per_clump, 1.0))
	var near := minf(tier.min_spawn_distance, tier.max_spawn_distance)
	var far := maxf(tier.min_spawn_distance, tier.max_spawn_distance)
	var min_gap := deg_to_rad(tier.clump_min_gap_deg)
	var space := get_world_3d().direct_space_state
	var angles: Array[float] = []

	for _c in count:
		var best_offset := Vector2.ZERO
		var found := false
		for attempt in max_attempts:
			var angle := randf() * TAU
			if not _angle_is_clear(angle, angles, min_gap) and attempt < max_attempts - 1:
				continue   # too close to another clump: try another direction
			# Keep the whole clump outside min distance where the ring allows it.
			var dist := randf_range(minf(near + radius, far), far)
			var offset := Vector2.from_angle(angle) * dist
			if _floor_point(space, offset) == null:
				continue   # clump center is inside a building or off the map
			best_offset = offset
			angles.append(angle)
			found = true
			break
		if found:
			clumps.append({"center": best_offset, "radius": radius})
	return clumps


func _angle_is_clear(angle: float, taken: Array[float], min_gap: float) -> bool:
	for a in taken:
		if absf(angle_difference(a, angle)) < min_gap:
			return false
	return true


# Returns a Vector3 on the floor, or null if every attempt was rejected.
# With a clump, the point lands inside that clump's circle; without one, anywhere in the ring.
func _find_spawn_point(tier: SpawnTier, clump: Dictionary = {}) -> Variant:
	var space := get_world_3d().direct_space_state
	var near := minf(tier.min_spawn_distance, tier.max_spawn_distance)
	var far := maxf(tier.min_spawn_distance, tier.max_spawn_distance)
	for attempt in max_attempts:
		var offset: Vector2
		if clump.is_empty():
			# Random point in a ring around the spawner. Squaring keeps the spread even
			# across the ring's area, so far distances aren't under-represented.
			var dist := sqrt(randf_range(near * near, far * far))
			offset = Vector2.from_angle(randf() * TAU) * dist
		else:
			# Random point in the clump's circle (sqrt = even spread, not bunched in the middle).
			var r: float = clump["radius"] * sqrt(randf())
			offset = clump["center"] + Vector2.from_angle(randf() * TAU) * r
		var point = _floor_point(space, offset)
		if point != null:
			return point
	return null


# Floor position at this horizontal offset from the spawner, or null if it isn't valid ground.
func _floor_point(space: PhysicsDirectSpaceState3D, offset: Vector2) -> Variant:
	var from := Vector3(global_position.x + offset.x, global_position.y + ray_height, global_position.z + offset.y)
	var to := from + Vector3.DOWN * (ray_height + ray_depth)
	var hit := _raycast(space, from, to)
	if hit.is_empty():
		return null   # nothing below: edge of the map / void
	if hit.normal.y < min_floor_normal_y:
		return null   # steep wall or slope
	if hit.collider.get_parent() is Interactable:
		return null   # don't spawn on top of chests or guns
	return hit.position + Vector3.UP * 0.1   # tiny lift so the body isn't born in the floor


# Ray that ignores characters (player and other enemies).
func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var exclude: Array[RID] = []
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not (hit.collider is CharacterBody3D):
			return hit
		exclude.append(hit.rid)
	return {}
