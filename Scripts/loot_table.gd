# The pool of items chests draw from, plus the odds of each tier.
class_name LootTable
extends Resource

@export_group("Tier odds (percent, keep the five adding up to 100). Gun rarity uses these too: tier 5 = Common ... tier 1 = Legendary")
@export_range(0.0, 100.0, 0.1) var tier_1_chance := 20.0
@export_range(0.0, 100.0, 0.1) var tier_2_chance := 20.0
@export_range(0.0, 100.0, 0.1) var tier_3_chance := 20.0
@export_range(0.0, 100.0, 0.1) var tier_4_chance := 20.0
@export_range(0.0, 100.0, 0.1) var tier_5_chance := 20.0

@export_group("Items")
@export var items: Array[ItemData]


func get_chance_total() -> float:
	return tier_1_chance + tier_2_chance + tier_3_chance + tier_4_chance + tier_5_chance


## Rolls a tier by the odds, then picks a random item from that tier.
## Tiers with no items are skipped, so an empty tier never produces nothing.
## Luck shifts the roll toward rarer tiers (see roll_tier).
func roll(luck: float = 0.0) -> ItemData:
	var by_tier := {1: [], 2: [], 3: [], 4: [], 5: []}
	for item in items:
		if item != null and by_tier.has(item.tier):
			by_tier[item.tier].append(item)

	var allowed : Array[int] = []
	for tier in by_tier:
		if not by_tier[tier].is_empty():
			allowed.append(tier)
	if allowed.is_empty():
		return null

	var tier := roll_tier(luck, allowed)
	if tier == 0:
		return items.pick_random()
	return by_tier[tier].pick_random()


func get_tier_chance(tier: int) -> float:
	match tier:
		1: return tier_1_chance
		2: return tier_2_chance
		3: return tier_3_chance
		4: return tier_4_chance
		5: return tier_5_chance
	return 0.0


## Rolls just a tier (1 = rarest, 5 = most common) from these odds.
## Luck rolls extra times and keeps the best result (like Risk of Rain 2):
##   luck 1 = best of 2 rolls, luck 2 = best of 3, luck 0.5 = 50% chance of a second roll.
##   Negative luck keeps the WORST of the extra rolls instead.
## allowed_tiers limits which tiers can come up (empty = all five).
## Returns 0 only if every allowed tier has 0% odds.
func roll_tier(luck: float = 0.0, allowed_tiers: Array[int] = []) -> int:
	var tiers : Array[int] = [1, 2, 3, 4, 5]
	if not allowed_tiers.is_empty():
		tiers = allowed_tiers
	var total := 0.0
	for tier in tiers:
		total += get_tier_chance(tier)
	if total <= 0.0:
		return 0

	var extra := floori(absf(luck))
	if randf() < absf(luck) - extra:
		extra += 1
	var result := _roll_once(tiers, total)
	for i in extra:
		var other := _roll_once(tiers, total)
		result = mini(result, other) if luck > 0.0 else maxi(result, other)
	return result


func _roll_once(tiers: Array[int], total: float) -> int:
	var r := randf() * total
	for tier in tiers:
		r -= get_tier_chance(tier)
		if r < 0.0:
			return tier
	return tiers.back()
