# Ranged enemy: keeps its distance from the player, repositions now and then,
# and fires fast shells from a turret that tracks the player independently of the body.
extends Enemy
class_name TankEnemy

@export_group("Range")
## The tank tries to hold a distance in this band (meters from the player).
@export var min_range := 10.0
@export var max_range := 20.0
## How far off its chosen distance it can drift before it moves again.
@export var range_tolerance := 2.0
## Seconds between repositions (random in this range).
@export var reposition_interval := Vector2(3.0, 6.0)
## How long it circles sideways during a reposition.
@export var strafe_time := 1.5

@export_group("Turning")
## Degrees per second.
@export var body_turn_speed := 120.0
@export var turret_turn_speed := 90.0

@export_group("Cannon")
@export var projectile_scene: PackedScene   # EnemyProjectile.tscn
@export var shell_speed := 80.0
@export var shell_damage := 20.0
## Seconds between shots.
@export var fire_interval := 3.0
## Pause (and stand still) before each shot, so the player can react.
@export var windup_time := 0.6
## Won't fire at targets farther than this.
@export var max_fire_range := 35.0
## The turret must be pointing this close to the target before it fires.
@export var aim_tolerance_deg := 4.0
## 0 = aim where the player is, 1 = fully lead their horizontal movement.
@export_range(0.0, 1.0) var lead_strength := 0.7

@export_group("Audio")
@export var charge_sound: AudioStream
@export var shot_sound: AudioStream

@onready var body: Node3D = $Body
@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle

const WORLD_MASK := 1

var _desired_dist := 15.0
var _next_reposition_ms := 0
var _strafe_until_ms := 0
var _strafe_sign := 1.0

var _winding_up := false
var _fire_at_ms := 0
var _next_shot_ms := 0


func _ready() -> void:
	super()
	face_move_direction = false   # the tank turns its own body and turret
	_schedule_reposition(Time.get_ticks_msec())
	# Stagger first shots so a group of tanks doesn't fire in unison.
	_next_shot_ms = Time.get_ticks_msec() + int(randf_range(0.5, fire_interval) * 1000.0)


# ---------- Movement (called by EnemyManager) ----------

func compute_wish_dir(to_player: Vector3, dist: float) -> Vector3:
	if _winding_up or dist < 0.01:
		return Vector3.ZERO   # plant its tracks while charging a shot

	var now := Time.get_ticks_msec()
	if now >= _next_reposition_ms:
		_schedule_reposition(now)

	var radial := to_player / dist
	var error := dist - _desired_dist
	if absf(error) > range_tolerance:
		return radial * signf(error)   # too far: close in, too close: back off

	if now < _strafe_until_ms:
		return radial.cross(Vector3.UP) * _strafe_sign   # circle around the player
	return Vector3.ZERO


func _schedule_reposition(now: int) -> void:
	_desired_dist = randf_range(min_range, max_range)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_strafe_until_ms = now + int(strafe_time * 1000.0)
	_next_reposition_ms = now + int(randf_range(reposition_interval.x, reposition_interval.y) * 1000.0)


# ---------- Per-tick: body, turret, cannon ----------

func _physics_process(delta: float) -> void:
	if dead:
		return
	var player := GameManager.player
	if player == null:
		return

	var target := _get_target_point(player)
	_update_body(delta, player)
	var aligned := _update_turret(delta, target)
	_update_firing(target, player, aligned)


# Body follows the movement direction, but reverses instead of turning its back on the player.
func _update_body(delta: float, player: Player) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var heading := wish_dir
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01 and heading.dot(to_player.normalized()) < -0.5:
		heading = -heading
	var target_yaw := atan2(-heading.x, -heading.z)
	body.rotation.y = _turn_toward(body.rotation.y, target_yaw, deg_to_rad(body_turn_speed) * delta)


# Turns the turret toward the target. Returns true once it's pointing close enough to fire.
func _update_turret(delta: float, target: Vector3) -> bool:
	var to_target := target - turret.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return false
	var target_yaw := atan2(-to_target.x, -to_target.z)
	turret.global_rotation.y = _turn_toward(turret.global_rotation.y, target_yaw, deg_to_rad(turret_turn_speed) * delta)
	return absf(angle_difference(turret.global_rotation.y, target_yaw)) <= deg_to_rad(aim_tolerance_deg)


func _update_firing(target: Vector3, player: Player, aligned: bool) -> void:
	var now := Time.get_ticks_msec()
	var cooldown_up := _winding_up or now >= _next_shot_ms
	var can_fire := cooldown_up and aligned \
			and global_position.distance_to(player.global_position) <= max_fire_range \
			and _has_clear_shot(turret.global_position, muzzle.global_position) \
			and _has_clear_shot(muzzle.global_position, target)

	if _winding_up:
		if not can_fire:
			_winding_up = false   # lost the shot (player ducked behind cover): cancel
		elif now >= _fire_at_ms:
			_fire(target)
			_winding_up = false
			_next_shot_ms = now + int(fire_interval * 1000.0)
		return

	if can_fire:
		_winding_up = true
		_fire_at_ms = now + int(windup_time * 1000.0)
		_play_one_shot(charge_sound)


func _fire(target: Vector3) -> void:
	if projectile_scene == null:
		push_warning("%s: no projectile_scene assigned" % name)
		return
	var proj := projectile_scene.instantiate() as EnemyProjectile
	proj.speed = shell_speed
	proj.damage = shell_damage
	get_tree().root.add_child(proj)
	proj.global_position = muzzle.global_position

	var dir := target - muzzle.global_position
	if dir.length_squared() > 0.01:
		# Avoid look_at errors when aiming straight up or down.
		var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
		proj.look_at(target, up, true)   # true = the shell's +Z points at the target
	proj.reset_physics_interpolation()
	_play_one_shot(shot_sound)


# ---------- Helpers ----------

# Where to aim: the player's position, nudged ahead along their horizontal velocity.
func _get_target_point(player: Player) -> Vector3:
	var point := player.global_position
	if lead_strength > 0.0 and shell_speed > 0.0:
		var flat_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var flight_time := global_position.distance_to(point) / shell_speed
		point += flat_velocity * flight_time * lead_strength
	return point


func _has_clear_shot(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider is Player


# Turns an angle toward a target by at most `step` radians, taking the short way around.
func _turn_toward(from: float, to: float, step: float) -> float:
	return from + clampf(angle_difference(from, to), -step, step)


func _play_one_shot(stream: AudioStream) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.bus = ENEMY_SFX_BUS
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


# The tank shells the player from range; it shouldn't also ram them.
func try_contact_attack(_hit_player: Player) -> void:
	pass
