# Pylon that closes every chest in the world again (item chests and gun boxes).
# The orb flashes briefly on use, since this pylon has no on/off state.
extends Pylon
class_name ResetPylon

## How long the orb stays lit after use, in seconds.
@export var flash_time := 0.6

var _flash_until_ms := 0


func _on_interact() -> void:
	for chest in get_tree().get_nodes_in_group(&"chests"):
		(chest as Chest).reset()
	_flash_until_ms = Time.get_ticks_msec() + int(flash_time * 1000.0)
	_refresh_visuals()


func _is_active() -> bool:
	return Time.get_ticks_msec() < _flash_until_ms
