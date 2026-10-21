extends Node3D
class_name Bullet

# Speed is set on the gun (Projectile Speed, plus an optional Speed Curve).
@export var hit_effect : PackedScene
@export var camera_shake_time : float = 0
@export var delete_after : float = 4
## How far a ricochet can reach for its next enemy.
@export var ricochet_range : float = 60.0

@export_group("Explosion Visual")
## Only used when the firing gun has its explosion turned on (damage, size and
## knockback are set on the gun). This is just what the blast looks like.
## Empty = the default see-through sphere below.
@export var explosion_effect : PackedScene
## The radius (m) explosion_effect was built at. It's scaled by gun radius / this,
## so an effect made 1 m wide fills a 5 m blast automatically.
@export var explosion_effect_radius := 1.0
## Seconds the explosion visual stays on screen.
@export var explosion_lifetime := 0.25
## Color of the default sphere (alpha = how see-through).
@export var explosion_color := Color(1.0, 0.1, 0.1, 0.35)

var source : Gun
var elapsed_time : float = 0

const MAX_HIT_EFFECTS := 40   # a fast gun on a crowd can hit hundreds of times a second
static var _active_hit_effects := 0

# Explosion visuals are capped the same way. Damage still happens past the cap.
const MAX_EXPLOSION_VISUALS := 40
static var _active_explosion_visuals := 0
static var _sphere_mesh : SphereMesh
static var _sphere_materials := {}   # Color -> StandardMaterial3D, one per color ever used

const MAX_LOS_CHECKS := 4
var _ricochet_rolled := false
var _ricochets_left := 0
var _bounces := 0   # ricochets done so far (hits after one proc at a reduced rate)
var _hit_enemies : Array = []   # enemies this bullet has already hit

# The bullet is a plain Node3D: it has no body in the physics server at all.
# All hit detection is done with the raycast below, so moving it every frame is free
# as far as physics is concerned.

var _dir := Vector3.ZERO         # travel direction (set by launch)
var _speed_bonus := 0.0          # forward speed inherited from the player
var _lateral := Vector3.ZERO     # sideways speed inherited from the player, fades out
var _settle_time := 0.15


## Called by the Gun right after spawning. See Gun._apply_player_velocity.
func launch(dir: Vector3, speed_bonus: float, lateral: Vector3, settle_time: float) -> void:
	_dir = dir.normalized()
	_speed_bonus = speed_bonus
	_lateral = lateral
	_settle_time = maxf(settle_time, 0.01)
	var up := Vector3.UP if absf(_dir.y) < 0.99 else Vector3.RIGHT   # avoids look_at errors
	look_at(global_position + _dir, up, true)


func _physics_process(delta: float) -> void:
	if _dir == Vector3.ZERO:
		_dir = global_basis.z   # spawned without launch(): fly straight ahead
	var speed := source.get_projectile_speed(elapsed_time) + _speed_bonus
	var motion := (_dir * speed + _lateral) * delta
	if _lateral != Vector3.ZERO:
		_lateral *= exp(-delta / _settle_time)
		if _lateral.length_squared() < 0.0001:
			_lateral = Vector3.ZERO
	elapsed_time += delta

	if elapsed_time > delete_after:
		queue_free()
		return

	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion)
	query.collision_mask = 1 | 16
	query.hit_from_inside = true
	query.exclude = _build_exclude_list()
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	# Swarm enemies have no physics bodies, so they're checked separately, only up to
	# whatever the physics ray hit first.
	var end := global_position + motion if result.is_empty() else (result.position as Vector3)
	var swarm_hit := Swarm.raycast(global_position, end, _swarm_skip())
	if not swarm_hit.is_empty():
		global_position = swarm_hit.position
		hit(swarm_hit.unit, swarm_hit.normal)
		return

	if result.is_empty():
		global_position += motion
		return

	global_position = result.position
	hit(result.collider, result.normal)


# Swarm enemies this bullet already hit (ricochets don't hit the same one twice).
func _swarm_skip() -> Dictionary:
	if _hit_enemies.is_empty():
		return {}
	var skip := {}
	for e in _hit_enemies:
		if is_instance_valid(e) and e is SwarmUnit:   # check validity first: hit enemies can be freed
			skip[e] = true
	return skip


func hit(collider : Object, normal : Vector3 = Vector3.ZERO) -> void:
	_spawn_hit_effect(normal)

	var is_enemy := collider is Enemy or collider is SwarmUnit
	if is_enemy:
		var roll : Dictionary = source.roll_damage()
		var ricocheted := _bounces > 0
		var proc := source.proc_coefficient * (source.ricochet_proc_multiplier if ricocheted else 1.0)
		var kind := HitInfo.Kind.RICOCHET if ricocheted else HitInfo.Kind.DIRECT
		HitSystem.deal_hit(HitInfo.make(collider, roll.damage, roll.crit, source, proc, kind, global_position))
	if source.explosion_enabled:
		_explode()

	if is_enemy and _try_ricochet(collider):
		return
	queue_free()


# ---------- Explosion ----------

func _explode() -> void:
	var r := source.get_explosion_radius()
	if r <= 0.0:
		return
	Explosion.detonate(get_world_3d().direct_space_state, global_position, r, source)
	_spawn_explosion_visual(r)


func _spawn_explosion_visual(r : float) -> void:
	if explosion_lifetime <= 0.0 or _active_explosion_visuals >= MAX_EXPLOSION_VISUALS:
		return

	var fx : Node3D
	if explosion_effect != null:
		fx = explosion_effect.instantiate() as Node3D
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position
		fx.scale = Vector3.ONE * (r / maxf(explosion_effect_radius, 0.01))
		var particles := fx as GPUParticles3D
		if particles != null:
			particles.one_shot = true
			particles.restart()
	else:
		fx = _make_default_sphere(r)
		get_tree().current_scene.add_child(fx)
		fx.global_position = global_position

	fx.reset_physics_interpolation()
	_active_explosion_visuals += 1
	# The tree owns this timer, so it still fires after the bullet itself is gone.
	get_tree().create_timer(explosion_lifetime).timeout.connect(Bullet._release_explosion_visual.bind(fx))


# See-through sphere that pops out to the blast radius, then fades.
func _make_default_sphere(r : float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _get_sphere_mesh()
	mesh.material_override = _get_sphere_material(explosion_color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # animated by a tween
	mesh.scale = Vector3.ONE * r * 0.3

	var tween := mesh.create_tween()   # owned by the mesh, so it dies with it
	tween.tween_property(mesh, "scale", Vector3.ONE * r, explosion_lifetime * 0.35)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Per-instance fade: the material stays shared.
	tween.tween_property(mesh, "transparency", 1.0, explosion_lifetime * 0.65)
	return mesh


# Unit-radius sphere shared by every explosion, so scale == blast radius.
static func _get_sphere_mesh() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 1.0
		_sphere_mesh.height = 2.0
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12
	return _sphere_mesh


static func _get_sphere_material(color : Color) -> StandardMaterial3D:
	var mat : StandardMaterial3D = _sphere_materials.get(color)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # still visible from inside the blast
		_sphere_materials[color] = mat
	return mat


static func _release_explosion_visual(fx : Node) -> void:
	_active_explosion_visuals -= 1
	if is_instance_valid(fx):
		fx.queue_free()


# ---------- Ricochet ----------

# Rolls the ricochet chance (once per bullet) and, if the bullet has bounces left,
# turns it toward the next closest enemy. Returns true if the bullet lives on.
func _try_ricochet(from_enemy : Object) -> bool:
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
	_bounces += 1
	var point := _aim_point_of(target)
	var dir := point - global_position
	if dir.length_squared() < 0.01:
		return false
	# Avoid look_at errors when aiming straight up or down.
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	look_at(point, up, true)
	_dir = global_basis.z        # fly straight at the new target
	_lateral = Vector3.ZERO
	return true


# Closest living enemy within range that this bullet hasn't hit yet and can see.
# Covers node enemies and swarm enemies (EnemyManager.find_nearest searches both).
func _find_ricochet_target() -> Object:
	var origin := global_position
	var skip := {}
	for e in _hit_enemies:
		skip[e] = true
	var exclude := _build_exclude_list()
	for attempt in MAX_LOS_CHECKS:
		var candidate = EnemyManager.find_nearest(origin, ricochet_range, skip)
		if candidate == null:
			return null
		if _has_line_of_sight(candidate, exclude):
			return candidate
		skip[candidate] = true   # blocked by a wall: try the next closest
	return null


# The player and enemies this bullet already hit must not block its rays.
# (The bullet itself has no physics body anymore, so it doesn't need excluding.)
func _build_exclude_list() -> Array[RID]:
	var rids : Array[RID] = []
	if GameManager.player != null:
		rids.append(GameManager.player.get_rid())
	for enemy in _hit_enemies:
		if is_instance_valid(enemy) and enemy is CollisionObject3D:
			rids.append((enemy as CollisionObject3D).get_rid())
	return rids


func _has_line_of_sight(enemy : Object, exclude : Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, _aim_point_of(enemy))
	query.exclude = exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	if not (enemy is Node):
		return false   # swarm enemy: it has no body, so anything hit is in the way
	# Fine if the first thing hit is the enemy itself (or part of it).
	var collider := result.collider as Node
	return collider == enemy or enemy.is_ancestor_of(collider) or collider.is_ancestor_of(enemy)

# Aim at a child Marker3D named "AimPoint" if the enemy has one, otherwise its origin.
func _aim_point_of(enemy: Object) -> Vector3:
	if enemy is Enemy or enemy is SwarmUnit:
		return enemy.get_aim_position()
	return (enemy as Node3D).global_position


# ---------- Hit effect ----------

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
