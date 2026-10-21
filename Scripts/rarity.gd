# The rarities guns (and later other rolled things) come in.
# Rarity is the same scale as item tiers, just counted the other way:
#   COMMON = tier 5, UNCOMMON = tier 4, RARE = tier 3, EPIC = tier 2, LEGENDARY = tier 1.
# Colors come from TierColors, so rarity and item tiers always match.
#
# MYTHIC sits above Legendary and only comes from the Combiner (two Legendaries). It has no
# item tier; its color is a bright rainbow that cycles over time, so anything showing it
# should keep re-reading get_color() (see RarityAnimator).
class_name Rarity
extends RefCounted

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHIC }

const COUNT := 6
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]

## Seconds for the Mythic rainbow to go all the way around.
const RAINBOW_CYCLE := 3.0
## How washed-out the rainbow is: lower = lighter, brighter pastel colors (0 = white).
const RAINBOW_SATURATION := 0.42


static func to_tier(rarity: int) -> int:
	if rarity >= MYTHIC:
		return 0
	return 5 - clampi(rarity, 0, LEGENDARY)


## Item tiers only go up to Legendary (tier 1), so this never returns MYTHIC.
static func from_tier(tier: int) -> int:
	return clampi(5 - tier, 0, LEGENDARY)


static func name_of(rarity: int) -> String:
	return NAMES[clampi(rarity, 0, COUNT - 1)]


## The rarity's color right now (Mythic changes every frame).
static func get_color(rarity: int) -> Color:
	if rarity >= MYTHIC:
		return rainbow()
	return TierColors.get_color(to_tier(rarity))


## True if this rarity's color changes over time.
static func is_animated(rarity: int) -> bool:
	return rarity >= MYTHIC


## The Mythic rainbow at this moment. offset (0-1) shifts the hue, for multi-colored effects.
static func rainbow(offset := 0.0) -> Color:
	var hue := fposmod(Time.get_ticks_msec() / 1000.0 / RAINBOW_CYCLE + offset, 1.0)
	return Color.from_hsv(hue, RAINBOW_SATURATION, 1.0)


## Rolls a rarity from a LootTable's tier odds, shifted toward higher rarities by luck.
## Pass null to get COMMON.
static func roll(table: LootTable, luck: float = 0.0) -> int:
	if table == null:
		return COMMON
	return from_tier(table.roll_tier(luck))
