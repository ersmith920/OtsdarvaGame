# Every gun stat that can be rolled on a shop / gun box weapon, plus how each one is shown.
# The order of Kind must match the checkbox list on Gun.rollable_stats.
class_name WeaponStat
extends RefCounted

enum Kind {
	DAMAGE,
	ATTACK_SPEED,
	RELOAD_SPEED,
	PROJECTILE_COUNT,
	PROJECTILE_SPEED,
	ACCURACY,
	MAGAZINE_SIZE,
	AOE_SIZE,
	AOE_DAMAGE,
	KNOCKBACK,
	RICOCHET_CHANCE,
	RICOCHET_BOUNCES,
}

const COUNT := 12

## Shown on cards and tooltips.
const NAMES := {
	Kind.DAMAGE: "Damage",
	Kind.ATTACK_SPEED: "Attack Speed",
	Kind.RELOAD_SPEED: "Reload Speed",
	Kind.PROJECTILE_COUNT: "Projectile Count",
	Kind.PROJECTILE_SPEED: "Projectile Speed",
	Kind.ACCURACY: "Accuracy",
	Kind.MAGAZINE_SIZE: "Magazine Size",
	Kind.AOE_SIZE: "AoE Size",
	Kind.AOE_DAMAGE: "AoE Damage",
	Kind.KNOCKBACK: "Knockback",
	Kind.RICOCHET_CHANCE: "Ricochet Chance",
	Kind.RICOCHET_BOUNCES: "Ricochet Bounces",
}

## Stats shown as a plain number (+1 Projectile Count). Everything else is a percent (+12%).
## Ricochet Chance is percentage POINTS added to the chance (+10% = 10 more points).
const FLAT := [Kind.PROJECTILE_COUNT, Kind.RICOCHET_BOUNCES]

## Only rolled on guns with Explosion Enabled (they'd do nothing otherwise).
const NEEDS_EXPLOSION := [Kind.AOE_SIZE, Kind.AOE_DAMAGE, Kind.KNOCKBACK]


static func name_of(kind: int) -> String:
	return NAMES.get(kind, "?")


static func is_flat(kind: int) -> bool:
	return kind in FLAT


## "+12% Attack Speed", "+1 Projectile Count", "+0.5 Projectile Count".
## Values are stored the way they're shown: 12 means +12%.
static func format(kind: int, value: float) -> String:
	var prefix := "+" if value >= 0.0 else "-"
	var v := absf(value)
	var num := str(int(round(v))) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.01))
	if is_flat(kind):
		return "%s%s %s" % [prefix, num, name_of(kind)]
	return "%s%s%% %s" % [prefix, num, name_of(kind)]
