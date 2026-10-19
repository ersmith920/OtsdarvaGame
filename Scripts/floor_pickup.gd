# Shared by anything that can be thrown out of a box and lie on the floor.
# Launched pickups fly in an arc, land, and stop dead. Hand-placed ones start landed.
extends Interactable
class_name FloorPickup

@export_group("Launch")
@export var launch_up_speed := 8.0
@export var launch_toward_speed := 2.0
@export var launch_gravity := 20.0
@export_range(0.0, 1.0) var min_floor_normal_y := 0.7   # surfaces flatter than this count as floor

var _landed := true          # hand-placed pickups start "landed"
var _velocity := Vector3.ZERO


## Throws the pickup in the given horizontal direction plus upward.
func launch(horizontal_direction: Vector3) -> void:
	horizontal_direction.y = 0.0
	_velocity = horizontal_direction.normalized() * launch_toward_speed + Vector3.UP * launch_up_speed
	_landed = false


func _physics_process(delta: float) -> void:
	if _landed:
		return

	_velocity.y -= launch_gravity * delta
	var from := global_position
	var to := from + _velocity * delta
	var hit := _raycast(from, to)

	if hit.is_empty():
		global_position = to
		if global_position.y < -100.0:   # fell out of the world
			queue_free()
		return

	if hit.normal.y >= min_floor_normal_y:
		global_position = hit.position   # floor: stop dead right here
		if _on_floor_impact(_velocity):   # a subclass can bounce instead of landing
			return
		_velocity = Vector3.ZERO
		_landed = true
	else:
		# Wall or ceiling: lose sideways motion and drop down along it.
		global_position = hit.position + hit.normal * 0.05
		_velocity.x = 0.0
		_velocity.z = 0.0
		if hit.normal.y < -min_floor_normal_y:
			_velocity.y = minf(_velocity.y, 0.0)


# Ray against the world, ignoring characters (player and enemies) so the pickup
# can't land on someone's head.
func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not (hit.collider is CharacterBody3D):
			return hit
		exclude.append(hit.rid)
	return {}


# Joins the group as soon as it enters the tree, so subclasses with their own
# _ready() (like Gun and ItemPickup) don't need to call super().
func _enter_tree() -> void:
	add_to_group(&"floor_pickups")


## False for anything that shouldn't be swept away, like a gun the player is holding.
func can_be_cleared() -> bool:
	return true

## Called when a launched pickup hits the floor. Return true if it keeps moving (it bounced
## and set _velocity itself), or false to land and stop dead like normal.
func _on_floor_impact(_impact_velocity: Vector3) -> bool:
	return false
