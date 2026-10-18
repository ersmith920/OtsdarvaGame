extends Chest
class_name ItemChest

@export var loot_table: LootTable
@export var pickup_scene: PackedScene   # item_pickup.tscn


func _ready() -> void:
	if loot_table != null and not is_equal_approx(loot_table.get_chance_total(), 100.0):
		push_warning("LootTable tier odds add up to %s, not 100" % loot_table.get_chance_total())


func _create_reward() -> FloorPickup:
	if loot_table == null or pickup_scene == null:
		push_warning("ItemChest needs a loot_table and pickup_scene")
		return null
	var item := loot_table.roll()
	if item == null:
		return null

	var pickup: ItemPickup = pickup_scene.instantiate()
	pickup.item = item   # set before adding to the tree so _ready sees it
	return pickup
