extends FloorPickup
class_name Gun

const MIN_ATTACK_SPEED := 0.01
const MIN_RELOAD_SPEED := 0.01
## Audio bus every player gun sound plays through (its limiter is the volume ceiling).
const GUN_BUS := &"PlayerGuns"
## Most gun shot sounds allowed to play at once, across all guns.
const MAX_SHOT_VOICES := 34
static var _active_shot_voices := 0

## Name shown on shop cards and in the Tab menu. Empty = the scene's root node name.
@export var display_name := ""
## Optional small picture for the Tab menu. Empty = a rendered preview of the model.
@export var icon : Texture2D

@export_group("Rolls")
## Which stats this gun may roll when it comes from a gun store or gun box.
## How much each one rolls is set globally in Items/weapon_roll_table.tres.
## AoE Size, AoE Damage and Knockback are skipped automatically on guns without an explosion.
@export_flags("Damage", "Attack Speed", "Reload Speed", "Projectile Count", "Projectile Speed",
		"Accuracy", "Magazine Size", "AoE Size", "AoE Damage", "Knockback",
		"Ricochet Chance", "Ricochet Bounces") var rollable_stats := 4095

@export_group("Projectile")
@export var projectile : PackedScene
@export var projectile_count : int = 1
@export var cone_size : float = 0.05
## Flat speed of this gun's projectiles, in meters per second.
@export var projectile_speed : float = 100.0
## Optional: changes the speed over the projectile's flight, for special firing types
## (e.g. starts slow then accelerates). Y = multiplier on Projectile Speed, X = 0 to 1
## across Speed Curve Time. Leave empty for a flat speed.
@export var speed_curve : Curve
## Seconds the Speed Curve takes to play out. After that it holds its last value.
@export var speed_curve_time : float = 1.0
## How much of the player's movement a projectile keeps when fired (0 = none, 1 = all).
## Forward movement is added to its speed, so you can't outrun your own shots.
## Sideways movement makes it leave the barrel moving with you, then settle back onto
## the aim line, so it still lands where you aimed.
@export_range(0.0, 1.0, 0.05) var inherit_velocity := 1.0
## Seconds for that sideways movement to fade out. Short = snaps onto the aim line quickly,
## long = sweeps wider before settling.
@export_range(0.02, 1.0, 0.01) var strafe_settle_time := 0.15
## Scales the chance of on-hit item effects for this gun's hits (1.0 = full chance).
## Lower it on fast, spammy guns so they don't trigger items constantly.
@export_range(0.0, 2.0, 0.05) var proc_coefficient := 1.0
## Hits after a ricochet use proc_coefficient times this (0.5 = half the chance).
@export_range(0.0, 1.0, 0.05) var ricochet_proc_multiplier := 0.5
@export var pierce_count : int = 0
@export var damage : float = 0
@export var aiming : bool = true

@export_group("Explosion")
## Every projectile this gun fires explodes on impact (enemies AND walls/floor).
## What the blast looks like is set on the projectile scene.
@export var explosion_enabled := false
## Base damage to every enemy in the blast. Scaled by the player's damage stat and can crit.
## Stacks with the direct hit, so the enemy that was hit takes both.
@export var explosion_damage := 20.0
## Base blast radius in meters. The projectile's explosion visual is scaled to match.
@export var explosion_radius := 3.0
## Horizontal push (m/s) on enemies at the center of the blast; half that at the edge. 0 = none.
@export var explosion_knockback := 0.0
## Upward pop (m/s) at the center of the blast. 0 = none.
@export var explosion_knockback_up := 0.0
## Proc coefficient for each enemy caught in the blast (each one rolls on-hit effects separately).
@export_range(0.0, 2.0, 0.05) var explosion_proc_coefficient := 1.0

@export_group("Firing")
## Seconds between shots when the player's attack speed is 1.0.
@export var fire_rate : float = 0.05
@export var magSize : int = 1
## Seconds a full reload takes at 100% reload speed. The reload animation is stretched or
## squeezed to fit, and the mag refills when it ends. The player's reload_speed stat divides
## this (2.0 = twice as fast).
@export var reload_time : float = 1.0

@export_group("Effects")
@export var muzzle_flash : PackedScene
@export var gunSounds : Array[AudioStream]
@export var reloadSound : AudioStream
## Volume offset for shots and reloads, in dB. Negative = quieter.
## All player gun sounds also go through the "PlayerGuns" audio bus, whose limiter caps
## how loud they can get together (edit it in the Audio panel at the bottom of the editor).
@export var shot_volume_db := -20
@export var reload_volume_db := 0.0

@export_group("World Pickup")
## Gap between the floor and the BOTTOM of the model while it lies on the ground.
@export var float_height := 0.8
@export var bob_height := 0.12
@export var bob_speed := 2.0
@export var spin_speed := 1.0         # radians per second, 0 to disable

@onready var shotsLeft : int = get_mag_size()
@onready var true_cone : float = cone_size / 100

@onready var model_anchor : Node3D = $ModelAnchor
@onready var muzzle : Node3D = $ModelAnchor/muzzle
@onready var area_3d : Area3D = $Area3D
@onready var animator : AnimationPlayer = $AnimationPlayer
@onready var audio_stream_player_3d : AudioStreamPlayer3D = $AudioStreamPlayer3D

var next_use : int = 0  # Time.get_ticks_msec() value when we can fire again
var reloading : bool = false
var _reload_id := 0   # bumped every reload, so stale reload timers are ignored

## This instance's rarity and rolled bonuses (null = a plain, unrolled gun).
## Set it with apply_roll(), ideally before the gun enters the tree.
var roll : GunRoll

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
	audio_stream_player_3d.bus = GUN_BUS


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


# ---------- Rolls ----------

## Gives this gun a rarity and stat bonuses. Safe before or after it enters the tree.
func apply_roll(new_roll: GunRoll) -> void:
	roll = new_roll
	if is_node_ready():
		shotsLeft = get_mag_size()


## The stats this gun can roll, as WeaponStat.Kind values.
func get_rollable_kinds() -> Array[int]:
	var kinds : Array[int] = []
	for kind in WeaponStat.COUNT:
		if rollable_stats & (1 << kind) == 0:
			continue
		if not explosion_enabled and kind in WeaponStat.NEEDS_EXPLOSION:
			continue
		kinds.append(kind)
	return kinds


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return String(name).capitalize()   # "HammerGun" -> "Hammer Gun"


func get_rarity() -> int:
	return roll.rarity if roll != null else Rarity.COMMON


# Rolled bonus for one stat, as shown (12 = +12%). 0 when unrolled.
func _bonus(kind: int) -> float:
	return roll.get_value(kind) if roll != null else 0.0


# Percent bonus as a multiplier: +25% -> 1.25.
func _bonus_mult(kind: int) -> float:
	return 1.0 + _bonus(kind) / 100.0


## Magazine size after the Magazine Size roll. Any positive roll adds at least 1 round.
func get_mag_size() -> int:
	var bonus := _bonus(WeaponStat.Kind.MAGAZINE_SIZE)
	if bonus <= 0.0:
		return magSize
	return maxi(roundi(magSize * (1.0 + bonus / 100.0)), magSize + 1)


# ---------- Player stat helpers ----------

func _get_stat(stat_name: StringName) -> float:
	return GameManager.player.stats_node.get_value(stat_name)


## Player's final attack speed, floored so it's always safe to divide by.
func get_attack_speed() -> float:
	return maxf(_get_stat(&"attack_speed") * _bonus_mult(WeaponStat.Kind.ATTACK_SPEED), MIN_ATTACK_SPEED)


## Seconds this gun's reload actually takes, after the player's reload_speed stat.
func get_reload_duration() -> float:
	var speed := _get_stat(&"reload_speed") * _bonus_mult(WeaponStat.Kind.RELOAD_SPEED)
	return maxf(reload_time, 0.0) / maxf(speed, MIN_RELOAD_SPEED)


## Damage of one projectile: this gun's base damage scaled by the player's damage stat.
## Bullets should call source.get_damage() instead of reading source.damage.
func get_damage() -> float:
	return damage * _bonus_mult(WeaponStat.Kind.DAMAGE) * _get_stat(&"damage")

## Rolls one hit's damage including crits. Returns {"damage": float, "crit": bool}.
## Crit multiplier is 1 + crit_damage, so the default 1.0 gives 2x.
func roll_damage() -> Dictionary:
	return _roll_crit(get_damage())

## Same as roll_damage, for this gun's explosion.
func roll_explosion_damage() -> Dictionary:
	return _roll_crit(explosion_damage * _bonus_mult(WeaponStat.Kind.AOE_DAMAGE) * _get_stat(&"damage"))

func _roll_crit(dmg: float) -> Dictionary:
	var is_crit := randf() < _get_stat(&"crit_chance")
	if is_crit:
		dmg *= 1.0 + _get_stat(&"crit_damage")
	return {"damage": dmg, "crit": is_crit}

## Blast radius in meters. One place to apply the future area_size player stat, e.g.:
##   return explosion_radius * _bonus_mult(...) * _get_stat(&"area_size")
func get_explosion_radius() -> float:
	return explosion_radius * _bonus_mult(WeaponStat.Kind.AOE_SIZE)

## Explosion push and pop after the Knockback roll.
func get_explosion_knockback() -> float:
	return explosion_knockback * _bonus_mult(WeaponStat.Kind.KNOCKBACK)

func get_explosion_knockback_up() -> float:
	return explosion_knockback_up * _bonus_mult(WeaponStat.Kind.KNOCKBACK)

## Base projectile speed after the Projectile Speed roll (before any speed curve).
func get_base_projectile_speed() -> float:
	return projectile_speed * _bonus_mult(WeaponStat.Kind.PROJECTILE_SPEED)

## Projectile speed (m/s) at this point in its flight. One place for a future projectile speed stat.
func get_projectile_speed(flight_time: float) -> float:
	if speed_curve == null:
		return get_base_projectile_speed()
	return get_base_projectile_speed() * speed_curve.sample(flight_time / maxf(speed_curve_time, 0.001))

## Projectiles per shot: the gun's own count (plus its Projectile Count roll) multiplied by
## the player's projectile_count stat rounded down (1.89 -> 1, 4.2 -> 4).
## The roll can be a decimal: the gun's count is a chance, rolled every shot.
##   count 1 + 0.5 = 1 projectile, 50% chance of a 2nd.  1 + 1.2 = 2, 20% chance of a 3rd.
func get_projectile_count() -> int:
	# Small epsilon so float error from stacked modifiers (e.g. 2.9999999) doesn't floor a whole number down.
	# maxi(..., 1) keeps a low stat from stopping the gun from firing at all.
	var player_count := maxi(floori(_get_stat(&"projectile_count") + 0.0001), 1)
	var gun_count := float(projectile_count) + _bonus(WeaponStat.Kind.PROJECTILE_COUNT)
	var whole := floori(gun_count + 0.0001)
	if randf() < gun_count - whole:
		whole += 1
	return maxi(whole, 1) * player_count

## Average projectiles per shot (a 0.5 Projectile Count roll counts as half a projectile).
func get_expected_projectile_count() -> float:
	var player_count := maxi(floori(_get_stat(&"projectile_count") + 0.0001), 1)
	var gun_count := maxf(float(projectile_count) + _bonus(WeaponStat.Kind.PROJECTILE_COUNT), 1.0)
	return gun_count * player_count


## This gun's damage per second right now, with everything that affects it: base damage,
## rolls, the player's damage / attack speed / projectile count / reload speed stats.
## Explosion damage counts once per projectile (as if every blast hits the target).
## include_reload: true = sustained DPS (reload time spread across the mag),
## false = DPS while actually firing. Crits are not included.
func get_dps(include_reload := true) -> float:
	var per_projectile := get_damage()
	if explosion_enabled:
		per_projectile += explosion_damage * _bonus_mult(WeaponStat.Kind.AOE_DAMAGE) * _get_stat(&"damage")
	var per_shot := per_projectile * get_expected_projectile_count()
	var shot_time := fire_rate / get_attack_speed()
	if cone_size <= 0.0:
		# Burst guns fire extra projectiles one fire_rate apart, so the shot takes that long.
		shot_time *= get_expected_projectile_count()
	shot_time = maxf(shot_time, 0.001)
	if not include_reload:
		return per_shot / shot_time
	var mag := float(get_mag_size())
	return per_shot * mag / (shot_time * mag + get_reload_duration())


## Chance (0.15 = 15%) that a bullet ricochets after its first enemy hit.
func get_ricochet_chance() -> float:
	return _get_stat(&"ricochet_chance") + _bonus(WeaponStat.Kind.RICOCHET_CHANCE) / 100.0


## How many times a ricocheting bullet can chain to another enemy.
func get_ricochet_bounces() -> int:
	var bounces := floori(_get_stat(&"ricochet_bounces") + _bonus(WeaponStat.Kind.RICOCHET_BOUNCES) + 0.0001)
	# A Ricochet Chance roll always comes with at least one bounce, or it would do nothing.
	if roll != null and roll.has(WeaponStat.Kind.RICOCHET_CHANCE):
		bounces = maxi(bounces, 1)
	return maxi(bounces, 0)

func get_cone() -> float:
	return true_cone / maxf(_get_stat(&"accuracy") * _bonus_mult(WeaponStat.Kind.ACCURACY), 0.1)

# ---------- Pickup ----------

func interact(normal : Vector3):
	super(normal)
	if _held or not _landed:
		return
	if not GameManager.player.has_free_gun_slot():
		return   # every slot is full: leave the gun on the floor

	equip()


## Puts this gun straight into the player's next gun slot (no floor pickup needed).
## The gun must already be in the tree. Used by floor pickups and the gun store.
func equip() -> void:
	_held = true
	_disable_world_pickup()
	GameManager.player.pickup_gun(self)
	model_anchor.transform = Transform3D.IDENTITY   # stop hovering, sit in the hand normally
	animator.play("RESET")
	GameManager.gun_equipped.emit(self)


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
	_reload_id += 1
	var duration := get_reload_duration()

	# Play the whole reload animation over exactly `duration` seconds.
	animator.stop()
	if animator.has_animation(&"reload") and duration > 0.0:
		var anim_length := animator.get_animation(&"reload").length
		animator.play(&"reload", -1, anim_length / duration)
	audio_stream_player_3d.stream = reloadSound
	audio_stream_player_3d.volume_db = reload_volume_db
	audio_stream_player_3d.bus = GUN_BUS
	audio_stream_player_3d.play()

	if duration <= 0.0:
		_finish_reload(_reload_id)
	else:
		get_tree().create_timer(duration, false).timeout.connect(_finish_reload.bind(_reload_id))


# Refills the mag. The id makes a timer from an older reload do nothing.
func _finish_reload(id: int) -> void:
	if id != _reload_id or not reloading:
		return
	shotsLeft = get_mag_size()
	reloading = false


# The reload animations still call this from a method track. The mag now refills on
# reload_time instead, so this does nothing (left in so those tracks don't error).
func reload() -> void:
	pass


func _play_shot_effects(attack_speed: float) -> void:
	# Third argument speeds up the shoot animation to keep pace with the fire rate.
	animator.stop()
	animator.play("shoot", -1, attack_speed)

	# One-shot audio player so rapid shots don't cut each other off. Capped, so a
	# dozen fast guns don't stack hundreds of overlapping voices.
	if gunSounds.is_empty() or _active_shot_voices >= MAX_SHOT_VOICES:
		return
	_active_shot_voices += 1
	var audio := AudioStreamPlayer3D.new()
	audio.stream = gunSounds.pick_random()
	audio.volume_db = shot_volume_db
	audio.max_db = -1
	audio.bus = GUN_BUS
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
	audio.tree_exited.connect(Gun._release_shot_voice)   # also counts voices freed with the gun


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

	_apply_player_velocity(proj)
	proj.reset_physics_interpolation()


# Gives the projectile some of the player's movement (see inherit_velocity).
#  - Forward part: added to the projectile's speed.
#  - Sideways part: the projectile starts with it and it fades out over strafe_settle_time.
#    The firing direction is nudged the other way by exactly the drift that causes,
#    so the projectile still crosses the aim point.
func _apply_player_velocity(proj: Bullet) -> void:
	var dir := proj.global_basis.z.normalized()
	var k := clampf(inherit_velocity, 0.0, 1.0)
	if k <= 0.0:
		proj.launch(dir, 0.0, Vector3.ZERO, strafe_settle_time)
		return

	var pv := GameManager.player.velocity * k
	var along := pv.dot(dir)
	var lateral := pv - dir * along
	var boost := maxf(along, 0.0)   # moving backward never makes shots slower than normal
	var speed := maxf(get_base_projectile_speed() + boost, 0.1)

	# Distance to the aim point along the shot (fallback if it's behind us or missing).
	var aim_point := GameManager.player.get_gun_aim_point(self)
	var dist := (aim_point - proj.global_position).dot(dir)
	if dist < 1.0:
		dist = 30.0
	var tau := maxf(strafe_settle_time, 0.01)
	var t := dist / speed
	# Total sideways drift by the time it reaches the aim point.
	var drift := lateral * tau * (1.0 - exp(-t / tau))
	var aimed := (dir * dist - drift).normalized()
	proj.launch(aimed, boost, lateral, tau)


func _aim_projectile(proj: Node3D) -> void:
	# The guns hang off the Head, which is drawn at the player's interpolated (slightly
	# behind) position. Spawn from the player's real physics position instead, or fast
	# movement leaves new bullets up to a tick of movement behind the barrel.
	var player := GameManager.player
	var lag: Vector3 = player.global_position - (player.head as Node3D).global_position
	proj.global_position = muzzle.global_position + lag
	proj.global_rotation = muzzle.global_rotation  # fallback

	var aim_point := player.get_gun_aim_point(self)
	var dir := aim_point - proj.global_position
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


static func _release_shot_voice() -> void:
	_active_shot_voices = maxi(_active_shot_voices - 1, 0)
