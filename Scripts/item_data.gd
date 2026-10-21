class_name ItemData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## 1 = Legendary (best of the normal tiers) ... 5 = Common. 0 = Mythic: above Legendary, for
## special items only (the dev PC). Loot tables never roll Mythic items.
@export_range(0, 5) var tier: int = 5
@export var icon: Texture2D
@export var model: PackedScene   # shown on the floor pickup
@export var modifiers: Array[StatModifier]
## Effects that can trigger when the player hits an enemy (burn, chain lightning...).
@export var on_hit_effects: Array[OnHitEffect]

func get_tier_color() -> Color:
	return TierColors.get_color(tier)
