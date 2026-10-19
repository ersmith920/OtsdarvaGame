# Shared base for anything that opens with a rumble + open sound (item chests, gun boxes).
# The open animation calls play_rumble(), play_open(), launch_lid() and spawn_reward() at the right moments.
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

const LID_COLLIDE_MASK := 1   # world only: never hits the player, enemies, bullets or pickups

@onready var animator : AnimationPlayer = $AnimationPlayer
var open := false


func interact(normal : Vector3) -> void:
	super(normal)
	if open:
		return
	animator.play("open")
	open = true


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


## Closes the chest again so it can be reopened.
func reset() -> void:
	animator.stop()
	animator.play("RESET")   # snaps the lid and crate back to their closed pose
	if lid_mesh != null:
		lid_mesh.visible = true   # bring the lid back after it was launched
	open = false
