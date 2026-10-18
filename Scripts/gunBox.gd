extends Chest
class_name GunBox

@export var guns : Array[PackedScene]


func _create_reward() -> FloorPickup:
	if guns.is_empty():
		push_warning("GunBox has no guns assigned")
		return null
	return guns.pick_random().instantiate() as FloorPickup
