# The five rarities guns (and later other rolled things) come in.
# Rarity is the same scale as item tiers, just counted the other way:
#   COMMON = tier 5, UNCOMMON = tier 4, RARE = tier 3, EPIC = tier 2, LEGENDARY = tier 1.
# Colors come from TierColors, so rarity and item tiers always match.
class_name Rarity
extends RefCounted

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const COUNT := 5
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]


static func to_tier(rarity: int) -> int:
	return 5 - clampi(rarity, 0, COUNT - 1)


static func from_tier(tier: int) -> int:
	return clampi(5 - tier, 0, COUNT - 1)


static func name_of(rarity: int) -> String:
	return NAMES[clampi(rarity, 0, COUNT - 1)]


static func get_color(rarity: int) -> Color:
	return TierColors.get_color(to_tier(rarity))


## Rolls a rarity from a LootTable's tier odds, shifted toward higher rarities by luck.
## Pass null to get COMMON.
static func roll(table: LootTable, luck: float = 0.0) -> int:
	if table == null:
		return COMMON
	return from_tier(table.roll_tier(luck))
