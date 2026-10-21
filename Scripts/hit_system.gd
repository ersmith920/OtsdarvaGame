# Autoload "HitSystem": the one place every hit on an enemy goes through.
# Applies the damage, shows the damage number, then runs the player's on-hit effects
# (from items) and on-kill hooks. Bullets, explosions, ricochets, DoTs and effects all
# call deal_hit(), so a new item effect works with every weapon automatically.
extends Node

## Fired after any hit that kills an enemy.
signal enemy_killed(info: HitInfo)

# Cached [effect, stacks] pairs from the player's items. Rebuilt when items change,
# so a hit never has to walk the inventory.
var _effects: Array = []
var _dirty := true


func _ready() -> void:
	GameManager.item_picked_up.connect(func(_item: ItemData) -> void: _dirty = true)


## Call if items are ever removed or changed outside of pickups.
func mark_effects_dirty() -> void:
	_dirty = true


func deal_hit(info: HitInfo) -> void:
	var enemy = info.enemy   # Enemy node or SwarmUnit
	if enemy == null or not is_instance_valid(enemy) or enemy.dead or enemy.spawning:
		return
	if _dirty:
		_rebuild_effects()

	info.killed = enemy.take_damage(info.damage, info.crit)
	DamageNumbers.spawn(info.position, info.damage, info.crit)

	if info.killed:
		for pair in _effects:
			(pair[0] as OnHitEffect).on_kill(info, pair[1])
		enemy_killed.emit(info)

	if info.proc_coefficient <= 0.0:
		return
	for pair in _effects:
		(pair[0] as OnHitEffect).try_proc(info, pair[1])


func _rebuild_effects() -> void:
	_dirty = false
	_effects.clear()
	var player := GameManager.player
	if player == null:
		return
	for item: ItemData in player.inventory:
		for effect in item.on_hit_effects:
			if effect != null:
				_effects.append([effect, int(player.inventory[item])])
