# Scatters interactables (chests, gun stores, ...) across the level when the game starts.
# Total Count is shared out between the Entries by their weights, so the mix varies a little
# each run (e.g. total 35, chests weight 25, gun stores weight 10).
# Spawn region: a box centered on this node. Rays drop from the top of the box to its bottom,
# like the enemy spawner, and each spot is checked for flat floor, open space and spacing.
# The box is drawn in the editor (not in game) so you can see and size the region.
@tool
extends Node3D
class_name InteractableSpawner

@export_group("Spawns")
## How many interactables to place in total when the game starts.
@export var total_count := 35
## What can spawn and how often. Add a row per interactable type.
@export var entries : Array[InteractableSpawnEntry]

@export_group("Area")
## Size of the spawn region in meters, centered on this node.
## X/Z = footprint. Y = how far above and below this node the rays search for floor.
@export var area_size := Vector3(100.0, 60.0, 100.0):
	set(v):
		area_size = v
		_update_preview()
## Draw the region as a see-through box in the editor.
@export var show_area_in_editor := true:
	set(v):
		show_area_in_editor = v
		_update_preview()

@export_group("Placement Rules")
## Surfaces flatter than this count as floor (same rule as the enemy spawner).
@export_range(0.0, 1.0) var min_floor_normal_y := 0.8
## Free space needed around an interactable, in meters. Spots touching walls or props are skipped.
@export var clearance_radius := 0.8
## Interactables (including hand-placed chests and stores) won't spawn closer than this to each other.
@export var min_spacing := 8.0
## Nothing spawns closer than this to the player's starting position.
@export var min_distance_from_player := 6.0
## Random spots tried per interactable before giving up on it.
@export var max_attempts_per_spawn := 30

@export_group("Look")
## Random tilt in degrees, in any direction. The lid side always stays facing up.
@export_range(0.0, 30.0, 0.5) var max_tilt_degrees := 6.0
## 0 = chests stand straight up, 1 = they lean fully with the slope they sit on.
@export_range(0.0, 1.0) var align_to_slope := 0.5
## How far interactables sink into the floor, so tilting never leaves a gap under one edge.
@export var sink_depth := 0.06

var _preview : MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	# Wait one physics frame so the level's colliders are registered before casting rays.
	await get_tree().physics_frame
	spawn_all()


## Places everything. Safe to call again later (e.g. a new stage) to add another batch.
func spawn_all() -> void:
	var plan := roll_counts()
	if plan.is_empty():
		push_warning("%s: no entries with a scene and weight assigned" % name)
		return

	# Start the spacing check with anything already in the level (hand-placed chests, stores).
	var placed : Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(&"interactables"):
		placed.append((node as Node3D).global_position)

	# Shuffle the order so a crowded map doesn't always run out of room on the last type.
	var queue : Array[InteractableSpawnEntry] = []
	for entry: InteractableSpawnEntry in plan:
		for i in plan[entry]:
			queue.append(entry)
	queue.shuffle()

	var spawned := {}
	for entry in queue:
		if _spawn_one(entry.scene, placed, entry.allow_tilt):
			spawned[entry] = spawned.get(entry, 0) + 1
	for entry: InteractableSpawnEntry in plan:
		print("InteractableSpawner: placed %d/%d %s" % [spawned.get(entry, 0), plan[entry],
				entry.scene.resource_path.get_file().get_basename()])


## How many of each entry to place this time: minimums first, then the rest of
## Total Count picked one at a time by weight (respecting max counts).
func roll_counts() -> Dictionary:
	var counts := {}
	var valid : Array[InteractableSpawnEntry] = []
	for entry in entries:
		if entry != null and entry.scene != null:
			valid.append(entry)
			counts[entry] = mini(entry.min_count, entry.max_count) if entry.max_count > 0 else entry.min_count
	if valid.is_empty():
		return {}

	var used := 0
	for entry in valid:
		used += counts[entry]
	for i in maxi(total_count - used, 0):
		var total_weight := 0.0
		for entry in valid:
			if entry.max_count <= 0 or counts[entry] < entry.max_count:
				total_weight += entry.weight
		if total_weight <= 0.0:
			break
		var r := randf() * total_weight
		for entry in valid:
			if entry.max_count > 0 and counts[entry] >= entry.max_count:
				continue
			r -= entry.weight
			if r < 0.0:
				counts[entry] += 1
				break
	return counts


func _spawn_one(scene: PackedScene, placed: Array[Vector3], allow_tilt := true) -> bool:
	var hit := _find_spot(placed)
	if hit.is_empty():
		return false

	var obj : Node3D = scene.instantiate()
	add_child(obj)

	# Lowest point of the model in its own space, so any model sits on the floor
	# regardless of where its origin was exported.
	var bounds := _get_local_bounds(obj)
	var bottom := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)

	var rot := _random_basis(hit.normal) if allow_tilt else Basis(Vector3.UP, randf() * TAU)
	var origin : Vector3 = hit.position - rot * bottom - Vector3.UP * sink_depth
	obj.global_transform = Transform3D(rot, origin)
	if obj.has_method(&"reset_physics_interpolation"):
		obj.reset_physics_interpolation()

	placed.append(hit.position)
	return true


# Tries random spots until one passes every rule. Returns the floor hit, or {} if none did.
func _find_spot(placed: Array[Vector3]) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var player := GameManager.player
	var exclude : Array[RID] = []
	if player != null:
		exclude.append(player.get_rid())

	var half := area_size * 0.5
	for attempt in max_attempts_per_spawn:
		var local := Vector3(randf_range(-half.x, half.x), half.y, randf_range(-half.z, half.z))
		var from := to_global(local)
		var to := to_global(Vector3(local.x, -half.y, local.z))
		var hit := _raycast(space, from, to)

		if hit.is_empty():
			continue   # no floor under this spot
		if hit.normal.y < min_floor_normal_y:
			continue   # too steep
		if hit.collider is Node and (hit.collider as Node).get_parent() is Interactable:
			continue   # landed on another interactable or pickup
		if player != null and _flat_dist_sq(hit.position, player.global_position) < min_distance_from_player * min_distance_from_player:
			continue
		if _too_close(hit.position, placed):
			continue
		if not _has_clearance(space, hit.position, exclude):
			continue
		return hit
	return {}


func _too_close(point: Vector3, placed: Array[Vector3]) -> bool:
	for p in placed:
		if _flat_dist_sq(point, p) < min_spacing * min_spacing:
			return true
	return false


# A sphere just above the floor must touch nothing: rejects spots inside walls,
# under overhangs that are too low, or jammed against props.
func _has_clearance(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array[RID]) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = clearance_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (clearance_radius + 0.1))
	query.exclude = exclude
	for result in space.intersect_shape(query, 4):
		if not (result.collider is CharacterBody3D):   # enemies don't block placement
			return false
	return true


# Ray that passes through characters (player and enemies) to find the floor under them.
func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var exclude : Array[RID] = []
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not (hit.collider is CharacterBody3D):
			return hit
		exclude.append(hit.rid)
	return {}


# Random spin, a small random tilt, then partly leaned into the slope. Up stays up.
func _random_basis(floor_normal: Vector3) -> Basis:
	var rot := Basis(Vector3.UP, randf() * TAU)
	var tilt_axis := Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	rot = Basis(tilt_axis, deg_to_rad(randf_range(0.0, max_tilt_degrees))) * rot
	var up := Vector3.UP.lerp(floor_normal, align_to_slope).normalized()
	if not up.is_equal_approx(Vector3.UP):
		rot = Basis(Quaternion(Vector3.UP, up)) * rot
	return rot


# Bounding box of every mesh under the node, in the node's own space.
static func _get_local_bounds(node: Node3D) -> AABB:
	var to_local := node.global_transform.affine_inverse()
	var bounds := AABB()
	var found := false
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		var geo := child as GeometryInstance3D
		var box : AABB = to_local * geo.global_transform * geo.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds if found else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


static func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()


# ---------- Editor preview ----------

func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not show_area_in_editor:
		if _preview != null:
			_preview.queue_free()
			_preview = null
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.8, 0.1, 0.12)
		_preview.material_override = mat
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview)   # no owner: never saved into the scene
	var box := BoxMesh.new()
	box.size = area_size
	_preview.mesh = box
