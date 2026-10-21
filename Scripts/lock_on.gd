# The smart crosshair(s). Finds targets near the screen center, moves crosshairs onto them,
# and tells each gun where to aim. The crosshairs are 2D HUD elements.
#
# Aim modes (mouse wheel, see Player): the lock-on circle is split between 1, 2 or 4
# crosshairs, each feeding some of the gun quadrants:
#   1 SINGLE:       one crosshair, every quadrant aims at it (the original behavior).
#   2 LEFT / RIGHT: the left guns and the right guns each get a crosshair.
#   3 TOP / BOTTOM: the upper guns and the lower guns each get a crosshair.
#   4 QUADRANTS:    every quadrant gets its own crosshair.
# A split crosshair goes for the enemy closest to the middle of its own half (or quarter) of
# the lock-on circle: its rest point, halfway between the screen center and the circle's edge.
# Enemies in its own region come first; if its region is empty it takes the closest one
# anywhere in the circle. With nothing in the circle at all it rests on its point.
class_name LockOn
extends Node3D

const TARGET_GROUP := &"lock_target"   # enemies join this group to be lockable
const MAX_LOCK_RANGE := 80.0           # ignore targets farther than this
const REST_MAX_DISTANCE := 100.0       # how far the guns aim when looking at open sky
const MIN_REST_DISTANCE := 8.0         # keeps guns from crossing sharply near walls
const REQUIRE_LINE_OF_SIGHT := true    # don't lock onto targets behind walls
# Only used to project the crosshair's direction onto the screen; any positive number works.
const SCREEN_PROJECT_DISTANCE := 10.0
# Swarm enemies looked at per crosshair each frame (the ones nearest its rest point).
const SWARM_CANDIDATES := 8
## How close (degrees) a crosshair must be to its locked enemy to count as on it.
const ON_TARGET_ANGLE := 1.5
## How far out a split crosshair rests, as a fraction of the lock-on circle's radius.
const REST_FRACTION := 0.5

enum Mode { SINGLE = 1, LEFT_RIGHT = 2, TOP_BOTTOM = 3, QUADRANTS = 4 }
const MODE_NAMES := {1: "Single Target", 2: "Split Left / Right", 3: "Split Top / Bottom", 4: "Split Quadrants"}

@export var crosshair: Control   # the 2D HUD crosshair (drag it in from the scene)
@export var idle_color := Color(1.0, 1.0, 1.0, 0.6)
@export var locked_color := Color(1.0, 0.25, 0.25, 0.85)

@onready var camera: Camera3D = get_parent() as Camera3D

## The current aim mode (1-4). Change it with set_mode().
var mode := Mode.SINGLE
## The first crosshair's locked target (an Enemy node or a SwarmUnit, null = none).
var target: Object:
	get:
		return _reticles[0].target if not _reticles.is_empty() else null


# One crosshair.
class Reticle:
	var rest := Vector2.ZERO     # rest point, in lock-circle radii (x = right, y = up)
	var region := Vector2.ZERO   # which part of the circle it picks from: -1 / +1 per axis, 0 = any
	var target: Object = null
	# Smoothed direction (camera space) and aim distance, and where they're heading.
	var local_dir := Vector3.FORWARD
	var distance := 100.0
	var desired_local_dir := Vector3.FORWARD
	var desired_distance := 100.0
	var aim_point := Vector3.ZERO
	var crosshair: Control
	var snap := 0.0   # 1 right after locking a new target, fading to 0 (the crosshair squeezes in)

	func is_on_target() -> bool:
		if target == null or not is_instance_valid(target) or (target is SwarmUnit and target.dead):
			return false
		return rad_to_deg(local_dir.angle_to(desired_local_dir)) <= LockOn.ON_TARGET_ANGLE


var _reticles : Array[Reticle] = []
var _quadrant_reticle := [0, 0, 0, 0]   # Player.Quadrant -> index into _reticles
var _spare_crosshairs : Array[Control] = []
var _mode_label : Label
var _mode_label_until := 0
var _exclude: Array[RID] = []   # colliders the aim rays must ignore
var _exclude_countdown := 0


func _ready() -> void:
	set_mode(Mode.SINGLE, false)


# ---------- Modes ----------

## Switches the aim mode (1-4). show_name: flash the mode's name on screen.
func set_mode(new_mode: int, show_name := true) -> void:
	new_mode = clampi(new_mode, Mode.SINGLE, Mode.QUADRANTS)
	if new_mode == mode and not _reticles.is_empty():
		return   # scrolled past the first or last mode: nothing changes
	var old : Reticle = _reticles[0] if not _reticles.is_empty() else null
	mode = new_mode as Mode
	var h := REST_FRACTION
	var d := REST_FRACTION * sqrt(0.5)   # along the diagonal, same distance out
	var specs : Array   # [rest, region] per crosshair
	# Player.Quadrant order: LOWER_RIGHT, LOWER_LEFT, UPPER_RIGHT, UPPER_LEFT
	match mode:
		Mode.SINGLE:
			specs = [[Vector2.ZERO, Vector2.ZERO]]
			_quadrant_reticle = [0, 0, 0, 0]
		Mode.LEFT_RIGHT:
			specs = [[Vector2(-h, 0), Vector2(-1, 0)], [Vector2(h, 0), Vector2(1, 0)]]
			_quadrant_reticle = [1, 0, 1, 0]
		Mode.TOP_BOTTOM:
			specs = [[Vector2(0, h), Vector2(0, 1)], [Vector2(0, -h), Vector2(0, -1)]]
			_quadrant_reticle = [1, 1, 0, 0]
		Mode.QUADRANTS:
			specs = [[Vector2(-d, d), Vector2(-1, 1)], [Vector2(d, d), Vector2(1, 1)],
					[Vector2(-d, -d), Vector2(-1, -1)], [Vector2(d, -d), Vector2(1, -1)]]
			_quadrant_reticle = [3, 2, 1, 0]

	_reticles.clear()
	for i in specs.size():
		var r := Reticle.new()
		r.rest = specs[i][0]
		r.region = specs[i][1]
		if old != null:
			# New crosshairs slide out from where the old one was, and aim where it aimed
			# until they've moved, so the guns don't jump for a frame.
			r.local_dir = old.local_dir
			r.distance = old.distance
			r.aim_point = old.aim_point
		r.crosshair = _crosshair_for(i)
		_reticles.append(r)
	for i in _spare_crosshairs.size():
		_spare_crosshairs[i].visible = i + 1 < _reticles.size()
	if show_name:
		_flash_mode_name()


## The aim mode's display name.
func get_mode_name() -> String:
	return MODE_NAMES.get(mode, "")


# Crosshair 0 is the one placed in the scene; the others are copies of it.
func _crosshair_for(i: int) -> Control:
	if crosshair == null:
		return null
	if i == 0:
		return crosshair
	while _spare_crosshairs.size() < i:
		var copy := crosshair.duplicate() as Control
		crosshair.get_parent().add_child.call_deferred(copy)
		_spare_crosshairs.append(copy)
	return _spare_crosshairs[i - 1]


func _flash_mode_name() -> void:
	if crosshair == null:
		return
	if _mode_label == null:
		_mode_label = Label.new()
		_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_mode_label.add_theme_font_size_override("font_size", 18)
		_mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_mode_label.add_theme_constant_override("outline_size", 4)
		crosshair.get_parent().add_child.call_deferred(_mode_label)
	_mode_label.text = "Aim: %s  [%d]" % [get_mode_name(), mode]
	_mode_label_until = Time.get_ticks_msec() + 1200


# ---------- What the guns use ----------

## True if any crosshair has a target.
func is_locked() -> bool:
	for r in _reticles:
		if r.target != null:
			return true
	return false


## World-space direction from the camera toward the first crosshair.
func get_aim_direction() -> Vector3:
	return _dir_of(_reticles[0])


## World-space point the first crosshair's guns should aim at.
func get_aim_point() -> Vector3:
	return _reticles[0].aim_point


## Where guns in this quadrant (Player.Quadrant) should aim.
func get_aim_point_for(quadrant: int) -> Vector3:
	return _reticle_for(quadrant).aim_point


## True once the crosshair has actually reached a locked enemy (not still sliding onto it).
## quadrant: that quadrant's crosshair; -1 = any crosshair. Auto-firing guns wait for this.
func is_on_target(quadrant := -1) -> bool:
	if quadrant >= 0:
		return _reticle_for(quadrant).is_on_target()
	for r in _reticles:
		if r.is_on_target():
			return true
	return false


func _reticle_for(quadrant: int) -> Reticle:
	return _reticles[mini(_quadrant_reticle[clampi(quadrant, 0, 3)], _reticles.size() - 1)]


func _dir_of(r: Reticle) -> Vector3:
	return (camera.global_basis * r.local_dir).normalized()


# ---------- Target selection (physics frame, since it uses raycasts) ----------

func _physics_process(_delta: float) -> void:
	if GameManager.player == null:
		return
	_exclude_countdown -= 1
	if _exclude_countdown <= 0:
		_exclude = _build_exclude_list()
		_exclude_countdown = 15

	var max_angle := deg_to_rad(GameManager.player.stats_node.get_value(&"lock_fov"))
	var candidates := _candidates(max_angle)
	var los_cache := {}
	for r in _reticles:
		var was : Object = r.target
		r.target = _pick_target(r, candidates, max_angle, los_cache)
		if r.target != null and r.target != was:
			r.snap = 1.0
		if r.target != null:
			var point := _aim_point_of(r.target)
			r.desired_local_dir = camera.to_local(point).normalized()
			r.desired_distance = camera.global_position.distance_to(point)
		else:
			r.desired_local_dir = _rest_dir(r, max_angle)
			r.desired_distance = maxf(_distance_along(camera.global_basis * r.desired_local_dir), MIN_REST_DISTANCE)


# Everything attached to the player (body, held guns) must be ignored by the aim rays.
func _build_exclude_list() -> Array[RID]:
	var rids: Array[RID] = [GameManager.player.get_rid()]
	for node in GameManager.player.find_children("*", "CollisionObject3D", true, false):
		rids.append((node as CollisionObject3D).get_rid())
	return rids


# Every lockable enemy inside the lock-on circle worth looking at, as
# [camera-space direction, enemy]. Node enemies are all checked. Swarm enemies come from
# the Swarm's nearest few around each crosshair's rest point, so a crosshair always sees the
# enemies closest to the middle of its own region (not just the ones nearest the screen center).
func _candidates(max_angle: float) -> Array:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var to_local := camera.global_basis.inverse()
	var out := []
	var seen := {}
	for r in _reticles:
		var rest := _rest_dir(r, max_angle)
		var rest_world := camera.global_basis * rest
		# A cone around the rest point wide enough to reach the far edge of the lock circle.
		var reach := max_angle + forward.angle_to(rest_world)
		for c in Swarm.lock_candidates(origin, rest_world, reach, MAX_LOCK_RANGE, SWARM_CANDIDATES):
			var unit : Object = c[1]
			if seen.has(unit):
				continue
			seen[unit] = true
			var to_point := _aim_point_of(unit) - origin
			if forward.angle_to(to_point) <= max_angle:   # only what's inside the lock circle
				out.append([(to_local * to_point).normalized(), unit])
	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var to_point := _aim_point_of(enemy) - origin
		var dist := to_point.length()
		if dist > MAX_LOCK_RANGE or dist < 0.01:
			continue
		if forward.angle_to(to_point / dist) <= max_angle:
			out.append([(to_local * to_point / dist).normalized(), enemy])
	return out


# The enemy closest to this crosshair's rest point (the middle of its region).
# Enemies inside its region come first; if its region is empty it takes the closest one
# anywhere in the lock circle, so it never sits idle while there's something to shoot.
func _pick_target(r: Reticle, candidates: Array, max_angle: float, los_cache: Dictionary) -> Object:
	var rest := _rest_dir(r, max_angle)
	var inside := []
	var outside := []
	for c in candidates:
		var dir : Vector3 = c[0]
		var entry := [rest.angle_to(dir), c[1]]
		var in_region := (r.region.x == 0.0 or signf(dir.x) == r.region.x) \
				and (r.region.y == 0.0 or signf(dir.y) == r.region.y)
		(inside if in_region else outside).append(entry)
	for group in [inside, outside]:
		group.sort_custom(func(a, b): return a[0] < b[0])
		for c in group:
			var enemy : Object = c[1]
			if not REQUIRE_LINE_OF_SIGHT:
				return enemy
			if not los_cache.has(enemy):
				los_cache[enemy] = _has_line_of_sight(enemy)
			if los_cache[enemy]:
				return enemy
	return null


# The crosshair's rest point as a camera-space direction.
func _rest_dir(r: Reticle, max_angle: float) -> Vector3:
	if r.rest == Vector2.ZERO:
		return Vector3.FORWARD
	var a := r.rest * max_angle
	return Vector3(tan(a.x), tan(a.y), -1.0).normalized()


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


# Distance to whatever lies along this world direction, so bullets converge where you look.
func _distance_along(dir: Vector3) -> float:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * REST_MAX_DISTANCE)
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


# ---------- Moving the crosshairs (every frame, for smoothness) ----------

func _process(delta: float) -> void:
	if GameManager.player == null:
		return

	var strength := GameManager.player.stats_node.get_value(&"lock_strength")
	# Frame-rate independent smoothing: higher strength = faster lock.
	var t := 1.0 - exp(-strength * delta)

	for r in _reticles:
		# slerp can't build a stable rotation axis when the two directions are almost
		# identical (which is exactly what happens once the lock settles), so snap
		# the last tiny gap instead of interpolating it.
		if r.local_dir.angle_to(r.desired_local_dir) < 0.0001:
			r.local_dir = r.desired_local_dir
		else:
			r.local_dir = r.local_dir.slerp(r.desired_local_dir, t).normalized()
		r.distance = lerpf(r.distance, r.desired_distance, t)
		r.aim_point = camera.global_position + _dir_of(r) * r.distance
		_update_crosshair(r)

	if _mode_label != null and _mode_label.is_inside_tree():
		var left := _mode_label_until - Time.get_ticks_msec()
		_mode_label.visible = left > 0
		if left > 0:
			_mode_label.modulate.a = clampf(left / 300.0, 0.0, 1.0)
			var view := _mode_label.get_viewport_rect().size
			_mode_label.reset_size()
			_mode_label.position = Vector2((view.x - _mode_label.size.x) * 0.5,
					view.y * 0.5 + get_fov_screen_radius() + 18.0)


# Draws a 2D crosshair from its aim DIRECTION, not the aim point, so walls and
# distance can never move it on screen. At rest (single mode) it sits at the screen center.
func _update_crosshair(r: Reticle) -> void:
	var c := r.crosshair
	if c == null or not c.is_inside_tree():
		return
	var probe := camera.global_position + _dir_of(r) * SCREEN_PROJECT_DISTANCE
	if camera.is_position_behind(probe):
		c.visible = false
		return
	c.visible = true
	c.position = camera.unproject_position(probe) - c.size * 0.5
	c.modulate = locked_color if r.target != null else idle_color
	# Locking on: the crosshair starts wide and squeezes in onto the target.
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * (1.0 + 0.7 * r.snap * r.snap)
	if r.snap > 0.0:
		c.modulate = c.modulate.lerp(Color.WHITE, r.snap * 0.6)
		r.snap = maxf(r.snap - get_process_delta_time() * 6.0, 0.0)

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
