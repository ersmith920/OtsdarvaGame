extends Node3D
class_name Bullet

@export var speed : float = 50
@export var curve_time : float = 1
@export var hit_effect : PackedScene
@export var camera_shake_time : float = 0
@export var delete_after : float = 4
## How far a ricochet can reach for its next enemy.
@export var ricochet_range : float = 60.0

@export_group("Explosion")
## If set, the bullet detonates this on impact instead of doing direct damage.
@export var explosion_scene : PackedScene

var source : Gun
var elapsed_time : float = 0

const MAX_HIT_EFFECTS := 40   # a fast gun on a crowd can hit hundreds of times a second
static var _active_hit_effects := 0

const MAX_LOS_CHECKS := 4
var _ricochet_rolled := false
var _ricochets_left := 0
var _hit_enemies : Array = []   # enemies this bullet has already hit

# The bullet is a plain Node3D: it has no body in the physics server at all.
# All hit detection is done with the raycast below, so moving it every frame is free
# as far as physics is concerned.

func _physics_process(delta: float) -> void:
	var speed_factor : float = source.projectile_speed.sample(elapsed_time / curve_time)
	var motion := global_basis.z * delta * speed * speed_factor
	elapsed_time += delta

	if elapsed_time > delete_after:
		queue_free()
		return

	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion)
	query.collision_mask = 1 | 16
	query.hit_from_inside = true
	query.exclude = _build_exclude_list()
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		global_position += motion
		return

	global_position = result.position
	hit(result.collider, result.normal)


func hit(collider : Object, normal : Vector3 = Vector3.ZERO) -> void:
	_spawn_hit_effect(normal)

	if collider is Enemy:
		var roll : Dictionary = source.roll_damage()
		collider.take_damage(roll.damage, roll.crit)
	if explosion_scene != null:
		_explode()

	if collider is Enemy and _try_ricochet(collider):
		return
	queue_free()


func _explode() -> void:
	var blast : Explosion = explosion_scene.instantiate()
	get_tree().current_scene.add_child(blast)
	blast.detonate(global_position, source)

# Rolls the ricochet chance (once per bullet) and, if the bullet has bounces left,
# turns it toward the next closest enemy. Returns true if the bullet lives on.
func _try_ricochet(from_enemy : Enemy) -> bool:
	if not _ricochet_rolled:
		_ricochet_rolled = true
		if randf() < source.get_ricochet_chance():
			_ricochets_left = source.get_ricochet_bounces()
	if _ricochets_left <= 0:
		return false

	_hit_enemies.append(from_enemy)
	var target := _find_ricochet_target()
	if target == null:
		return false

	_ricochets_left -= 1
	var point := _aim_point_of(target)
	var dir := point - global_position
	if dir.length_squared() < 0.01:
		return false
	# Avoid look_at errors when aiming straight up or down.
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	look_at(point, up, true)
	return true


# Closest living enemy within range that this bullet hasn't hit yet.
func _find_ricochet_target() -> Node3D:
	var range_sq := ricochet_range * ricochet_range
	var origin := global_position
	var dists := PackedFloat32Array()
	var enemies : Array[Enemy] = []

	for node in get_tree().get_nodes_in_group("lock_target"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_queued_for_deletion() or _hit_enemies.has(enemy):
			continue
		var d := origin.distance_squared_to(enemy.get_aim_position())
		if d <= range_sq:
			dists.append(d)
			enemies.append(enemy)

	var exclude := _build_exclude_list()
	for attempt in MAX_LOS_CHECKS:
		# Pick the closest remaining one: no sort needed.
		var best := -1
		var best_d := INF
		for i in dists.size():
			if dists[i] < best_d:
				best_d = dists[i]
				best = i
		if best == -1:
			return null
		if _has_line_of_sight(enemies[best], exclude):
			return enemies[best]
		dists.remove_at(best)
		enemies.remove_at(best)
	return null

# The player and enemies this bullet already hit must not block its rays.
# (The bullet itself has no physics body anymore, so it doesn't need excluding.)
func _build_exclude_list() -> Array[RID]:
	var rids : Array[RID] = []
	if GameManager.player != null:
		rids.append(GameManager.player.get_rid())
	for enemy in _hit_enemies:
		if is_instance_valid(enemy):
			rids.append((enemy as CollisionObject3D).get_rid())
	return rids


func _has_line_of_sight(enemy : Node3D, exclude : Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, _aim_point_of(enemy))
	query.exclude = exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	# Fine if the first thing hit is the enemy itself (or part of it).
	var collider := result.collider as Node
	return collider == enemy or enemy.is_ancestor_of(collider) or collider.is_ancestor_of(enemy)

# Aim at a child Marker3D named "AimPoint" if the enemy has one, otherwise its origin.
func _aim_point_of(enemy: Node3D) -> Vector3:
	if enemy is Enemy:
		return (enemy as Enemy).get_aim_position()
	return enemy.global_position

func _spawn_hit_effect(normal : Vector3) -> void:
	if hit_effect == null or _active_hit_effects >= MAX_HIT_EFFECTS:
		return
	# Sparks fly out along the surface normal. If the ray started inside a shape the
	# normal is zero, so fall back to straight back toward the shooter.
	var dir := normal if normal.length_squared() > 0.001 else -global_basis.z
	dir = dir.normalized()

	var fx := hit_effect.instantiate() as Node3D
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT   # avoids look_at errors
	fx.look_at(fx.global_position + dir, up, true)   # true = the effect's +Z points along dir
	fx.reset_physics_interpolation()

	_active_hit_effects += 1
	var particles := fx as GPUParticles3D
	if particles != null:
		particles.one_shot = true
		particles.restart()
		particles.finished.connect(Bullet._release_hit_effect.bind(fx))
	else:
		# Effect scene isn't a bare GPUParticles3D: just clean it up after a couple of seconds.
		get_tree().create_timer(2.0).timeout.connect(Bullet._release_hit_effect.bind(fx))


static func _release_hit_effect(fx : Node) -> void:
	_active_hit_effects -= 1
	if is_instance_valid(fx):
		fx.queue_free()
