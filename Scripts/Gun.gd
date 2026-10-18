extends FloorPickup
class_name Gun

const MIN_ATTACK_SPEED := 0.01

@export_group("Projectile")
@export var projectile : PackedScene
@export var projectile_count : int = 1
@export var cone_size : float = 0.05
@export var projectile_speed : Curve
@export var pierce_count : int = 0
@export var damage : float = 0
@export var aiming : bool = true

@export_group("Firing")
## Seconds between shots when the player's attack speed is 1.0.
@export var fire_rate : float = 0.05
@export var magSize : int = 1

@export_group("Effects")
@export var muzzle_flash : PackedScene
@export var gunSounds : Array[AudioStream]
@export var reloadSound : AudioStream
## Volume offset for shots and reloads, in dB. Negative = quieter.
@export var shot_volume_db := -20
@export var reload_volume_db := 0.0

@export_group("World Pickup")
## Gap between the floor and the BOTTOM of the model while it lies on the ground.
@export var float_height := 0.8
@export var bob_height := 0.12
@export var bob_speed := 2.0
@export var spin_speed := 1.0         # radians per second, 0 to disable

@onready var shotsLeft : int = magSize
@onready var true_cone : float = cone_size / 100

@onready var model_anchor : Node3D = $ModelAnchor
@onready var muzzle : Node3D = $ModelAnchor/muzzle
@onready var area_3d : Area3D = $Area3D
@onready var animator : AnimationPlayer = $AnimationPlayer
@onready var audio_stream_player_3d : AudioStreamPlayer3D = $AudioStreamPlayer3D

var next_use : int = 0  # Time.get_ticks_msec() value when we can fire again
var reloading : bool = false

var _held := false
var _time := 0.0
var _spin := 0.0
var _model_center := Vector3.ZERO   # center of the model's bounds, in ModelAnchor space
var _half_height := 0.0


func _ready() -> void:
	var bounds := _get_model_bounds()
	_model_center = bounds.get_center()
	_half_height = bounds.size.y * 0.5
	_time = randf() * TAU   # so a group of guns doesn't bob in sync
	animator.animation_finished.connect(_on_animation_finished)


# ---------- World hover (only while lying on the floor) ----------

# Spins around the model's own center and bobs, so it never clips the ground
# no matter where the model was exported from. The model itself is never moved,
# so the shoot/reload animations are unaffected.
func _process(delta: float) -> void:
	if _held:
		return
	_time += delta
	_spin += spin_speed * delta
	var rot := Basis(Vector3.UP, _spin)
	var pivot_y := float_height + _half_height + sin(_time * bob_speed) * bob_height
	model_anchor.transform = Transform3D(rot, Vector3(0.0, pivot_y, 0.0) - rot * _model_center)


# Bounding box of every mesh under ModelAnchor, measured in ModelAnchor space.
func _get_model_bounds() -> AABB:
	var to_anchor := model_anchor.global_transform.affine_inverse()
	var bounds := AABB()
	var found := false
	for node in model_anchor.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var box: AABB = to_anchor * geo.global_transform * geo.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds if found else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


# ---------- Player stat helpers ----------

func _get_stat(stat_name: StringName) -> float:
	return GameManager.player.stats_node.get_value(stat_name)


## Player's final attack speed, floored so it's always safe to divide by.
func get_attack_speed() -> float:
	return maxf(_get_stat(&"attack_speed"), MIN_ATTACK_SPEED)


## Damage of one projectile: this gun's base damage scaled by the player's damage stat.
## Bullets should call source.get_damage() instead of reading source.damage.
func get_damage() -> float:
	return damage * _get_stat(&"damage")

## Rolls one hit's damage including crits. Returns {"damage": float, "crit": bool}.
## Crit multiplier is 1 + crit_damage, so the default 1.0 gives 2x.
func roll_damage() -> Dictionary:
	var dmg := get_damage()
	var is_crit := randf() < _get_stat(&"crit_chance")
	if is_crit:
		dmg *= 1.0 + _get_stat(&"crit_damage")
	return {"damage": dmg, "crit": is_crit}

## Projectiles per shot: the gun's own count multiplied by the player's
## projectile_count stat rounded down (1.89 -> 1, 4.2 -> 4).
func get_projectile_count() -> int:
	# Small epsilon so float error from stacked modifiers (e.g. 2.9999999) doesn't floor a whole number down.
	# maxi(..., 1) keeps a low stat from stopping the gun from firing at all.
	var player_count := maxi(floori(_get_stat(&"projectile_count") + 0.0001), 1)
	return projectile_count * player_count

## Chance (0.15 = 15%) that a bullet ricochets after its first enemy hit.
func get_ricochet_chance() -> float:
	return _get_stat(&"ricochet_chance")


## How many times a ricocheting bullet can chain to another enemy.
func get_ricochet_bounces() -> int:
	return maxi(floori(_get_stat(&"ricochet_bounces") + 0.0001), 0)

func get_cone() -> float:
	return true_cone / maxf(_get_stat(&"accuracy"), 0.1)

# ---------- Pickup ----------

func interact(normal : Vector3):
	super(normal)
	if _held or not _landed:
		return
	if not GameManager.player.has_free_gun_slot():
		return   # every slot is full: leave the gun on the floor

	_held = true
	_disable_world_pickup()
	GameManager.player.pickup_gun(self)
	model_anchor.transform = Transform3D.IDENTITY   # stop hovering, sit in the hand normally
	animator.play("RESET")


# Turns off the pickup area once the gun is held.
func _disable_world_pickup() -> void:
	(area_3d.get_child(0) as CollisionShape3D).disabled = true
	area_3d.visible = false
	area_3d.process_mode = Node.PROCESS_MODE_DISABLED
# ---------- Shooting ----------

func shoot() -> void:
	if Time.get_ticks_msec() < next_use:
		return
	if shotsLeft <= 0:
		# If the last shot's animation is still playing, let it finish first;
		# the handler above starts the reload when it's done.
		if animator.current_animation != "shoot":
			_start_reload()
		return

	var attack_speed := get_attack_speed()
	shotsLeft -= 1
	# Higher attack speed = shorter delay before the next shot.
	next_use = Time.get_ticks_msec() + int(fire_rate / attack_speed * 1000.0)

	_play_shot_effects(attack_speed)
	_fire_projectiles(attack_speed)


func _start_reload() -> void:
	if reloading:
		return
	reloading = true
	animator.stop()
	animator.play("reload")
	audio_stream_player_3d.stream = reloadSound
	audio_stream_player_3d.volume_db = reload_volume_db
	audio_stream_player_3d.play()


# Called by the reload animation (or anything else) when the reload finishes.
func reload() -> void:
	shotsLeft = magSize
	reloading = false


func _play_shot_effects(attack_speed: float) -> void:
	# Third argument speeds up the shoot animation to keep pace with the fire rate.
	animator.stop()
	animator.play("shoot", -1, attack_speed)

	# One-shot audio player so rapid shots don't cut each other off.
	var audio := AudioStreamPlayer3D.new()
	audio.stream = gunSounds.pick_random()
	audio.volume_db = shot_volume_db
	audio.max_db = -1
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


func _fire_projectiles(attack_speed: float) -> void:
	var total := get_projectile_count()
	# With no cone, extra projectiles fire as a staggered burst instead of all at once.
	var is_burst := cone_size <= 0.0
	for i in total:
		_spawn_projectile()
		if is_burst and i < total - 1:
			await get_tree().create_timer(fire_rate / attack_speed).timeout
			if not is_inside_tree():
				return  # gun was freed mid-burst

func _spawn_projectile() -> void:
	var proj : Bullet = projectile.instantiate()
	proj.source = self
	get_tree().root.add_child(proj)
	_aim_projectile(proj)

	# Fire in a cone: nudge the rotation in a random direction by a random amount.
	if cone_size > 0.0:
		var angle := randf_range(0.0, TAU)
		var offset := Vector3(cos(angle), sin(angle), 0.0)
		proj.global_rotation += offset * randf_range(0.0, get_cone())

	proj.reset_physics_interpolation()

func _aim_projectile(proj: Node3D) -> void:
	proj.global_position = muzzle.global_position
	proj.global_rotation = muzzle.global_rotation  # fallback

	var aim_point := GameManager.player.lock_on.get_aim_point()
	var dir := aim_point - muzzle.global_position
	if dir.length_squared() < 0.01:
		return
	# Avoid look_at errors when aiming straight up or down.
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	proj.look_at(aim_point, up, true)

# Auto-reload: once the shoot animation of the last bullet has played out.
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"shoot" and shotsLeft <= 0:
		_start_reload()

func can_be_cleared() -> bool:
	return not _held
