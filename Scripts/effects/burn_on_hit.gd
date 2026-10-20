## On hit: sets the enemy on fire. Each burn deals flat damage every DoT tick
## (StatusEffects.TICK, 0.25s) for its duration. Burns stack on the same enemy.
class_name BurnOnHit
extends OnHitEffect

## Damage each burn deals per tick, with 1 copy of the item. Flat: not scaled by the hit.
@export var damage_per_tick := 3.0
## Added to damage_per_tick for each extra copy of the item.
@export var damage_per_tick_per_stack := 3.0
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
	var per_tick := damage_per_tick + damage_per_tick_per_stack * float(stacks - 1)
	StatusEffects.add_dot(info.enemy, get_key(), per_tick, duration, max_stacks, info.source,
			tick_proc_coefficient)
