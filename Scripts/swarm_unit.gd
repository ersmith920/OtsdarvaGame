# A handle to one swarm enemy. Hits, burns, lock-on, ricochet and chain lightning hold
# these just like they hold Enemy nodes, with the same names: dead, spawning, pos,
# take_damage(), get_aim_position(). The actual data lives in the Swarm autoload's arrays.
# A handle is never reused: once `dead` is true it stays dead.
class_name SwarmUnit
extends RefCounted

var slot := -1
var dead := false

var spawning : bool:
	get: return Swarm.is_spawning(slot) if not dead else false
## Feet position.
var pos : Vector3:
	get: return Swarm.get_pos(slot)
var global_position : Vector3:
	get: return Swarm.get_pos(slot)
var height : float:
	get: return Swarm.get_height(slot)
var knockback_resist : float:
	get: return Swarm.get_knockback_resist(slot)
var is_elite : bool:
	get: return Swarm.is_elite(slot)
var health : float:
	get: return Swarm.get_health(slot)


## Same as Enemy.take_damage. Use HitSystem.deal_hit() instead, so on-hit effects run.
func take_damage(damage: float, is_crit: bool = false) -> bool:
	if dead:
		return false
	return Swarm.damage(slot, damage, is_crit)


func get_aim_position() -> Vector3:
	return Swarm.get_aim_position(slot)
