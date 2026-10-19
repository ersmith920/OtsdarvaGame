extends CharacterBody3D
class_name Enemy

@export var maxHealth : float = 100.0
@export var hitSounds : Array[AudioStream]
@export var deathSounds : Array[AudioStream]
@onready var health = maxHealth
@onready var audio_stream_player_3d: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var _aim_node := get_node_or_null("AimPoint") as Node3D

@export_group("Movement")
@export var speed := 5.0
## Soft-collision circle (horizontal) and body height, for separation and stacking.
@export var radius := 0.9
@export var height := 1.6
## Ledges up to this tall are stepped onto; anything taller counts as a wall.
@export var step_height := 1.0
## Climbers rise along walls and step onto enemies at their height or higher.
@export var can_climb := false
@export var climb_speed := 6.0
## Safety cap: a climber won't step onto an enemy whose top is higher than this above the ground.
@export var max_climb_height := 6.0
## If true, the manager rotates this whole enemy to face its movement direction.
## Turn off for enemies that handle their own facing (like the tank).
@export var face_move_direction := true

@export_group("Attack")
@export var attack_damage : float = 10.0
@export var attack_cooldown : float = 1.0
@export var knockback_force : float = 8.0
@export var knockback_up : float = 3.0
## Extra reach beyond touching the player's edge.
@export var attack_reach := 0.3

@export_group("Hit Flash")
## How long the red flash lasts, in seconds. 0 turns it off for this enemy.
@export var flash_time := 0.08

@export_group("Drops")
## Set by the spawner from the enemy's tier. Hand-placed enemies use whatever is set here.
@export var gold_value := 0
## The most pieces a drop can break into. Bigger drops use bigger coins; past this
## limit the small coins get fatter instead of more numerous.
@export var gold_coins := 6

@export_group("Audio")
## Volume offset for this enemy's hit sounds, in dB. Negative = quieter.
@export var hit_volume_db := 0.0

const ENEMY_SFX_BUS := &"EnemySFX"
const MAX_DEATH_SOUNDS := 8
const HIT_SOUND_MIN_GAP_MS := 30
const LAYER_ENEMY := 16        # physics layer 5
const MAX_HIT_SOUNDS := 16
const GOLD_SCENE := preload("res://gold_pickup.tscn")

const FLASH_COLOR := Color(1.0, 0.1, 0.1, 0.25)   # alpha = how strong the red is

static var _flash_material: StandardMaterial3D

var _meshes : Array[MeshInstance3D] = []
var _meshes_found := false
var _flashing := false
var _flash_until_ms := 0

static var _active_death_sounds := 0
static var _last_hit_sound_ms := 0
static var _active_hit_sounds := 0

var dead := false
var _next_attack_ms : int = 0

## Set by the spawner from the enemy's SpawnTier before it enters the tree.
## Below 0 means hand-placed: GameManager's global health scaling is used instead.
var health_multiplier := -1.0

# Owned by EnemyManager.
var pos := Vector3.ZERO
var wish_dir := Vector3.ZERO
var vy := 0.0
var ground_y := -INF
var support_y := -INF
var wall_normal := Vector3.ZERO
var climbing := false
var fresh := true
var mgr_index := -1


func _ready() -> void:
	collision_layer = LAYER_ENEMY
	collision_mask = 0   # never moves through physics; bullets and rays still hit it
	audio_stream_player_3d.bus = ENEMY_SFX_BUS
	add_to_group("lock_target")
	var mult := health_multiplier if health_multiplier >= 0.0 else GameManager.get_enemy_health_multiplier()
	maxHealth *= mult
	health = maxHealth
	EnemyManager.register(self)


func _exit_tree() -> void:
	EnemyManager.unregister(self)


## Behavior hook, called a few times per second by the manager.
## to_player is horizontal. Return the direction to move (ZERO = stand still).
func compute_wish_dir(to_player: Vector3, dist: float) -> Vector3:
	return to_player / dist if dist > 0.01 else Vector3.ZERO


func play_death_sound():
	if not is_inside_tree() or _active_death_sounds >= MAX_DEATH_SOUNDS:
		return
	_active_death_sounds += 1

	var audio := AudioStreamPlayer3D.new()
	audio.stream = deathSounds.pick_random()
	audio.bus = ENEMY_SFX_BUS
	get_tree().current_scene.add_child(audio)
	audio.global_transform.origin = global_transform.origin
	audio.play()
	audio.finished.connect(Enemy._release_death_sound.bind(audio))


static func _release_death_sound(audio: AudioStreamPlayer3D) -> void:
	_active_death_sounds -= 1
	audio.queue_free()

func play_hit_sound() -> void:
	if not is_inside_tree() or hitSounds.is_empty() or _active_hit_sounds >= MAX_HIT_SOUNDS:
		return
	_active_hit_sounds += 1

	var audio := AudioStreamPlayer3D.new()
	audio.stream = hitSounds.pick_random()
	audio.max_db = -5.0
	audio.volume_db = hit_volume_db
	audio.bus = ENEMY_SFX_BUS
	get_tree().current_scene.add_child(audio)
	audio.global_position = get_aim_position()
	audio.play()
	audio.finished.connect(Enemy._release_hit_sound.bind(audio))


static func _release_hit_sound(audio: AudioStreamPlayer3D) -> void:
	_active_hit_sounds -= 1
	audio.queue_free()


func take_damage(damage: float, is_crit: bool = false) -> void:
	if dead:
		return
	GameManager.enemy_damaged.emit(damage, is_crit)
	health -= damage
	if health <= 0.0:
		_die()
		return
	_flash()

	var now := Time.get_ticks_msec()
	if now - _last_hit_sound_ms >= HIT_SOUND_MIN_GAP_MS:
		_last_hit_sound_ms = now
		play_hit_sound()


func _die() -> void:
	dead = true
	remove_from_group("lock_target")
	collision_layer = 0
	EnemyManager.unregister(self)
	play_death_sound()
	_drop_gold()
	queue_free()


## Called by the manager if the enemy falls out of the world.
func fall_out() -> void:
	dead = true
	remove_from_group("lock_target")
	collision_layer = 0
	queue_free()


func try_contact_attack(hit_player: Player) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_attack_ms:
		return
	_next_attack_ms = now + int(attack_cooldown * 1000.0)
	var push := hit_player.global_position - global_position
	hit_player.take_damage(attack_damage)
	hit_player.apply_knockback(push, knockback_force, knockback_up)


func get_aim_position() -> Vector3:
	return _aim_node.global_position if _aim_node != null else global_position

func _drop_gold() -> void:
	if gold_value <= 0 or gold_coins <= 0:
		return
	var origin := get_aim_position()
	var each := float(gold_value) / gold_coins
	var parent := get_tree().current_scene
	for i in gold_coins:
		var coin: GoldPickup = GOLD_SCENE.instantiate()
		coin.value = each
		parent.add_child(coin)
		coin.global_position = origin
		coin.burst()
		coin.reset_physics_interpolation()

func _flash() -> void:
	if flash_time <= 0.0:
		return
	if not _meshes_found:
		_find_meshes()
	_flash_until_ms = Time.get_ticks_msec() + int(flash_time * 1000.0)
	if _flashing:
		return   # already red: the running timer will see the new deadline and extend itself
	_flashing = true
	var mat := _get_flash_material()
	for mesh in _meshes:
		mesh.material_overlay = mat
	get_tree().create_timer(flash_time).timeout.connect(_end_flash)


func _end_flash() -> void:
	var remaining := _flash_until_ms - Time.get_ticks_msec()
	if remaining > 0:   # hit again during the flash: keep it going
		get_tree().create_timer(remaining / 1000.0).timeout.connect(_end_flash)
		return
	_flashing = false
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


# Looked up once, the first time this enemy is hit.
func _find_meshes() -> void:
	_meshes_found = true
	for node in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)


# One shared material for every enemy, so flashing never allocates anything.
static func _get_flash_material() -> StandardMaterial3D:
	if _flash_material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = FLASH_COLOR
		_flash_material = mat
	return _flash_material
