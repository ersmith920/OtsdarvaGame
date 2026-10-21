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
## 0 = takes full knockback from explosions, 1 = immune. Heavy enemies (tanks, bosses) should resist.
@export_range(0.0, 1.0) var knockback_resist := 0.0

@export_group("Attack")
@export var attack_damage : float = 10.0
@export var attack_cooldown : float = 1.0
@export var knockback_force : float = 8.0
@export var knockback_up : float = 3.0
## Extra reach beyond touching the player's edge.
@export var attack_reach := 0.3

@export_group("Spawn")
## Seconds to rise up out of the floor. 0 = appear instantly (no emerge).
@export var emerge_time := 0.8
## Seconds to stand still once fully out, before it starts moving and attacking.
@export var emerge_pause := 0.3
## Extra depth below its own height to start from, so no part pokes through at first.
@export var emerge_extra_depth := 0.1

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

@export_group("Swarm")
## Spawn as a lightweight swarm enemy (no node per enemy, drawn with GPU instancing), so
## thousands can be alive at once. Only for enemies using this plain Enemy script: enemies
## with their own script (like the tank) always spawn as normal nodes. Hand-placed enemies
## in a level stay nodes too. Turn off to force this enemy to spawn as a node.
@export var use_swarm := true
## Swarm enemies drawing shadows. Off by default: thousands of shadow casters are expensive.
@export var swarm_cast_shadows := false

const ENEMY_SFX_BUS := &"EnemySFX"
const MAX_DEATH_SOUNDS := 8
const HIT_SOUND_MIN_GAP_MS := 30
const LAYER_ENEMY := 16        # physics layer 5
const MAX_HIT_SOUNDS := 16

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

## True if the spawner rolled this enemy as an elite.
var is_elite := false
## Multiplies damage from attacks that don't go through attack_damage (e.g. the tank's shells).
var damage_multiplier := 1.0

## True while rising out of the floor and during the pause after. While spawning the enemy
## can't move, attack, be targeted or be damaged.
var spawning := false
var _spawn_t := 0.0
var _spawn_started := false
var _surface_y := 0.0
var _emerge_depth := 0.0

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
## Horizontal knockback velocity (m/s). Set through EnemyManager.knock_back, decays on its own.
var knock := Vector3.ZERO


func _ready() -> void:
	collision_mask = 0   # never moves through physics; bullets and rays still hit it
	audio_stream_player_3d.bus = ENEMY_SFX_BUS
	var mult := health_multiplier if health_multiplier >= 0.0 else GameManager.get_enemy_health_multiplier()
	maxHealth *= mult
	health = maxHealth
	if emerge_time > 0.0 or emerge_pause > 0.0:
		# No hitbox and not a lock-on target until fully spawned.
		spawning = true
		collision_layer = 0
		visible = false   # hidden until the manager moves it below the floor (avoids a 1-frame pop)
	else:
		_activate()
	EnemyManager.register(self)


## Called by EnemyManager every physics tick while spawning. Moves pos/global_position itself.
func step_spawn(delta: float) -> void:
	var first_tick := not _spawn_started
	if first_tick:
		# The spawner has placed us by now, so this is our floor position.
		_spawn_started = true
		_surface_y = pos.y
		_emerge_depth = height + emerge_extra_depth
		visible = true
	_spawn_t += delta
	if _spawn_t < emerge_time:
		var k := _spawn_t / emerge_time
		k = 1.0 - (1.0 - k) * (1.0 - k)   # ease out: fast start, settles gently at the top
		pos.y = _surface_y - _emerge_depth * (1.0 - k)
	else:
		pos.y = _surface_y
	global_position = pos
	if first_tick:
		reset_physics_interpolation()   # don't smear from the floor surface down to the start depth
	if _spawn_t >= emerge_time + emerge_pause:
		_activate()


func _activate() -> void:
	spawning = false
	visible = true
	collision_layer = LAYER_ENEMY
	add_to_group("lock_target")


func _exit_tree() -> void:
	EnemyManager.unregister(self)


## Turns this enemy into an elite. Call BEFORE add_child (the spawner does), so the
## health multiplier is folded in before _ready applies difficulty scaling.
func make_elite(size_mult: float, health_mult: float, damage_mult: float, speed_mult: float) -> void:
	if is_elite:
		return
	is_elite = true
	# Uniform scale on the root grows the model, collision shape and AimPoint together.
	scale *= size_mult
	# The manager's soft collision and ground probes don't read the node scale, so match them.
	radius *= size_mult
	height *= size_mult
	step_height *= size_mult
	max_climb_height *= size_mult
	maxHealth *= health_mult
	attack_damage *= damage_mult
	damage_multiplier *= damage_mult
	speed *= speed_mult
	climb_speed *= speed_mult


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


## Applies damage. Returns true if this hit killed the enemy.
## Use HitSystem.deal_hit() instead of calling this directly, so on-hit effects run.
func take_damage(damage: float, is_crit: bool = false) -> bool:
	if dead or spawning:
		return false
	GameManager.enemy_damaged.emit(damage, is_crit)
	health -= damage
	if health <= 0.0:
		_die()
		return true
	_flash()

	var now := Time.get_ticks_msec()
	if now - _last_hit_sound_ms >= HIT_SOUND_MIN_GAP_MS:
		_last_hit_sound_ms = now
		play_hit_sound()
	return false


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
	Coins.drop(get_aim_position(), gold_value, gold_coins)

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
