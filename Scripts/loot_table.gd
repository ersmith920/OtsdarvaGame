# The pool of items chests draw from, plus the odds of each tier.
class_name LootTable
extends Resource

@export_group("Tier odds (percent, keep the three adding up to 100)")
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
func roll() -> ItemData:
	var by_tier := {1: [], 2: [], 3: [], 4: [], 5:[]}
	for item in items:
		if item != null and by_tier.has(item.tier):
			by_tier[item.tier].append(item)

	var chances := {1: tier_1_chance, 2: tier_2_chance, 3: tier_3_chance, 4: tier_4_chance, 5: tier_5_chance}
	var total := 0.0
	for tier in by_tier:
		if not by_tier[tier].is_empty():
			total += chances[tier]

	if total <= 0.0:
		return items.pick_random() if not items.is_empty() else null

	var r := randf() * total
	for tier in [1, 2, 3, 4, 5]:
		if by_tier[tier].is_empty():
			continue
		r -= chances[tier]
		if r < 0.0:
			return by_tier[tier].pick_random()
	return items.pick_random()
