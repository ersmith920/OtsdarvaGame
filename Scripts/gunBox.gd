# Debug / free gun box. Pops out a random gun with a random rarity and rolled stats,
# so rolled guns can be tested without gold. Leave Roll Table empty for plain guns.
extends Chest
class_name GunBox

@export var guns : Array[PackedScene]

@export_group("Rolls")
## How much each stat rolls (Items/weapon_roll_table.tres). Empty = plain, unrolled guns.
@export var roll_table : WeaponRollTable
## Rarity odds come from this table's tier odds (Items/loot_table.tres, same as item chests).
## Empty = always Common.
@export var rarity_table : LootTable
## Lets luck shift the rarity, like gun stores do.
@export var use_luck := true


func _create_reward() -> FloorPickup:
	if guns.is_empty():
		push_warning("GunBox has no guns assigned")
		return null
	var gun := guns.pick_random().instantiate() as Gun
	if gun != null and roll_table != null:
		var luck := 0.0
		if use_luck and GameManager.player != null:
			luck = GameManager.player.stats_node.get_value(&"luck")
		gun.apply_roll(roll_table.roll_for(gun, Rarity.roll(rarity_table, luck)))
	return gun
