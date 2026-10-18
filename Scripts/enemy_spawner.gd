extends Node3D
class_name EnemySpawner

@export var spawnRate = 15
@export var radius = 20
## Each tier spawns its own enemies every wave, sized by its own rules.
@export var tiers : Array[SpawnTier]

@export_group("Placement")
# ...unchanged...
## Enemies won't spawn closer than this (horizontally) to the spawner.
@export var min_distance := 15.0
## Rays start this far above the spawner and point down.
@export var ray_height := 60.0
## How far below the spawner the ray keeps looking.
@export var ray_depth := 200.0
## Random positions to try per enemy before giving up on that enemy.
@export var max_attempts := 10
## Surfaces flatter than this count as floor (same rule as FloorPickup).
@export_range(0.0, 1.0) var min_floor_normal_y := 0.7

var elapsedTime = 0.0


func _process(delta: float) -> void:
	if GameManager.timer_paused:
		return
	if elapsedTime >= spawnRate:
		spawn_wave()
		elapsedTime = 0
	elapsedTime += delta


## One full wave: every tier spawns its own count for the current difficulty.
func spawn_wave() -> void:
	var summary := PackedStringArray()
	for tier in tiers:
		if tier == null:
			continue
		var total := tier.get_count(GameManager.difficulty)
		var spawned := _spawn_tier(tier, total)
		summary.append("%s %d/%d" % [tier.tier_name, spawned, total])
	print("Wave (difficulty ", GameManager.difficulty, "): ", ", ".join(summary))


## Used by the Tab menu button: spawns an exact amount from the first tier (Common).
## With no amount it spawns a normal wave.
func spawn_enemies(amount: int = -1) -> void:
	if amount < 0:
		spawn_wave()
	elif not tiers.is_empty() and tiers[0] != null:
		_spawn_tier(tiers[0], amount)

## Spawns an exact amount from the tier with this name (used by the Tab menu debug buttons).
func spawn_from_tier(tier_name: String, amount: int) -> int:
	for tier in tiers:
		if tier != null and tier.tier_name == tier_name:
			var spawned := _spawn_tier(tier, amount)
			print("Spawned ", spawned, "/", amount, " from tier ", tier_name)
			return spawned
	push_warning("EnemySpawner: no tier named '%s'" % tier_name)
	return 0

func _spawn_tier(tier: SpawnTier, total: int) -> int:
	var spawned := 0
	for i in total:
		var scene_to_spawn := tier.pick()
		if scene_to_spawn == null:
			break   # tier has no enemies assigned
		var point = _find_spawn_point()
		if point == null:
			continue   # no valid spot found this time; skip this enemy
		var enemy : Node3D = scene_to_spawn.instantiate()
		get_tree().root.add_child(enemy)
		enemy.global_position = point
		enemy.reset_physics_interpolation()
		spawned += 1
	return spawned
	

# Returns a Vector3 on the floor, or null if every attempt was rejected.
func _find_spawn_point() -> Variant:
	var space := get_world_3d().direct_space_state
	for attempt in max_attempts:
		var offset := Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
		if offset.length() < min_distance:
			continue

		var from := Vector3(global_position.x + offset.x, global_position.y + ray_height, global_position.z + offset.y)
		var to := from + Vector3.DOWN * (ray_height + ray_depth)
		var hit := _raycast(space, from, to)

		if hit.is_empty():
			continue   # nothing below: edge of the map / void
		if hit.normal.y < min_floor_normal_y:
			continue   # steep wall or slope
		if hit.collider.get_parent() is Interactable:
			continue   # don't spawn on top of chests or guns

		return hit.position + Vector3.UP * 0.1   # tiny lift so the body isn't born in the floor
	return null


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
