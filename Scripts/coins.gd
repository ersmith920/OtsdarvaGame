# Autoload "Coins": every gold coin on the map, for huge enemy counts.
#
# Like the swarm, a coin here is NOT a node: it's one entry in the native GoldCore's arrays,
# drawn as one instance of a MultiMesh (one draw per coin texture, not per coin). The core
# runs the same flight, bounces, hover, swirl collection and merging as the GoldPickup node
# coin, so they look and feel the same.
#
# All the coin settings (art, sizes, bounce, swirl, merging, sounds, glow) are still edited
# on gold_pickup.tscn: they're read from there when a level starts.
#
# If the native library isn't loaded, drop() spawns GoldPickup nodes instead (the old way).
#
#   Coins.drop(origin, gold_value, coin_count)
extends Node

const GOLD_SCENE := preload("res://gold_pickup.tscn")

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_prepass_alpha, cull_back;
uniform sampler2D tex : source_color, FILTER;
uniform vec4 tint = vec4(1.0);
uniform float bob_time = 0.0;
uniform float bob_speed = 3.0;
uniform float bob_height = 0.08;
void vertex() {
	// Hover bob (custom.r = the coin's random phase, custom.g = 1 when bobbing).
	vec3 origin = MODEL_MATRIX[3].xyz;
	origin.y += sin(bob_time * bob_speed + INSTANCE_CUSTOM.r) * bob_height * INSTANCE_CUSTOM.g;
	// Billboard that keeps the instance's scale (same as the node coin's material).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(origin, 1.0));
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = tint.rgb * c.rgb;
	ALPHA = tint.a * c.a;
}
"""

## True when the fast C++ core is running.
var native := false
## Milliseconds the last coin tick took inside the core (for profiling).
var last_tick_ms := 0.0

var _core : Object   # GoldCore
var _settings : GoldPickup   # the gold_pickup.tscn instance the settings are read from
var _scene : Node
var _types : Array[Dictionary] = []   # {mm: MultiMesh, node: MultiMeshInstance3D, mat: ShaderMaterial, cap: int}
var _bob_time := 0.0

var _bounce_voices := 0
var _last_bounce_ms := 0
var _pickup_voices := 0
var _last_pickup_ms := 0


func _ready() -> void:
	# Run after the player each physics tick (like the node coins), so swirling coins use
	# the player's position from this tick and stay locked to them at high speed.
	process_physics_priority = 100
	native = ClassDB.class_exists(&"GoldCore")


## Drops `count` coins worth `value` gold in total, bursting out from `origin`.
func drop(origin: Vector3, value: float, count: int) -> void:
	if value <= 0.0 or count <= 0:
		return
	if not native:
		_drop_nodes(origin, value, count)
		return
	if _core == null or _scene != get_tree().current_scene:
		_setup()
	_core.drop(origin, value, count)


## Coins currently on the map.
func count() -> int:
	return _core.count() if _core != null else get_tree().get_node_count_in_group(GoldPickup.GROUP)


## Removes every coin (no gold given).
func clear() -> void:
	if _core != null:
		_core.clear()
		_upload(true)
	for node in get_tree().get_nodes_in_group(GoldPickup.GROUP):
		node.queue_free()


func _physics_process(delta: float) -> void:
	if _core == null:
		return
	if not is_instance_valid(_scene) or _scene != get_tree().current_scene:
		_teardown()
		return

	var player := GameManager.player
	var has_player := player != null and is_instance_valid(player)
	var player_pos := player.global_position if has_player else Vector3.ZERO
	var pickup_range := player.stats_node.get_value(&"pickup_range") if has_player else 0.0
	var exclude : Array[RID] = []
	if has_player:
		exclude.append(player.get_rid())
	_core.set_world(get_viewport().world_3d.direct_space_state, exclude)

	var events : PackedFloat32Array = _core.step(delta, player_pos, pickup_range, has_player, Time.get_ticks_msec())
	last_tick_ms = _core.get_last_step_ms()
	if has_player and events[1] > 0.0:
		player.add_gold(_core.get_last_gold())
		_play_pickup_sound()
	var i := 2
	while i + 3 < events.size():
		_play_bounce_sound(Vector3(events[i], events[i + 1], events[i + 2]), events[i + 3])
		i += 4
	_upload(false)


func _process(delta: float) -> void:
	if _core == null:
		return
	_bob_time += delta
	for t in _types:
		(t.mat as ShaderMaterial).set_shader_parameter(&"bob_time", _bob_time)


# Hands the core's buffers to the MultiMeshes (only the ones that changed).
func _upload(force: bool) -> void:
	for idx in _types.size():
		var t : Dictionary = _types[idx]
		var mm : MultiMesh = t.mm
		var cap : int = _core.get_instance_capacity(idx)
		var grew : bool = cap != t.cap
		if grew:
			mm.instance_count = cap
			t.cap = cap
		if cap == 0 or not (force or grew or _core.needs_upload(idx)):
			continue
		mm.visible_instance_count = _core.get_visible_count(idx)
		mm.set_buffer_interpolated(_core.get_buffer(idx), _core.get_prev_buffer(idx))


# ======================================================================
# Setup
# ======================================================================

func _setup() -> void:
	_teardown()
	_scene = get_tree().current_scene
	_settings = GOLD_SCENE.instantiate() as GoldPickup   # not added to the tree: just read
	var s := _settings
	_core = ClassDB.instantiate(&"GoldCore")
	_core.set_settings({
		"large_value": GoldPickup.LARGE_VALUE,
		"huge_value": GoldPickup.HUGE_VALUE,
		"burst_up_min": s.burst_up_speed.x, "burst_up_max": s.burst_up_speed.y,
		"burst_out_min": s.burst_out_speed.x, "burst_out_max": s.burst_out_speed.y,
		"gravity": s.launch_gravity,
		"min_floor_normal_y": s.min_floor_normal_y,
		"restitution": s.bounce_restitution,
		"friction": s.bounce_friction,
		"min_bounce_speed": s.min_bounce_speed,
		"max_bounces": s.max_bounces,
		"swirl": s.swirl,
		"swirl_time": float(s.swirl_time),
		"swirl_turns": s.swirl_turns,
		"swirl_direction": float(s.swirl_direction),
		"swirl_tightening": s.swirl_tightening,
		"swirl_spin_up": s.swirl_spin_up,
		"swirl_min_time_fraction": s.swirl_min_time_fraction,
		"collect_distance": s.collect_distance,
		"pull_start_speed": s.pull_start_speed,
		"pull_max_speed": s.pull_max_speed,
		"pull_acceleration": s.pull_acceleration,
		"merge_threshold": s.merge_threshold,
		"merge_cell_size": s.merge_cell_size,
		"merge_interval_ms": s.merge_interval_ms,
	})

	# One look per texture choice at each size, picked the same way as GoldPickup._refresh_look.
	var type_of := {}   # [texture, crisp] key -> type index
	var small := _looks_for(s.sprite_textures, s.sprite_textures, 1.0, type_of)
	var large := _looks_for(s.large_textures, s.sprite_textures, s.large_scale, type_of)
	var huge := _looks_for(s.huge_textures, s.sprite_textures, s.huge_scale, type_of)
	_core.set_looks(small, large, huge)


# own: this size's art list. fallback: the small art (used, bigger, when own is empty).
func _looks_for(own: Array[Texture2D], fallback: Array[Texture2D], scale_mult: float, type_of: Dictionary) -> PackedFloat32Array:
	var list := own if not own.is_empty() else fallback
	var out := PackedFloat32Array()
	var n := maxi(list.size(), 1)
	for j in n:
		var tex : Texture2D = null
		for k in list.size():   # skips empty slots, like GoldPickup._pick_texture
			tex = list[(j + k) % list.size()]
			if tex != null:
				break
		var has_art := tex != null
		if not has_art:
			tex = GoldPickup._get_placeholder()
		var crisp := _settings.pixel_art and has_art
		var key := [tex, crisp]
		if not type_of.has(key):
			type_of[key] = _add_type(tex, crisp)
		var longest := float(maxi(tex.get_width(), tex.get_height()))
		var world_size := _settings.sprite_size * scale_mult
		out.append(float(type_of[key]))
		out.append(world_size * tex.get_width() / longest)
		out.append(world_size * tex.get_height() / longest)
		out.append(_settings.float_height * scale_mult)
	return out


func _add_type(tex: Texture2D, crisp: bool) -> int:
	var idx : int = _core.add_type()
	var shader := Shader.new()
	shader.code = SHADER.replace("FILTER", "filter_nearest" if crisp else "filter_linear")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"tex", tex)
	var tint := Color.WHITE
	if _settings.glow_strength > 1.0:
		var boosted := _settings.glow_tint * _settings.glow_strength
		tint = Color(boosted.r, boosted.g, boosted.b, 1.0)   # above 1 = blooms
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"bob_speed", _settings.bob_speed)
	mat.set_shader_parameter(&"bob_height", _settings.bob_height)

	var quad := QuadMesh.new()   # 1 m x 1 m; each instance is scaled to size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))   # never culled
	add_child(node)
	_types.append({"mm": mm, "node": node, "mat": mat, "cap": 0})
	return idx


func _teardown() -> void:
	for t in _types:
		(t.node as Node).queue_free()
	_types.clear()
	if _settings != null:
		_settings.free()
		_settings = null
	_core = null
	_scene = null


# ======================================================================
# Sounds (same limits as the node coins)
# ======================================================================

func _play_bounce_sound(at: Vector3, impact_speed: float) -> void:
	var s := _settings
	if s.bounce_sounds.is_empty() or _bounce_voices >= GoldPickup.MAX_BOUNCE_VOICES:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bounce_ms < GoldPickup.BOUNCE_MIN_GAP_MS:
		return
	_last_bounce_ms = now
	_bounce_voices += 1
	var audio := AudioStreamPlayer3D.new()
	audio.stream = s.bounce_sounds.pick_random()
	# Harder impacts are louder: full volume at 8 m/s or more, quieter for small ones.
	audio.volume_db = s.bounce_volume_db + linear_to_db(clampf(impact_speed / 8.0, 0.2, 1.0))
	audio.pitch_scale = randf_range(1.0 - s.pitch_variance, 1.0 + s.pitch_variance)
	audio.unit_size = 20
	audio.max_distance = 40.0
	get_tree().current_scene.add_child(audio)
	audio.global_position = at
	audio.play()
	audio.finished.connect(_release_bounce_voice.bind(audio))


func _release_bounce_voice(audio: AudioStreamPlayer3D) -> void:
	_bounce_voices -= 1
	audio.queue_free()


func _play_pickup_sound() -> void:
	var s := _settings
	if s.pickup_sounds.is_empty() or _pickup_voices >= GoldPickup.MAX_PICKUP_VOICES:
		return
	var now := Time.get_ticks_msec()
	if now - _last_pickup_ms < GoldPickup.PICKUP_MIN_GAP_MS:
		return
	_last_pickup_ms = now
	_pickup_voices += 1
	var audio := AudioStreamPlayer.new()
	audio.stream = s.pickup_sounds.pick_random()
	audio.volume_db = s.pickup_volume_db
	audio.pitch_scale = randf_range(1.0 - s.pitch_variance, 1.0 + s.pitch_variance)
	get_tree().current_scene.add_child(audio)
	audio.play()
	audio.finished.connect(_release_pickup_voice.bind(audio))


func _release_pickup_voice(audio: AudioStreamPlayer) -> void:
	_pickup_voices -= 1
	audio.queue_free()


# ======================================================================
# Fallback: node coins (when the native library isn't loaded)
# ======================================================================

func _drop_nodes(origin: Vector3, value: float, count: int) -> void:
	var parent := get_tree().current_scene
	var each := value / count
	for i in count:
		var coin : GoldPickup = GOLD_SCENE.instantiate()
		coin.value = each
		parent.add_child(coin)
		coin.global_position = origin
		coin.burst()
		coin.reset_physics_interpolation()
