## One instance of damage to an enemy. Every damage source builds one of these and
## hands it to HitSystem.deal_hit(), which applies the damage and runs on-hit effects.
class_name HitInfo
extends RefCounted

enum Kind { DIRECT, RICOCHET, EXPLOSION, DOT, EFFECT }

## The enemy hit: an Enemy node or a SwarmUnit (both have dead, take_damage(), get_aim_position()).
var enemy: Object
var damage := 0.0
var crit := false
## The gun this hit came from (can be null for some effects).
var source: Gun
## Scales the CHANCE of on-hit effects (1.0 = full chance, 0 = can't trigger anything).
var proc_coefficient := 1.0
var kind := Kind.DIRECT
## Where the hit landed (used for damage numbers and effects that start from the hit).
var position := Vector3.ZERO
## Effects already part of this hit's proc chain. They won't trigger again from it,
## which stops loops like lightning -> lightning -> lightning.
var chain: Array[StringName] = []
## Set by HitSystem: true if this hit killed the enemy.
var killed := false


static func make(p_enemy: Object, p_damage: float, p_crit: bool, p_source: Gun,
		p_proc: float, p_kind: Kind, p_position: Vector3) -> HitInfo:
	var info := HitInfo.new()
	info.enemy = p_enemy
	info.damage = p_damage
	info.crit = p_crit
	info.source = p_source
	info.proc_coefficient = p_proc
	info.kind = p_kind
	info.position = p_position
	return info
