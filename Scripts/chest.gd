# Shared base for anything that opens with a rumble + open sound (item chests, gun boxes).
# The open animation calls play_rumble(), play_open(), launch_lid() and spawn_reward() at the right moments.
# Opening costs gold (rising with every chest opened this run), shown as a glowing price above it.
extends Interactable
class_name Chest

@export_group("Audio")
## Played while the chest shakes before opening.
@export var rumble_sounds : Array[AudioStream]
## Played when the lid pops open.
@export var open_sound : AudioStream
## Played when the lid is launched off (launch_lid).
@export var lid_launch_sound : AudioStream
@export var rumble_volume_db := 0.0
@export var open_volume_db := 0.0
@export var lid_launch_volume_db := 0.0

@export_group("Lid Launch")
## The lid mesh inside the model. Leave empty for chests whose lid shouldn't fly off.
@export var lid_mesh : MeshInstance3D
## Upward launch speed in m/s.
@export var lid_up_speed := 7.0
## Random +/- added to the upward speed.
@export var lid_up_jitter := 1.5
## Random sideways speed in m/s, in any direction.
@export var lid_side_speed := 2.5
## Max random spin in radians per second, per axis.
@export var lid_spin := 8.0
## 0 = no bounce, 1 = perfectly bouncy.
@export_range(0.0, 1.0) var lid_bounce := 0.35
## Seconds the lid stays fully visible before it starts fading.
@export var lid_lifetime := 1.5
## Seconds the fade takes.
@export var lid_fade_time := 0.6

@export_group("Cost")
## Gold to open this chest when it's the first one opened in the run. 0 = free (no price shown).
@export var base_cost := 25
## Price goes up by this percent for every chest already opened this run, compounding.
## 10 = each chest costs 10% more than the last: 25, 27.5, 30.25...
@export var cost_increase_percent := 10.0
## Off: opening this one doesn't make later chests pricier (handy for the debug gun box).
@export var counts_toward_price := true
## Played when the player tries to open it without enough gold.
@export var deny_sound : AudioStream
@export var deny_volume_db := 0.0

@export_group("Price Display")
## Font for the floating price. Use the same one as the HUD.
@export var cost_font : Font
## Text size in pixels (of the price image). Bigger = sharper, not bigger in the world.
@export var cost_font_size := 64
## World size of one price-image pixel. This sets how big the price looks.
@export var cost_pixel_size := 0.006
## Coin shown before the price (e.g. gold1.png). Empty = number only.
@export var cost_icon : Texture2D
## Coin size and gap to the number, in price-image pixels (same scale as the font size).
@export var cost_icon_size_px := 64
@export var cost_icon_gap_px := 10
@export var cost_icon_pixel_art := true
## Height of the price above the chest's origin, in meters.
@export var cost_height := 1.6
## The price fades out beyond this distance, in meters.
@export var cost_visible_distance := 45.0
## Match these to the GoldPickup scene's Glow settings so the price shines like the coins.
## Values above 1 bloom using the scene's Glow, exactly like the floor coins.
@export var cost_glow_tint := Color(0.92, 0.93, 0.64)
@export_range(1.0, 4.0, 0.05) var cost_glow_strength := 2.0
## Text outline, for readability against bright backgrounds.
@export var cost_outline_color := Color(0.25, 0.15, 0.02, 1.0)
@export var cost_outline_size := 12
## Price color while the player can't afford it (no glow).
@export var cant_afford_color := Color(0.75, 0.3, 0.25, 1.0)

const LID_COLLIDE_MASK := 1   # world only: never hits the player, enemies, bullets or pickups

@onready var animator : AnimationPlayer = $AnimationPlayer
var open := false

var _cost_root : Node3D
var _cost_viewport : SubViewport
var _cost_row : HBoxContainer
var _cost_label : Label
var _cost_quad : MeshInstance3D
var _cost_material : StandardMaterial3D
var _cost_built := false
var _shown_cost := -1
var _deny_shake := 0.0


## Current price, from base_cost and how many chests have been opened this run.
func get_cost() -> int:
	if base_cost <= 0:
		return 0
	return roundi(base_cost * pow(1.0 + cost_increase_percent / 100.0, GameManager.chests_opened))


func interact(normal : Vector3) -> void:
	super(normal)
	if open:
		return
	var cost := get_cost()
	if cost > 0:
		var player := GameManager.player
		if player == null or player.gold < cost:
			_deny()
			return
		player.gold -= cost
		GameManager.gold_changed.emit(player.gold)
	if counts_toward_price:
		GameManager.chests_opened += 1
		GameManager.chests_opened_changed.emit(GameManager.chests_opened)
	animator.play("open")
	open = true
	_refresh_cost_display()


func _deny() -> void:
	_play_sound(deny_sound, deny_volume_db)
	_deny_shake = 1.0


# ---------- Floating price ----------
# Label3D and Sprite3D clamp their tint, so they can't get bright enough to bloom.
# Instead the coin + number are drawn into a small 2D image (SubViewport) and shown on a
# quad whose material color is pushed above 1, the same way the floor coins glow.

# Built one frame after entering the tree, so it works whether or not a subclass's
# _ready() calls super(), and after spawners have set the chest's final position.
func _build_cost_display() -> void:
	if _cost_built or not is_inside_tree():
		return
	_cost_built = true

	_cost_root = Node3D.new()
	_cost_root.top_level = true   # stays upright even when the chest is tilted
	add_child(_cost_root)

	# --- The 2D image: [coin] 123 ---
	_cost_viewport = SubViewport.new()
	_cost_viewport.transparent_bg = true
	_cost_viewport.disable_3d = true
	_cost_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_cost_root.add_child(_cost_viewport)

	_cost_row = HBoxContainer.new()
	_cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cost_row.add_theme_constant_override("separation", cost_icon_gap_px)
	_cost_viewport.add_child(_cost_row)

	if cost_icon != null:
		var coin := TextureRect.new()
		coin.texture = cost_icon
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.custom_minimum_size = Vector2(cost_icon_size_px, cost_icon_size_px)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if cost_icon_pixel_art \
				else CanvasItem.TEXTURE_FILTER_LINEAR
		_cost_row.add_child(coin)

	_cost_label = Label.new()
	if cost_font != null:
		_cost_label.add_theme_font_override("font", cost_font)
	_cost_label.add_theme_font_size_override("font_size", cost_font_size)
	_cost_label.add_theme_color_override("font_color", Color.WHITE)
	_cost_label.add_theme_color_override("font_outline_color", cost_outline_color)
	_cost_label.add_theme_constant_override("outline_size", cost_outline_size)
	_cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_row.add_child(_cost_label)

	# --- The quad in the world that shows it ---
	_cost_material = StandardMaterial3D.new()
	_cost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cost_material.albedo_texture = _cost_viewport.get_texture()
	_cost_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	_cost_quad = MeshInstance3D.new()
	_cost_quad.mesh = QuadMesh.new()
	_cost_quad.material_override = _cost_material
	_cost_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cost_quad.visibility_range_end = cost_visible_distance
	_cost_quad.visibility_range_end_margin = cost_visible_distance * 0.15
	_cost_quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_cost_root.add_child(_cost_quad)

	# Method callables (not lambdas) so the connections drop cleanly when the chest is freed.
	GameManager.chests_opened_changed.connect(_on_cost_inputs_changed)
	GameManager.gold_changed.connect(_on_cost_inputs_changed)
	_refresh_cost_display()


func _on_cost_inputs_changed(_value: int) -> void:
	_refresh_cost_display()


# Updates the number and the affordability color.
func _refresh_cost_display() -> void:
	if _cost_root == null:
		return
	var cost := get_cost()
	_cost_root.visible = not open and cost > 0
	if not _cost_root.visible:
		return

	# Color lives on the material, so it can go above 1 and bloom (no re-render needed).
	var player := GameManager.player
	var affordable := player != null and player.gold >= cost
	var boosted := cost_glow_tint * cost_glow_strength
	_cost_material.albedo_color = Color(boosted.r, boosted.g, boosted.b, 1.0) if affordable else cant_afford_color

	if cost == _shown_cost:
		return
	_shown_cost = cost
	_cost_label.text = str(cost)

	# Resize the image to fit the new number (plus room for the outline), then redraw it once.
	var pad := cost_outline_size
	var content := _cost_row.get_combined_minimum_size()
	var img_size := Vector2i(ceili(content.x) + pad * 2, ceili(content.y) + pad * 2)
	_cost_viewport.size = img_size
	_cost_row.position = Vector2(pad, pad)
	_cost_row.size = content
	_cost_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	(_cost_quad.mesh as QuadMesh).size = Vector2(img_size) * cost_pixel_size


# Keeps the price above the chest and turned to face the camera.
func _process(delta: float) -> void:
	if _cost_root == null or not _cost_root.visible:
		return
	var shake := Vector3.ZERO
	if _deny_shake > 0.0:
		_deny_shake = maxf(_deny_shake - delta * 3.0, 0.0)
		shake = Vector3(sin(Time.get_ticks_msec() * 0.06) * 0.06 * _deny_shake, 0.0, 0.0)
	var cam := get_viewport().get_camera_3d()
	var basis_to_cam := cam.global_basis.orthonormalized() if cam != null else Basis.IDENTITY
	_cost_root.global_transform = Transform3D(basis_to_cam, global_position + Vector3.UP * cost_height + basis_to_cam * shake)


## Call from the open animation (Call Method track) when the lid is up.
func spawn_reward() -> void:
	var reward := _create_reward()
	if reward == null:
		return
	get_tree().current_scene.add_child(reward)
	reward.global_position = $Marker3D.global_position
	reward.launch(GameManager.player.global_position - global_position)


## Subclasses return the thing to pop out (not yet added to the tree), or null.
func _create_reward() -> FloorPickup:
	return null


## Call from the open animation (Call Method track) at the moment the lid blows off.
## Hides the animated lid and throws a physics copy of it, which fades out and frees itself.
func launch_lid() -> void:
	if lid_mesh == null or lid_mesh.mesh == null or not lid_mesh.visible:
		return

	var xform := lid_mesh.global_transform
	var lid_scale := xform.basis.get_scale()

	# Physics bodies shouldn't be scaled, so the body is unscaled and the mesh/shape carry the scale.
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = LID_COLLIDE_MASK
	body.continuous_cd = true   # fast launch: don't tunnel through thin walls
	var phys := PhysicsMaterial.new()
	phys.bounce = lid_bounce
	body.physics_material_override = phys

	var mesh := MeshInstance3D.new()
	mesh.mesh = lid_mesh.mesh
	mesh.scale = lid_scale
	body.add_child(mesh)

	# Own copy of each material so fading never touches other chests.
	var mats : Array[BaseMaterial3D] = []
	for i in lid_mesh.mesh.get_surface_count():
		var src := lid_mesh.get_active_material(i) as BaseMaterial3D
		if src == null:
			continue   # ShaderMaterials can't be faded this way; they just vanish at the end
		var mat := src.duplicate() as BaseMaterial3D
		mesh.set_surface_override_material(i, mat)
		mats.append(mat)

	# Box collider fitted to the lid's bounds.
	var aabb := lid_mesh.mesh.get_aabb()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x * lid_scale.x, 0.05), maxf(aabb.size.y * lid_scale.y, 0.05), maxf(aabb.size.z * lid_scale.z, 0.05))
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center() * lid_scale
	body.add_child(shape)

	# Don't collide with the chest it was launched from.
	for node in find_children("*", "PhysicsBody3D", true, false):
		body.add_collision_exception_with(node)

	get_tree().current_scene.add_child(body)
	body.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
	body.reset_physics_interpolation()

	var side := Vector2.from_angle(randf() * TAU) * randf_range(0.0, lid_side_speed)
	body.linear_velocity = Vector3(side.x, lid_up_speed + randf_range(-lid_up_jitter, lid_up_jitter), side.y)
	body.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * lid_spin

	lid_mesh.visible = false
	_play_sound(lid_launch_sound, lid_launch_volume_db)

	# The tween lives on the flying lid, so it finishes even if the chest is reset or freed.
	var tween := body.create_tween()
	tween.tween_interval(lid_lifetime)
	tween.tween_callback(Chest._make_transparent.bind(mats))
	tween.tween_method(Chest._set_alpha.bind(mats), 1.0, 0.0, lid_fade_time)
	tween.tween_callback(body.queue_free)


# Transparency only switches on when the fade starts, so the lid renders normally until then.
static func _make_transparent(mats: Array[BaseMaterial3D]) -> void:
	for mat in mats:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


static func _set_alpha(alpha: float, mats: Array[BaseMaterial3D]) -> void:
	for mat in mats:
		mat.albedo_color.a = alpha


## Call from the open animation (Call Method track) with the sound's index.
func play_rumble(index : int = 0) -> void:
	if index < 0 or index >= rumble_sounds.size():
		push_warning("%s: no rumble sound at index %d" % [name, index])
		return
	_play_sound(rumble_sounds[index], rumble_volume_db)


## Call from the open animation (Call Method track).
func play_open() -> void:
	_play_sound(open_sound, open_volume_db)


# One-shot 3D sound at the chest, freed when it finishes.
# max_db is set to the volume too: up close, 3D distance boost pushes sounds past the
# default max_db cap (+3 dB), which would make volume_db changes do nothing.
func _play_sound(stream : AudioStream, volume_db : float) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.max_db = volume_db
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


# Joins the group as soon as it enters the tree, so subclasses with their own
# _ready() (like ItemChest) don't need to call super().
func _enter_tree() -> void:
	add_to_group(&"chests")
	if not _cost_built:
		_build_cost_display.call_deferred()


## Closes the chest again so it can be reopened.
func reset() -> void:
	animator.stop()
	animator.play("RESET")   # snaps the lid and crate back to their closed pose
	if lid_mesh != null:
		lid_mesh.visible = true   # bring the lid back after it was launched
	open = false
	_refresh_cost_display()
