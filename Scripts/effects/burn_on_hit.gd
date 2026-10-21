## On hit: sets the enemy on fire. Each burn deals damage every DoT tick
## (StatusEffects.TICK, 0.25s) for its duration. Burns stack on the same enemy.
##
## Gun DPS mode (default): a burn deals a percent of the firing gun's DPS every second,
## so it scales with the gun, its rolls and the player's damage / attack speed / projectile
## stats. Example: 50% on a 100 DPS gun = 50 damage per second for 3s (150 total).
## Flat mode: the old fixed damage per tick, not scaled by anything.
class_name BurnOnHit
extends OnHitEffect

enum DamageMode { GUN_DPS, FLAT }

@export var damage_mode := DamageMode.GUN_DPS

@export_group("Gun DPS")
## Percent of the gun's DPS each burn deals per second, with 1 copy of the item.
@export var dps_percent := 50.0
## Added to dps_percent for each extra copy of the item.
@export var dps_percent_per_stack := 50.0
## On: the gun's DPS includes reload downtime (sustained DPS). Off: DPS while firing,
## which favors guns with long reloads.
@export var include_reload := true

@export_group("Flat")
## Damage each burn deals per tick, with 1 copy of the item. Not scaled by anything.
## Also used in Gun DPS mode when the hit has no gun (e.g. the gun was dropped).
@export var damage_per_tick := 3.0
## Added to damage_per_tick for each extra copy of the item.
@export var damage_per_tick_per_stack := 3.0

@export_group("")
## Seconds each burn lasts.
@export var duration := 3.0
## Most burns from this effect one enemy can have at once. A new burn past this
## replaces the one closest to running out. 0 = no limit.
@export var max_stacks := 10
## Proc coefficient of the burn's ticks: the chance multiplier for on-hit items they trigger.
## 0 = burn ticks never trigger items. They can never apply more burn either way.
@export_range(0.0, 1.0, 0.05) var tick_proc_coefficient := 0.0


func _apply(info: HitInfo, stacks: int) -> void:
	if info.killed:
		return
	StatusEffects.add_dot(info.enemy, get_key(), get_damage_per_tick(info.source, stacks), duration,
			max_stacks, info.source, tick_proc_coefficient)


## Damage one burn deals each tick, for this gun and item stack count.
func get_damage_per_tick(gun: Gun, stacks: int) -> float:
	var extra := float(maxi(stacks - 1, 0))
	if damage_mode == DamageMode.GUN_DPS and gun != null and is_instance_valid(gun):
		var percent := dps_percent + dps_percent_per_stack * extra
		return gun.get_dps(include_reload) * percent / 100.0 * StatusEffects.TICK
	return damage_per_tick + damage_per_tick_per_stack * extra
