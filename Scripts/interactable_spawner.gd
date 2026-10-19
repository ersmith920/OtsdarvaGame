# Scatters interactables (chests for now) across the level when the game starts.
# Spawn region: a box centered on this node. Rays drop from the top of the box to its bottom,
# like the enemy spawner, and each spot is checked for flat floor, open space and spacing.
# The box is drawn in the editor (not in game) so you can see and size the region.
@tool
extends Node3D
class_name InteractableSpawner

@export_group("Chests")
## The chest to spawn (item_chest.tscn).
@export var chest_scene : PackedScene
## How many chests to place when the game starts.
@export var chest_count := 10

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
## Free space needed around a chest, in meters. Spots touching walls or props are skipped.
@export var clearance_radius := 0.8
## Chests (including hand-placed ones) won't spawn closer than this to each other.
@export var min_spacing := 8.0
## Chests won't spawn closer than this to the player's starting position.
@export var min_distance_from_player := 6.0
## Random spots tried per chest before giving up on it.
@export var max_attempts_per_chest := 30

@export_group("Look")
## Random tilt in degrees, in any direction. The lid side always stays facing up.
@export_range(0.0, 30.0, 0.5) var max_tilt_degrees := 6.0
## 0 = chests stand straight up, 1 = they lean fully with the slope they sit on.
@export_range(0.0, 1.0) var align_to_slope := 0.5
## How far chests sink into the floor, so tilting never leaves a gap under one edge.
@export var sink_depth := 0.06

var _preview : MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	# Wait one physics frame so the level's colliders are registered before casting rays.
	await get_tree().physics_frame
	spawn_all()


## Places every chest. Safe to call again later (e.g. a new stage) to add another batch.
func spawn_all() -> void:
	if chest_scene == null:
		push_warning("%s: no chest_scene assigned" % name)
		return

	# Start the spacing check with any chests already in the level (hand-placed ones).
	var placed : Array[Vector3] = []
	for chest in get_tree().get_nodes_in_group(&"chests"):
		placed.append((chest as Node3D).global_position)

	var spawned := 0
	for i in chest_count:
		if _spawn_one(chest_scene, placed):
			spawned += 1
	print("InteractableSpawner: placed %d/%d chests" % [spawned, chest_count])


func _spawn_one(scene: PackedScene, placed: Array[Vector3]) -> bool:
	var hit := _find_spot(placed)
	if hit.is_empty():
		return false

	var obj : Node3D = scene.instantiate()
	add_child(obj)

	# Lowest point of the model in its own space, so any chest model sits on the floor
	# regardless of where its origin was exported.
	var bounds := _get_local_bounds(obj)
	var bottom := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)

	var rot := _random_basis(hit.normal)
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
	for attempt in max_attempts_per_chest:
		var local := Vector3(randf_range(-half.x, half.x), half.y, randf_range(-half.z, half.z))
		var from := to_global(local)
		var to := to_global(Vector3(local.x, -half.y, local.z))
		var hit := _raycast(space, from, to)

		if hit.is_empty():
			continue   # no floor under this spot
		if hit.normal.y < min_floor_normal_y:
			continue   # too steep
		if hit.collider is Node and (hit.collider as Node).get_parent() is Interactable:
			continue   # landed on another chest or pickup
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
