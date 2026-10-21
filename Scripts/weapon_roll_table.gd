# Global settings for rolled guns: how much each stat can roll at each rarity, and how many
# stats a gun gets per rarity. Each gun picks WHICH stats it may roll (Gun > Rolls > Rollable Stats);
# this table decides HOW MUCH.
# Rarity odds are not here: gun stores and gun boxes use a LootTable's tier odds (the same
# one item chests use), shifted by the player's luck stat.
class_name WeaponRollTable
extends Resource

@export_group("Stats rolled per rarity")
@export_range(0, 12) var common_rolls := 2
@export_range(0, 12) var uncommon_rolls := 2
@export_range(0, 12) var rare_rolls := 2
@export_range(0, 12) var epic_rolls := 3
@export_range(0, 12) var legendary_rolls := 3

@export_group("")
## One entry per stat. A stat with no entry here can't roll on any gun.
@export var stat_ranges : Array[WeaponStatRange]


func get_roll_count(rarity: int) -> int:
	match rarity:
		Rarity.COMMON: return common_rolls
		Rarity.UNCOMMON: return uncommon_rolls
		Rarity.RARE: return rare_rolls
		Rarity.EPIC: return epic_rolls
		_: return legendary_rolls


func get_stat_range(kind: int) -> WeaponStatRange:
	for r in stat_ranges:
		if r != null and r.stat == kind:
			return r
	return null


## Rolls a rarity-appropriate set of bonuses for this gun. The gun doesn't need to be
## in the tree. Each stat is picked at most once.
func roll_for(gun: Gun, rarity: int) -> GunRoll:
	var result := GunRoll.new()
	result.rarity = rarity

	var pool : Array[WeaponStatRange] = []
	# Ricochet Bounces does nothing without a ricochet chance, so it only joins the pool
	# once this gun has rolled Ricochet Chance.
	var bounces : WeaponStatRange = null
	for kind in gun.get_rollable_kinds():
		var r := get_stat_range(kind)
		if r == null or r.weight <= 0.0:
			continue
		if kind == WeaponStat.Kind.RICOCHET_BOUNCES:
			bounces = r
		else:
			pool.append(r)

	for i in get_roll_count(rarity):
		if pool.is_empty():
			break
		var pick := _pick_weighted(pool)
		pool.erase(pick)
		var value := pick.roll(rarity)
		if value != 0.0:
			result.bonuses[pick.stat] = value
			if pick.stat == WeaponStat.Kind.RICOCHET_CHANCE and bounces != null:
				pool.append(bounces)
	return result


static func _pick_weighted(pool: Array[WeaponStatRange]) -> WeaponStatRange:
	var total := 0.0
	for r in pool:
		total += r.weight
	var x := randf() * total
	for r in pool:
		x -= r.weight
		if x < 0.0:
			return r
	return pool.back()
