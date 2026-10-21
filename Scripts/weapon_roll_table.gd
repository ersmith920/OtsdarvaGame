# Global settings for rolled guns: how much each stat can roll at each rarity, and how many
# stats a gun gets per rarity. Each gun picks WHICH stats it may roll (Gun > Rolls > Rollable Stats);
# this table decides HOW MUCH.
# Rarity odds are not here: gun stores and gun boxes use a LootTable's tier odds
# (Items/gun_rarity_table.tres; item chests have their own, Items/loot_table.tres), shifted
# by the player's luck stat.
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


# ---------- Combiner ----------

## What combining two guns of the same kind makes (their rolls a and b; null = an unrolled
## Common gun). Both guns' bonuses are added together, then:
##   different rarities: the result takes the higher one.
##   same rarity, below Legendary: one rarity up, plus one new stat the gun doesn't have yet,
##     rolled at the new rarity's values.
##   two Legendaries: Mythic, plus a Mythic-range roll added to every stat the gun can roll.
## roll_new = false leaves out the random part (for a preview before the player commits).
## Mythic guns can't be combined (see can_combine).
func combine(gun: Gun, a: GunRoll, b: GunRoll, roll_new := true) -> GunRoll:
	var ra := a.rarity if a != null else Rarity.COMMON
	var rb := b.rarity if b != null else Rarity.COMMON
	var result := GunRoll.new()
	for r in [a, b]:
		if r == null:
			continue
		for kind in r.bonuses:
			result.bonuses[kind] = result.bonuses.get(kind, 0.0) + r.bonuses[kind]

	if ra != rb:
		result.rarity = maxi(ra, rb)
		return result
	result.rarity = mini(ra + 1, Rarity.MYTHIC)
	if not roll_new:
		return result

	if result.rarity == Rarity.MYTHIC:
		_add_mythic_rolls(gun, result)
	else:
		_add_new_stat(gun, result)
	return result


## What combine() will add on top of the summed stats, for the preview. "" = nothing.
static func combine_note(a: GunRoll, b: GunRoll) -> String:
	var ra := a.rarity if a != null else Rarity.COMMON
	var rb := b.rarity if b != null else Rarity.COMMON
	if ra != rb:
		return ""
	if ra == Rarity.LEGENDARY:
		return "+ a Mythic roll on every stat"
	return "+ 1 random new stat"


## Mythic guns are already at the top and can't go in the Combiner.
static func can_combine(gun: Gun) -> bool:
	return gun != null and gun.get_rarity() < Rarity.MYTHIC


# One stat the result doesn't have yet (any stat if it already has them all), at its rarity.
func _add_new_stat(gun: Gun, result: GunRoll) -> void:
	var pool : Array[WeaponStatRange] = []
	var any : Array[WeaponStatRange] = []
	for kind in gun.get_rollable_kinds():
		var r := get_stat_range(kind)
		if r == null or r.weight <= 0.0:
			continue
		# Bounces do nothing without a ricochet chance.
		if kind == WeaponStat.Kind.RICOCHET_BOUNCES and not result.has(WeaponStat.Kind.RICOCHET_CHANCE):
			continue
		any.append(r)
		if not result.has(kind):
			pool.append(r)
	if pool.is_empty():
		pool = any
	if pool.is_empty():
		return
	var pick := _pick_weighted(pool)
	var value := pick.roll(result.rarity)
	if value != 0.0:
		result.bonuses[pick.stat] = result.bonuses.get(pick.stat, 0.0) + value


# A Mythic roll on every stat the gun can roll.
func _add_mythic_rolls(gun: Gun, result: GunRoll) -> void:
	var kinds := gun.get_rollable_kinds()
	# Ricochet Chance first, so Bounces knows whether the gun ends up with a chance.
	kinds.sort_custom(func(x: int, y: int) -> bool:
		return x == WeaponStat.Kind.RICOCHET_CHANCE and y != WeaponStat.Kind.RICOCHET_CHANCE)
	for kind in kinds:
		var r := get_stat_range(kind)
		if r == null or r.weight <= 0.0:
			continue
		if kind == WeaponStat.Kind.RICOCHET_BOUNCES and not result.has(WeaponStat.Kind.RICOCHET_CHANCE):
			continue
		var value := r.roll(Rarity.MYTHIC)
		if value != 0.0:
			result.bonuses[kind] = result.bonuses.get(kind, 0.0) + value


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
