## On hit: sets the enemy on fire. The burn deals a share of the hit's damage over time.
class_name BurnOnHit
extends OnHitEffect

## Total burn damage as a fraction of the hit's damage (0.5 = 50% of the hit, spread over the duration).
@export var damage_fraction := 0.5
## Added to damage_fraction for each stack after the first.
@export var damage_fraction_per_stack := 0.5
## Seconds the burn lasts.
@export var duration := 3.0
## Most burns from this effect one enemy can have at once. A new burn past this
## replaces the one closest to running out. 0 = no limit.
@export var max_stacks := 10


func _apply(info: HitInfo, stacks: int) -> void:
	if info.killed:
		return
	var total := info.damage * (damage_fraction + damage_fraction_per_stack * float(stacks - 1))
	StatusEffects.add_dot(info.enemy, get_key(), total, duration, max_stacks, info.source)
