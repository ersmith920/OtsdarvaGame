# A gold coin. Bursts out of a dead enemy in an arc, lands, then hovers and bobs.
# Once the player gets within pickup_range it latches on and swirls into them like a vortex,
# moving with the player the whole way (or flies straight in, with swirl turned off).
# Coins come in three looks (small / large / huge) chosen by their value, and piles of
# landed coins merge into one when too many are lying around.
extends FloorPickup
class_name GoldPickup

# A coin looks large at this value or more, and huge at the higher one.
# Drops are also made in these denominations (see plan_drop).
const LARGE_VALUE := 20    # = 20 small coins
const HUGE_VALUE := 100
const GROUP := &"gold"

# Sound limits: a big drop can bounce 300 coins at once, so voices and rate are capped.
const MAX_BOUNCE_VOICES := 10
const BOUNCE_MIN_GAP_MS := 25
const MAX_PICKUP_VOICES := 6
const PICKUP_MIN_GAP_MS := 35

## Gold this coin is worth. Setting it also updates the coin's size.
var value := 1.0:
	set(v):
		value = v
		if _sprite != null:
			_refresh_look()

@export_group("Burst")
## Random upward speed range when the coin pops out.
@export var burst_up_speed := Vector2(5.0, 8.0)
## Random outward speed range. Distance is roughly speed x airtime (~0.6-1.0 s).
@export var burst_out_speed := Vector2(1.5, 4.0)

@export_group("Bounce")
## How much of its downward speed a coin keeps when it hits the floor (0 = no bounce).
@export_range(0.0, 0.9) var bounce_restitution := 0.45
## Sideways speed kept on each bounce.
@export_range(0.0, 1.0) var bounce_friction := 0.6
## A rebound slower than this (m/s) doesn't happen: the coin lands and starts bobbing.
@export var min_bounce_speed := 2.0
## Safety cap on bounces per coin.
@export var max_bounces := 3

@export_group("Audio")
## One is picked at random for every floor impact, including the last one.
@export var bounce_sounds : Array[AudioStream]
@export var bounce_volume_db := -6.0
## One is picked at random when the player collects a coin.
@export var pickup_sounds : Array[AudioStream]
@export var pickup_volume_db := -6.0
## Random pitch wobble so repeated sounds don't sound identical (0.08 = +/-8%).
@export_range(0.0, 0.3) var pitch_variance := 0.08

@export_group("Sprite")
## Small coin art. One is picked at random per coin. Leave empty for a generated gold disc.
@export var sprite_textures : Array[Texture2D]
## Optional separate art for large and huge coins (also random). Empty = reuse the small art, just bigger.
@export var large_textures : Array[Texture2D]
@export var huge_textures : Array[Texture2D]
## World size of a small coin's longest side, in meters.
@export var sprite_size := 0.4
## Large and huge coins are this many times bigger than a small one.
@export var large_scale := 1.6
@export var huge_scale := 2.5
## Crisp pixels instead of smoothing. Turn off for soft or glowy art.
@export var pixel_art := true
## Gap between the floor and a small coin's center (bigger coins sit proportionally higher).
@export var float_height := 0.35
@export var bob_height := 0.08
@export var bob_speed := 3.0

@export_group("Glow")
## Brightness boost. Above 1, the brightest parts of the coin bloom using the scene's Glow
## setting. No lights are added. 1 = no glow.
@export_range(1.0, 4.0, 0.05) var glow_strength := 1.5
## Color of the boost. A light gold keeps the coin warm instead of white-hot.
@export var glow_tint := Color(1.0, 0.9, 0.6)

@export_group("Swirl Collection")
## On: coins spiral into the player like a vortex. Off: the old straight-line pull below.
@export var swirl := true
## Seconds a coin takes to spiral in from the edge of the pickup range.
@export var swirl_time := 1
## Full turns around the player before the coin reaches them.
@export var swirl_turns := 1.5
## Spin direction. Every coin spins the same way, which is what makes it read as one vortex.
@export_enum("Counter-clockwise:1", "Clockwise:-1") var swirl_direction := 1
## How long the coin stays wide before collapsing inward. 1 = shrinks steadily,
## higher = traces the edge of the pickup range longer, then snaps in at the end.
@export_range(0.5, 5.0, 0.05) var swirl_tightening := 2.0
## How the spin speeds up. 1 = constant spin, higher = starts lazy and whips around at the end.
@export_range(0.5, 5.0, 0.05) var swirl_spin_up := 1.5
## Coins that were already closer than the range edge swirl for a shorter time, down to this fraction.
@export_range(0.1, 1.0, 0.05) var swirl_min_time_fraction := 0.4

@export_group("Straight Pull (swirl off)")
## Within this distance of the player's center, the coin is collected.
@export var collect_distance := 0.9
@export var pull_start_speed := 4.0
@export var pull_max_speed := 30.0     # keep above the player's top speed so it can't be outrun
@export var pull_acceleration := 60.0

@export_group("Merging")
## Merging only starts while more than this many coins exist.
@export var merge_threshold := 150
## Landed coins inside the same cell of this size (meters) fuse into one.
@export var merge_cell_size := 3.0
## How often a merge pass may run.
@export var merge_interval_ms := 500

static var _placeholder: Texture2D
static var _last_merge_ms := 0

static var _bounce_voices := 0
static var _last_bounce_sound_ms := 0
static var _pickup_voices := 0
static var _last_pickup_sound_ms := 0
static var _quad: QuadMesh
static var _materials := {}   # texture -> shared material, so coins with the same art share one

var _bounces := 0

var _sprite: MeshInstance3D
var _float_y := 0.35
var _time := 0.0
var _attracted := false
var _pull_speed := 0.0
var _merged := false   # absorbed into another coin; waiting to be freed
var _variant := 0   # this coin's random pick; stays fixed so merging doesn't change its look

# Swirl state, all relative to the player so the coin moves with them.
var _swirl_t := 0.0          # 0 -> 1 over the swirl
var _swirl_duration := 0.5
var _start_radius := 0.0
var _start_angle := 0.0
var _start_height := 0.0


func _ready() -> void:
	_variant = randi()
	add_to_group(GROUP)
	# Run after the player each physics tick, so coins use the player's position from
	# this tick rather than the last one and stay locked to them at high speed.
	process_physics_priority = 100
	if _quad == null:
		_quad = QuadMesh.new()   # 1 m x 1 m; each coin is scaled to size
	_sprite = MeshInstance3D.new()
	_sprite.mesh = _quad
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)
	_refresh_look()
	_time = randf() * TAU   # so a pile of coins doesn't bob in sync


## Picks texture, size and hover height from the coin's current value.
func _refresh_look() -> void:
	var scale_mult := 1.0
	var tex := _pick_texture(sprite_textures)
	if value >= HUGE_VALUE:
		scale_mult = huge_scale
		if not huge_textures.is_empty():
			tex = _pick_texture(huge_textures)
	elif value >= LARGE_VALUE:
		scale_mult = large_scale
		if not large_textures.is_empty():
			tex = _pick_texture(large_textures)

	var has_art := tex != null
	if not has_art:
		tex = _get_placeholder()

	_sprite.material_override = _get_material(tex, pixel_art and has_art)
	# The quad is 1 m x 1 m, so scale it to make the longest side sprite_size x the coin's scale.
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	var world_size := sprite_size * scale_mult
	_sprite.scale = Vector3(world_size * tex.get_width() / longest,
			world_size * tex.get_height() / longest, 1.0)
	_float_y = float_height * scale_mult


## Pops the coin out in a random direction. Call after it's in the tree and positioned.
func burst() -> void:
	launch_up_speed = randf_range(burst_up_speed.x, burst_up_speed.y)
	launch_toward_speed = randf_range(burst_out_speed.x, burst_out_speed.y)
	launch(Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU))


func _process(delta: float) -> void:
	_time += delta
	if _attracted and swirl:
		# No bobbing mid-swirl; the hover offset shrinks away as the coin closes in.
		_sprite.position.y = _float_y * (1.0 - _swirl_t)
	else:
		_sprite.position.y = _float_y + sin(_time * bob_speed) * bob_height


func _physics_process(delta: float) -> void:
	if _merged:
		return
	super(delta)   # FloorPickup's launch arc; does nothing once landed
	if not _landed:
		return
	var player := GameManager.player
	if player == null:
		return

	# Latches on: once pulled, it keeps coming even if the player steps away.
	if not _attracted:
		var pickup_range := player.stats_node.get_value(&"pickup_range")
		if (player.global_position - global_position).length_squared() > pickup_range * pickup_range:
			_try_merge()
			return
		_start_attraction(player, pickup_range)

	if swirl:
		_swirl_step(player, delta)
	else:
		_pull_step(player, delta)


func _start_attraction(player: Player, pickup_range: float) -> void:
	_attracted = true
	_pull_speed = pull_start_speed

	# Freeze where the coin sits relative to the player, in polar form around them.
	var offset := global_position - player.global_position
	var flat := Vector2(offset.x, offset.z)
	_start_radius = flat.length()
	_start_angle = flat.angle()
	_start_height = offset.y
	_swirl_t = 0.0
	var fraction := clampf(_start_radius / maxf(pickup_range, 0.01), swirl_min_time_fraction, 1.0)
	_swirl_duration = maxf(swirl_time * fraction, 0.01)


# Spirals in around the player. The position is rebuilt from the player's position every
# tick, so the whole vortex travels with them no matter how fast they move.
func _swirl_step(player: Player, delta: float) -> void:
	_swirl_t = minf(_swirl_t + delta / _swirl_duration, 1.0)
	if _swirl_t >= 1.0:
		_collect(player)
		return
	var shrink := 1.0 - pow(_swirl_t, swirl_tightening)
	var angle := _start_angle + float(swirl_direction) * swirl_turns * TAU * pow(_swirl_t, swirl_spin_up)
	var radius := _start_radius * shrink
	global_position = player.global_position + Vector3(cos(angle) * radius, _start_height * shrink, sin(angle) * radius)


# The original straight-line pull, used when swirl is off.
func _pull_step(player: Player, delta: float) -> void:
	var to_player := player.global_position - global_position
	_pull_speed = move_toward(_pull_speed, pull_max_speed, pull_acceleration * delta)
	var step := _pull_speed * delta
	if to_player.length_squared() <= maxf(step * step, collect_distance * collect_distance):
		_collect(player)
		return
	global_position += to_player.normalized() * step


func _collect(player: Player) -> void:
	player.add_gold(value)
	_play_pickup_sound()
	_merged = true   # stop processing until freed
	queue_free()


# Fuses landed coins that share a grid cell. Throttled, and only runs while there are too many.
func _try_merge() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_merge_ms < merge_interval_ms:
		return
	_last_merge_ms = now
	if get_tree().get_node_count_in_group(GROUP) <= merge_threshold:
		return

	var keepers := {}   # grid cell -> the coin that absorbs the rest of that cell
	for node in get_tree().get_nodes_in_group(GROUP):
		var coin := node as GoldPickup
		if coin._merged or not coin._landed or coin._attracted:
			continue
		var p := coin.global_position
		var cell := Vector3i(floori(p.x / merge_cell_size), floori(p.y / merge_cell_size),
				floori(p.z / merge_cell_size))
		var keeper: GoldPickup = keepers.get(cell)
		if keeper == null:
			keepers[cell] = coin
		else:
			keeper.value += coin.value   # setter resizes it
			coin._merged = true
			coin.queue_free()


## Splits a gold total into coin values: biggest coins first, small coins for the change.
## max_coins caps the number of pieces; over that, the smallest coins become fewer but fatter.
## A drop always keeps at least one coin of each size it contains.
static func plan_drop(total: int, max_coins: int) -> PackedFloat32Array:
	var plan := PackedFloat32Array()
	if total <= 0:
		return plan

	var huge := floori(float(total) / HUGE_VALUE)
	var rest := total - huge * HUGE_VALUE
	var large := floori(float(rest) / LARGE_VALUE)
	var small := rest - large * LARGE_VALUE

	var counts := [huge, large, small]
	var amounts := [huge * HUGE_VALUE, large * LARGE_VALUE, small]

	# Too many pieces: squash the small coins first, then large, then huge.
	var excess: int = huge + large + small - maxi(max_coins, 1)
	for i in [2, 1, 0]:
		if excess <= 0:
			break
		var cut := mini(excess, maxi(counts[i] - 1, 0))
		counts[i] -= cut
		excess -= cut

	for i in 3:
		for n in counts[i]:
			plan.append(float(amounts[i]) / counts[i])
	return plan


static func _get_placeholder() -> Texture2D:
	if _placeholder == null:
		var gradient := Gradient.new()
		gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.78])
		gradient.colors = PackedColorArray([
			Color(1.0, 0.85, 0.25),
			Color(0.8, 0.5, 0.05),
			Color(0.8, 0.5, 0.05, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_placeholder = tex
	return _placeholder

# FloorPickup calls this when the coin hits the floor. Returning true keeps it flying.
func _on_floor_impact(impact_velocity: Vector3) -> bool:
	var impact := absf(impact_velocity.y)
	_play_bounce_sound(impact)

	var rebound := impact * bounce_restitution
	if rebound < min_bounce_speed or _bounces >= max_bounces:
		return false   # too soft to bounce again: land
	_bounces += 1
	_velocity = Vector3(impact_velocity.x * bounce_friction, rebound, impact_velocity.z * bounce_friction)
	global_position += Vector3.UP * 0.02   # start just above the floor so the next ray doesn't re-hit it
	return true


func _play_bounce_sound(impact_speed: float) -> void:
	if bounce_sounds.is_empty() or _bounce_voices >= MAX_BOUNCE_VOICES:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bounce_sound_ms < BOUNCE_MIN_GAP_MS:
		return
	_last_bounce_sound_ms = now
	_bounce_voices += 1

	var audio := AudioStreamPlayer3D.new()
	audio.stream = bounce_sounds.pick_random()
	# Harder impacts are louder: full volume at 8 m/s or more, quieter for small ones.
	audio.volume_db = bounce_volume_db + linear_to_db(clampf(impact_speed / 8.0, 0.2, 1.0))
	audio.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	audio.unit_size = 20
	audio.max_distance = 40.0
	get_tree().current_scene.add_child(audio)
	audio.global_position = global_position
	audio.play()
	audio.finished.connect(GoldPickup._release_bounce_voice.bind(audio))


static func _release_bounce_voice(audio: AudioStreamPlayer3D) -> void:
	_bounce_voices -= 1
	audio.queue_free()


# Not positional: the player hears their own pickups at the same level wherever they are.
# Added to the scene (not the coin), since the coin is freed right after.
func _play_pickup_sound() -> void:
	if pickup_sounds.is_empty() or _pickup_voices >= MAX_PICKUP_VOICES:
		return
	var now := Time.get_ticks_msec()
	if now - _last_pickup_sound_ms < PICKUP_MIN_GAP_MS:
		return
	_last_pickup_sound_ms = now
	_pickup_voices += 1

	var audio := AudioStreamPlayer.new()
	audio.stream = pickup_sounds.pick_random()
	audio.volume_db = pickup_volume_db
	audio.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	get_tree().current_scene.add_child(audio)
	audio.play()
	audio.finished.connect(GoldPickup._release_pickup_voice.bind(audio))

func _pick_texture(list : Array[Texture2D]) -> Texture2D:
	for i in list.size():   # skips any empty slots in the array
		var tex := list[(_variant + i) % list.size()]
		if tex != null:
			return tex
	return null


static func _release_pickup_voice(audio: AudioStreamPlayer) -> void:
	_pickup_voices -= 1
	audio.queue_free()

func _get_material(tex : Texture2D, crisp : bool) -> StandardMaterial3D:
	var mat : StandardMaterial3D = _materials.get(tex)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true   # so the node's scale still sizes the coin
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if crisp \
				else BaseMaterial3D.TEXTURE_FILTER_LINEAR
		if glow_strength > 1.0:
			var boosted := glow_tint * glow_strength
			mat.albedo_color = Color(boosted.r, boosted.g, boosted.b, 1.0)   # above 1 = blooms
		_materials[tex] = mat
	return mat
