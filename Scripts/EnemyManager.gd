# Moves every enemy in one loop. Enemies are NOT moved by the physics engine:
# soft circle separation via a spatial grid, rays for ground/walls, and a climbing rule.
extends Node

const CELL_SIZE := 2.0
const CELL_STRIDE := 100003
const PROBE_INTERVAL := 4         # each enemy re-thinks and re-probes once per N ticks
const GRAVITY := 24.0
const STEP_UP_SPEED := 10.0       # how fast non-climbers rise onto a ledge
const FALL_KILL_Y := -100.0
const WORLD_MASK := 1
const PLAYER_RADIUS := 0.5
const PLAYER_HALF_HEIGHT := 1.0   # player origin is the capsule center
const MAX_PUSH_SPEEDS := 2.0      # separation can move an enemy at most this x its speed
const EPS := 0.05
const MAX_NEIGHBORS := 30
const SEPARATE_INTERVAL := 2
const KNOCK_DECEL := 40.0         # m/s lost per second: a 10 m/s knock slides ~1.25 m in 0.25 s
const MAX_KNOCK_SPEED := 40.0     # stacked blasts can't launch an enemy faster than this


var enemies: Array[Enemy] = []
var _grid := {}
var _tick := 0
var _ray_exclude: Array[RID] = []


func register(e: Enemy) -> void:
	e.mgr_index = enemies.size()
	enemies.append(e)


func unregister(e: Enemy) -> void:
	var idx := e.mgr_index
	if idx < 0 or idx >= enemies.size() or enemies[idx] != e:
		return
	var last: Enemy = enemies.back()
	enemies[idx] = last
	last.mgr_index = idx
	enemies.pop_back()
	e.mgr_index = -1


## Pushes an enemy: `push` is a horizontal velocity (m/s), `up` an upward pop (m/s).
## Scaled by the enemy's knockback_resist. One ray along the push makes sure the
## slide stops at walls instead of shoving the enemy into buildings.
func knock_back(e: Enemy, push: Vector3, up: float) -> void:
	if e.dead or e.spawning:
		return
	var keep := 1.0 - e.knockback_resist
	if keep <= 0.0:
		return
	push.y = 0.0
	var v := (e.knock + push * keep).limit_length(MAX_KNOCK_SPEED)
	var speed := v.length()
	if speed > 0.01:
		var dir := v / speed
		var travel := speed * speed / (2.0 * KNOCK_DECEL)   # how far this push will slide
		var from := e.pos + Vector3.UP * (e.step_height - 0.1)
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, from + dir * (travel + e.radius), WORLD_MASK, _ray_exclude))
		if not hit.is_empty() and hit.normal.y < 0.7:
			# Wall in the way: shrink the push so the slide ends right at the wall.
			var room := maxf(from.distance_to(hit.position) - e.radius, 0.0)
			v = dir * sqrt(2.0 * KNOCK_DECEL * room)
	e.knock = v
	if up > 0.0:
		e.vy = maxf(e.vy, up * keep)


func _physics_process(delta: float) -> void:
	var player := GameManager.player
	if player == null or enemies.is_empty():
		return
	_tick += 1
	var ppos := player.global_position
	var space := get_viewport().world_3d.direct_space_state
	_ray_exclude = [player.get_rid()]
	_rebuild_grid()

	for i in enemies.size():
		var e := enemies[i]
		if e.dead:
			continue
		if e.spawning:
			e.step_spawn(delta)   # rising out of the floor: no thinking, moving or attacking
		else:
			_step(e, i, delta, player, ppos, space)


func _rebuild_grid() -> void:
	_grid.clear()
	for e in enemies:
		if e.dead:
			continue
		if e.fresh:
			e.pos = e.global_position   # spawner sets the position after _ready
		var key := floori(e.pos.x / CELL_SIZE) * CELL_STRIDE + floori(e.pos.z / CELL_SIZE)
		var cell = _grid.get(key)
		if cell == null:
			_grid[key] = [e]
		else:
			cell.append(e)


func _step(e: Enemy, i: int, delta: float, player: Player, ppos: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	# --- Think + probe (staggered: only 1/PROBE_INTERVAL of enemies per tick) ---
	if e.fresh or (i + _tick) % PROBE_INTERVAL == 0:
		e.fresh = false
		var to_player := ppos - e.pos
		to_player.y = 0.0
		e.wish_dir = e.compute_wish_dir(to_player, to_player.length())
		if e.wish_dir != Vector3.ZERO and e.face_move_direction:
			e.rotation.y = atan2(-e.wish_dir.x, -e.wish_dir.z)
		_probe(e, space)

	# --- Horizontal movement, blocked by walls (or turned into a climb) ---
	var vel := e.wish_dir * e.speed
	e.climbing = false
	if e.wall_normal != Vector3.ZERO and vel.dot(e.wall_normal) < 0.0:
		vel = vel.slide(e.wall_normal)
		e.climbing = e.can_climb
	e.pos.x += vel.x * delta
	e.pos.z += vel.z * delta

	# --- Knockback slide (wall-checked once when it was applied) ---
	if e.knock != Vector3.ZERO:
		e.pos.x += e.knock.x * delta
		e.pos.z += e.knock.z * delta
		e.knock = e.knock.move_toward(Vector3.ZERO, KNOCK_DECEL * delta)

	# --- Soft collision (also computes support from enemies below, for climbers) ---
	if (i + _tick) % SEPARATE_INTERVAL == 0:
		_separate(e, ppos, delta * SEPARATE_INTERVAL)

	# --- Vertical movement ---
	var floor_y := maxf(e.ground_y, e.support_y)
	if e.climbing:
		e.pos.y += e.climb_speed * delta
		e.vy = 0.0
	elif e.pos.y < floor_y - 0.001:
		var rise := e.climb_speed if e.can_climb else STEP_UP_SPEED
		e.pos.y = minf(e.pos.y + rise * delta, floor_y)
		e.vy = 0.0
	else:
		e.vy -= GRAVITY * delta
		e.pos.y = maxf(e.pos.y + e.vy * delta, floor_y)
		if e.pos.y <= floor_y:
			e.vy = 0.0

	if e.pos.y < FALL_KILL_Y:
		e.fall_out()
		return

	e.global_position = e.pos

	# --- Contact attack: plain distance check, no collision callbacks ---
	var dx := ppos.x - e.pos.x
	var dz := ppos.z - e.pos.z
	var reach := e.radius + PLAYER_RADIUS + e.attack_reach
	if dx * dx + dz * dz <= reach * reach and _overlaps_player_vertically(e, ppos):
		e.try_contact_attack(player)


func _overlaps_player_vertically(e: Enemy, ppos: Vector3) -> bool:
	var feet := ppos.y - PLAYER_HALF_HEIGHT
	return e.pos.y < feet + PLAYER_HALF_HEIGHT * 2.0 and e.pos.y + e.height > feet


# Ground height and wall in front. 3 rays per probe.
func _probe(e: Enemy, space: PhysicsDirectSpaceState3D) -> void:
	var ground := -INF

	# Ground under the enemy.
	var from := e.pos + Vector3.UP * e.step_height
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * 200.0, WORLD_MASK, _ray_exclude))
	if not hit.is_empty():
		ground = hit.position.y

	# Ground just ahead: lets enemies step up ledges and mantle the top of a wall they climbed.
	if e.wish_dir != Vector3.ZERO:
		var ahead := from + e.wish_dir * (e.radius + 0.3)
		var ahit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				ahead, ahead + Vector3.DOWN * (e.step_height * 2.0), WORLD_MASK, _ray_exclude))
		if not ahit.is_empty():
			ground = maxf(ground, ahit.position.y)
	e.ground_y = ground

	# Wall ahead, from just below step height so low ledges don't block.
	e.wall_normal = Vector3.ZERO
	if e.wish_dir != Vector3.ZERO:
		var wfrom := e.pos + Vector3.UP * (e.step_height - 0.1)
		var whit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				wfrom, wfrom + e.wish_dir * (e.radius + 0.4), WORLD_MASK, _ray_exclude))
		if not whit.is_empty() and whit.normal.y < 0.7:
			e.wall_normal = Vector3(whit.normal.x, 0.0, whit.normal.z).normalized()


func _separate(e: Enemy, ppos: Vector3, delta: float) -> void:
	var p := e.pos
	var push := Vector2.ZERO
	var support := -INF
	var checked := 0

	# The player is a fixed circle: enemies ring around it instead of overlapping.
	if _overlaps_player_vertically(e, ppos):
		var d := Vector2(p.x - ppos.x, p.z - ppos.z)
		var min_d := e.radius + PLAYER_RADIUS
		var dsq := d.length_squared()
		if dsq < min_d * min_d:
			var dist := sqrt(dsq)
			var dir := d / dist if dist > 0.001 else Vector2.from_angle(randf() * TAU)
			push += dir * (min_d - dist)

	var cx := floori(p.x / CELL_SIZE)
	var cz := floori(p.z / CELL_SIZE)
	for gx in range(cx - 1, cx + 2):
		if checked >= MAX_NEIGHBORS:
			break
		for gz in range(cz - 1, cz + 2):
			if checked >= MAX_NEIGHBORS:
				break
			var cell = _grid.get(gx * CELL_STRIDE + gz)
			if cell == null:
				continue
			for n: Enemy in cell:
				if n == e or n.dead:
					continue
				checked += 1
				if checked > MAX_NEIGHBORS:
					break
				var d := Vector2(p.x - n.pos.x, p.z - n.pos.z)
				var min_d := e.radius + n.radius
				var dsq := d.length_squared()
				if dsq >= min_d * min_d:
					continue
				var n_top := n.pos.y + n.height

				if e.can_climb:
					if n.pos.y >= p.y + e.height - EPS or n_top <= p.y - EPS:
						continue                        # entirely above or below me
					if n_top <= p.y + EPS:
						support = maxf(support, n_top)  # already standing on it
						continue
					# Only climb things in front of me: within ~60 degrees of my movement
					# direction, and not past the stack cap.
					if e.wish_dir != Vector3.ZERO and n_top - e.ground_y <= e.max_climb_height:
						var fwd := Vector2(e.wish_dir.x, e.wish_dir.z)
						if (-d).dot(fwd) > sqrt(dsq) * 0.5:
							support = maxf(support, n_top)
							continue
					# Behind or beside me: fall through and push apart like a normal neighbor.

				# Non-climbers: horizontal push unless vertically apart.
				if n.pos.y >= p.y + e.height - EPS or n_top <= p.y + EPS:
					continue
				var dist := sqrt(dsq)
				var dir := d / dist if dist > 0.001 else Vector2.from_angle(randf() * TAU)
				push += dir * ((min_d - dist) * 0.5)

	push = push.limit_length(e.speed * delta * MAX_PUSH_SPEEDS)
	e.pos.x += push.x
	e.pos.z += push.y
	e.support_y = support
