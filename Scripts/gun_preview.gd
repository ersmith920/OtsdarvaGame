# A small 3D picture of a gun's model for UI (shop cards, Tab menu tiles).
# Copies only the gun scene's ModelAnchor into its own little world with a camera and light,
# auto-framed to the model's size, so any gun works without setup.
# Keeps working while the game is paused.
class_name GunPreview
extends SubViewportContainer

## Radians per second the model turns. 0 = still (and rendered only once, which is cheaper).
var spin_speed := 0.6
## Camera direction toward the model. Default: from the side, a little above and in front.
var view_direction := Vector3(1.0, 0.55, 0.45)
## Extra room around the model (1 = the model just touches the edges).
var framing := 0.8

var _viewport : SubViewport
var _pivot : Node3D


## Builds a preview of `scene` (a gun .tscn). `px` = size in pixels.
static func create(scene: PackedScene, px: Vector2i, spin := 0.6) -> GunPreview:
	var preview := GunPreview.new()
	preview.spin_speed = spin
	preview.custom_minimum_size = Vector2(px)
	preview._build(scene, px)
	return preview


func _build(scene: PackedScene, px: Vector2i) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true

	_viewport = SubViewport.new()
	_viewport.size = px
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if spin_speed != 0.0 \
			else SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	_viewport.add_child(key)
	key.transform = _looking_at_origin(Vector3(2, 3, 2))
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.5
	_viewport.add_child(rim)
	rim.transform = _looking_at_origin(Vector3(-2, 1, -3))

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var model := _take_model(scene)
	var bounds := AABB(Vector3(-0.3, -0.1, -0.5), Vector3(0.6, 0.2, 1.0))
	if model != null:
		_pivot.add_child(model)
		bounds = _bounds_of(model)
		model.position = -bounds.get_center()   # spin around the model's middle

	var cam := Camera3D.new()
	cam.fov = 35.0
	_viewport.add_child(cam)
	var radius := maxf(bounds.size.length() * 0.5, 0.05)
	var dist := radius * framing / sin(deg_to_rad(cam.fov * 0.5))
	cam.transform = _looking_at_origin(view_direction.normalized() * dist)
	cam.near = maxf(dist - radius * 2.0, 0.01)
	cam.far = dist + radius * 4.0


# Built before the preview is in the tree, so no look_at() (that needs global transforms).
static func _looking_at_origin(from: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(-from, Vector3.UP), from)


func _process(delta: float) -> void:
	if spin_speed != 0.0 and _pivot != null:
		_pivot.rotate_y(spin_speed * delta)


# Instantiates the gun and keeps only its ModelAnchor (no script, sounds or pickup area).
static func _take_model(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var inst := scene.instantiate()
	var anchor := inst.get_node_or_null(^"ModelAnchor") as Node3D
	if anchor == null:
		inst.free()
		return null
	inst.remove_child(anchor)
	inst.free()
	anchor.transform = Transform3D.IDENTITY
	for node in anchor.find_children("*", "", true, false):
		node.owner = null
	return anchor


# Bounding box of every mesh under root, in root's space. Works outside the tree.
static func _bounds_of(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var xf := Transform3D.IDENTITY
		var n : Node = geo
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box : AABB = xf * geo.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds if found else AABB(Vector3(-0.3, -0.1, -0.5), Vector3(0.6, 0.2, 1.0))
