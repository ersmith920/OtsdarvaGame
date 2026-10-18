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

@export_group("Audio")
## Volume offset for this enemy's hit sounds, in dB. Negative = quieter.
@export var hit_volume_db := 0.0

const ENEMY_SFX_BUS := &"EnemySFX"
const MAX_DEATH_SOUNDS := 8
const HIT_SOUND_MIN_GAP_MS := 30
const LAYER_ENEMY := 16        # physics layer 5
const MAX_HIT_SOUNDS := 16

static var _active_death_sounds := 0
static var _last_hit_sound_ms := 0
static var _active_hit_sounds := 0

var dead := false
var _next_attack_ms : int = 0

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
	maxHealth *= GameManager.get_enemy_health_multiplier()
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
