class_name ItemData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## 1 = best/rarest, 3 = lowest/most common.
@export_range(1, 5) var tier: int = 5
@export var icon: Texture2D
@export var model: PackedScene   # shown on the floor pickup
@export var modifiers: Array[StatModifier]
## Effects that can trigger when the player hits an enemy (burn, chain lightning...).
@export var on_hit_effects: Array[OnHitEffect]

func get_tier_color() -> Color:
	return TierColors.get_color(tier)
