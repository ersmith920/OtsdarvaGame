# One gun instance's rarity and rolled stat bonuses.
# A Gun with a roll applies these on top of its base stats; player stats then apply on top of that.
class_name GunRoll
extends RefCounted

var rarity := Rarity.COMMON
## WeaponStat.Kind -> value, stored the way it's shown (12 = +12%, 1 = +1 projectile).
var bonuses := {}


func get_value(kind: int) -> float:
	return bonuses.get(kind, 0.0)


func has(kind: int) -> bool:
	return bonuses.has(kind)


## Percent stats as a multiplier: +25% -> 1.25.
func mult(kind: int) -> float:
	return 1.0 + get_value(kind) / 100.0


func get_color() -> Color:
	return Rarity.get_color(rarity)


func get_rarity_name() -> String:
	return Rarity.name_of(rarity)


## One line per bonus, in WeaponStat.Kind order: ["+10% Attack Speed", "+5% Damage"].
func describe() -> PackedStringArray:
	var lines := PackedStringArray()
	var kinds := bonuses.keys()
	kinds.sort()
	for kind in kinds:
		lines.append(WeaponStat.format(kind, bonuses[kind]))
	return lines
