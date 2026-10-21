# The smart crosshair. Finds the target nearest the screen center, moves the crosshair
# onto it, and exposes where the guns should aim. The crosshair is a 2D HUD element.
class_name LockOn
extends Node3D

const TARGET_GROUP := &"lock_target"   # enemies join this group to be lockable
const MAX_LOCK_RANGE := 80.0           # ignore targets farther than this
const REST_MAX_DISTANCE := 100.0       # how far the guns aim when looking at open sky
const MIN_REST_DISTANCE := 8.0         # keeps guns from crossing sharply near walls
const REQUIRE_LINE_OF_SIGHT := true    # don't lock onto targets behind walls
# Only used to project the crosshair's direction onto the screen; any positive number works.
const SCREEN_PROJECT_DISTANCE := 10.0
# Most-centered swarm enemies checked for line of sight each frame.
const SWARM_CANDIDATES := 8

@export var crosshair: Control   # the 2D HUD crosshair (drag it in from the scene)
@export var idle_color := Color(1.0, 1.0, 1.0, 0.6)
@export var locked_color := Color(1.0, 0.25, 0.25, 0.85)

@onready var camera: Camera3D = get_parent() as Camera3D

var target: Object = null   # the currently locked target: an Enemy node or a SwarmUnit (null = none)

# Smoothed state: the crosshair's direction (in camera space) and the guns' aim distance.
var _local_dir := Vector3.FORWARD
var _distance := REST_MAX_DISTANCE
# Where those are heading (updated every physics frame).
var _desired_local_dir := Vector3.FORWARD
var _desired_distance := REST_MAX_DISTANCE

var _aim_point := Vector3.ZERO
var _exclude: Array[RID] = []   # colliders the aim rays must ignore
var _exclude_countdown := 0

# ---------- What the guns use ----------

func is_locked() -> bool:
	return target != null

## World-space direction from the camera toward the crosshair.
func get_aim_direction() -> Vector3:
	return (camera.global_basis * _local_dir).normalized()

## World-space point the guns should aim at.
func get_aim_point() -> Vector3:
	return _aim_point


# ---------- Target selection (physics frame, since it uses raycasts) ----------

func _physics_process(_delta: float) -> void:
	if GameManager.player == null:
		return
	_exclude_countdown -= 1
	if _exclude_countdown <= 0:
		_exclude = _build_exclude_list()
		_exclude_countdown = 15

	var stats := GameManager.player.stats_node
	var max_angle := deg_to_rad(stats.get_value(&"lock_fov"))
	# A locked enemy that died (freed node or dead swarm unit): drop it right away.
	if target != null and (not is_instance_valid(target) or (target is SwarmUnit and target.dead)):
		target = null
	target = _find_target(max_angle)

	if target != null:
		var point := _aim_point_of(target)
		_desired_local_dir = camera.to_local(point).normalized()
		_desired_distance = camera.global_position.distance_to(point)
	else:
		_desired_local_dir = Vector3.FORWARD
		_desired_distance = maxf(_distance_to_surface(), MIN_REST_DISTANCE)


# Everything attached to the player (body, held guns) must be ignored by the aim rays.
func _build_exclude_list() -> Array[RID]:
	var rids: Array[RID] = [GameManager.player.get_rid()]
	for node in GameManager.player.find_children("*", "CollisionObject3D", true, false):
		rids.append((node as CollisionObject3D).get_rid())
	return rids


# Returns the target closest to the screen center within max_angle, or null.
func _find_target(max_angle: float) -> Object:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	# Swarm enemies: the Swarm returns its few most centered ones (already sorted).
	var candidates: Array = Swarm.lock_candidates(origin, forward, max_angle, MAX_LOCK_RANGE, SWARM_CANDIDATES)

	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var to_point := _aim_point_of(enemy) - origin
		var dist := to_point.length()
		if dist > MAX_LOCK_RANGE or dist < 0.01:
			continue
		# The smaller the angle from where the camera looks, the closer to screen center.
		var angle := forward.angle_to(to_point / dist)
		if angle <= max_angle:
			candidates.append([angle, enemy])

	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for candidate in candidates:
		if not REQUIRE_LINE_OF_SIGHT or _has_line_of_sight(candidate[1]):
			return candidate[1]
	return null


func _has_line_of_sight(enemy: Object) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, _aim_point_of(enemy))
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	if not (enemy is Node):
		return false   # swarm enemy: it has no body, so anything hit is in the way
	# Fine if the first thing hit is the enemy itself (or part of it).
	var collider := hit.collider as Node
	return collider == enemy or enemy.is_ancestor_of(collider) or collider.is_ancestor_of(enemy)


# Distance to whatever the camera is looking at, so bullets converge where you look.
func _distance_to_surface() -> float:
	var from := camera.global_position
	var to := from - camera.global_basis.z * REST_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return REST_MAX_DISTANCE
	return from.distance_to(hit.position)


# Aim at a child Marker3D named "AimPoint" if the enemy has one, otherwise its origin.
func _aim_point_of(enemy: Object) -> Vector3:
	if enemy is Enemy or enemy is SwarmUnit:
		return enemy.get_aim_position()
	return (enemy as Node3D).global_position


# ---------- Moving the crosshair (every frame, for smoothness) ----------

func _process(delta: float) -> void:
	if GameManager.player == null:
		return

	var strength := GameManager.player.stats_node.get_value(&"lock_strength")
	# Frame-rate independent smoothing: higher strength = faster lock.
	var t := 1.0 - exp(-strength * delta)

	# slerp can't build a stable rotation axis when the two directions are almost
	# identical (which is exactly what happens once the lock settles), so snap
	# the last tiny gap instead of interpolating it.
	if _local_dir.angle_to(_desired_local_dir) < 0.0001:
		_local_dir = _desired_local_dir
	else:
		_local_dir = _local_dir.slerp(_desired_local_dir, t).normalized()
	_distance = lerpf(_distance, _desired_distance, t)

	_aim_point = camera.global_position + get_aim_direction() * _distance
	_update_crosshair()


# Draws the 2D crosshair from the aim DIRECTION, not the aim point, so walls and
# distance can never move it on screen. At rest it sits at the exact screen center.
func _update_crosshair() -> void:
	if crosshair == null:
		return

	var probe := camera.global_position + get_aim_direction() * SCREEN_PROJECT_DISTANCE
	if camera.is_position_behind(probe):
		crosshair.visible = false
		return

	crosshair.visible = true
	crosshair.position = camera.unproject_position(probe) - crosshair.size * 0.5
	crosshair.modulate = locked_color if target != null else idle_color

## Radius, in screen pixels, of the lock-on cone around the center of the screen.
func get_fov_screen_radius() -> float:
	# Clamp so a huge lock_fov can't point the probe at or behind the camera.
	var angle := minf(deg_to_rad(GameManager.player.stats_node.get_value(&"lock_fov")), deg_to_rad(89.0))

	# A point at exactly that angle off the camera's forward direction...
	var offset := camera.global_basis * Vector3(sin(angle), 0.0, -cos(angle))
	var edge := camera.global_position + offset * SCREEN_PROJECT_DISTANCE
	# ...and a point straight ahead, which lands on the screen center.
	var middle := camera.global_position - camera.global_basis.z * SCREEN_PROJECT_DISTANCE

	# How far apart they land on screen is the circle's radius.
	return camera.unproject_position(edge).distance_to(camera.unproject_position(middle))
