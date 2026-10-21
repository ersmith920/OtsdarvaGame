# How much one weapon stat rolls for at each rarity. Lives in a WeaponRollTable.
# Values are written the way they're shown: Vector2(10, 15) on a percent stat = +10% to +15%,
# on a flat stat (Projectile Count, Ricochet Bounces, Pierce Count) = +10 to +15.
class_name WeaponStatRange
extends Resource

@export var stat : WeaponStat.Kind = WeaponStat.Kind.DAMAGE

@export_group("Range per rarity (min, max)")
@export var common := Vector2(5, 10)
@export var uncommon := Vector2(10, 15)
@export var rare := Vector2(15, 25)
@export var epic := Vector2(25, 35)
@export var legendary := Vector2(35, 50)

@export_group("")
## Rolls are rounded to this. 1 = whole numbers, 0.1 = one decimal (good for Projectile Count).
@export var step := 1.0
## How likely this stat is to be picked compared to the gun's other allowed stats.
@export_range(0.0, 10.0, 0.1) var weight := 1.0


func get_range(rarity: int) -> Vector2:
	match rarity:
		Rarity.COMMON: return common
		Rarity.UNCOMMON: return uncommon
		Rarity.RARE: return rare
		Rarity.EPIC: return epic
		_: return legendary


func roll(rarity: int) -> float:
	var r := get_range(rarity)
	var value := randf_range(minf(r.x, r.y), maxf(r.x, r.y))
	if step > 0.0:
		value = snappedf(value, step)
	return value
