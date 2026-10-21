# An item lying in the world. Floats and spins until the player interacts with it.
# Can be launched in an arc (by a chest); it lands and stops dead, then hovers.
extends FloorPickup
class_name ItemPickup

@export var item: ItemData

@export_group("Model")
## Re-centers the model so its center is at the pickup's origin and its bottom sits
## on the ground, no matter where the model was exported from.
@export var align_model_to_floor := true

@export_group("Float")
@export var float_height := 0.8       # gap between the floor and the BOTTOM of the model
@export var bob_height := 0.12
@export var bob_speed := 2.0
@export var spin_speed := 1.0         # radians per second, 0 to disable

@export_group("Tilt")
@export_range(0.0, 90.0) var tilt_degrees := 45.0

@export_group("Aura")
@export var aura_enabled := true
@export var core_color := Color(1.0, 1.0, 1.0)        # near-white hot center (same for every tier)
@export var glow_strength := 2.5
@export var aura_scale := 0.625
@export var light_energy := 4.0
@export var light_range := 5.0


@onready var model_anchor: Node3D = $ModelAnchor

var _time := 0.0
var _picked_up := false


func _ready() -> void:
	if item == null:
		push_warning("ItemPickup has no item assigned")
		return

	var center := Vector3(0.0, 0.5, 0.0)   # where the aura sits, in ModelAnchor space
	var diameter := 1.0

	var model := item.model.instantiate() as Node3D if item.model != null else null
	if model != null:
		model_anchor.add_child(model)
		var bounds := _get_model_bounds(model)
		if align_model_to_floor:
			var c := bounds.get_center()
			model.position += Vector3(-c.x, -bounds.position.y, -c.z)
			center = Vector3(0.0, bounds.size.y * 0.5, 0.0)
		else:
			center = bounds.get_center()
		diameter = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
				# Tilt around the model's center so it leans in place instead of swinging.
		var pivot := Node3D.new()
		pivot.position = center
		model_anchor.add_child(pivot)
		model.reparent(pivot, false)
		model.position -= center
		pivot.rotation_degrees.x = tilt_degrees

	if aura_enabled:
		_build_aura(center, diameter)

	_time = randf() * TAU   # so a group of items doesn't bob in sync


# Bounding box of every mesh in the model, measured in ModelAnchor space.
func _get_model_bounds(model: Node3D) -> AABB:
	var to_anchor := model_anchor.global_transform.affine_inverse()
	var bounds := AABB()
	var found := false
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var box: AABB = to_anchor * geo.global_transform * geo.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds if found else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


# A green point light plus a soft additive halo that always faces the camera.
# A green point light plus a soft additive halo that always faces the camera:
# near-white at the center, fading through green to nothing at the edge.
func _build_aura(center: Vector3, diameter: float) -> void:
	var color := item.get_tier_color()

	var aura := Node3D.new()
	aura.position = center
	model_anchor.add_child(aura)

	var light := OmniLight3D.new()
	light.light_color = color                  # was aura_color
	light.light_energy = light_energy
	light.omni_range = light_range
	aura.add_child(light)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(core_color, 1.0),
		Color(core_color.lerp(color, 0.5), 0.9),   # was aura_color
		Color(color, 0.45),                        # was aura_color
		Color(color, 0.0),                         # was aura_color
	])
	# ...the rest of the function (texture, material, quad, glow mesh) is unchanged
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = Color(glow_strength, glow_strength, glow_strength, 1.0)   # brightness boost
	material.proximity_fade_enabled = true     # softens the edge where the halo meets the floor
	material.proximity_fade_distance = 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter * aura_scale
	quad.material = material

	var glow := MeshInstance3D.new()
	glow.mesh = quad
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.add_child(glow)

	# Mythic items: the light and halo cycle through the rainbow.
	if Rarity.from_tier(item.tier) >= Rarity.MYTHIC:
		var spin := create_tween().set_loops()
		spin.tween_method(func(_v: float) -> void:
			var c := Rarity.rainbow()
			light.light_color = c
			material.albedo_color = Color(c.r * glow_strength, c.g * glow_strength, c.b * glow_strength, 1.0),
			0.0, 1.0, Rarity.RAINBOW_CYCLE)

func _process(delta: float) -> void:
	_time += delta
	model_anchor.position.y = float_height + sin(_time * bob_speed) * bob_height
	model_anchor.rotate_y(spin_speed * delta)

func interact(normal : Vector3) -> void:
	super(normal)
	if _picked_up or item == null or not _landed:
		return
	_picked_up = true
	GameManager.player.pick_up(item)
	queue_free()
