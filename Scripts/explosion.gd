## Instant spherical area damage, set off by a Bullet when its gun has explosions turned on.
## Creates no nodes: one shape query, then damage + knockback on every enemy found.
## The visual lives on the Bullet (see Bullet._spawn_explosion_visual).
class_name Explosion
extends RefCounted

const ENEMY_MASK := 16        # physics layer 5: enemies only, so terrain never uses up target slots
const MAX_TARGETS := 128      # most node enemies one blast can hit
const MAX_SWARM_TARGETS := 256  # most swarm enemies one blast can hit
## Knockback at the very edge of the blast, as a fraction of the knockback at the center.
const EDGE_KNOCKBACK := 0.5

# Shared by every explosion, so a blast never allocates a shape or query.
static var _shape: SphereShape3D
static var _query: PhysicsShapeQueryParameters3D


static func detonate(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float, src: Gun) -> void:
	if radius <= 0.0 or src == null:
		return
	if _query == null:
		_shape = SphereShape3D.new()
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = _shape
		_query.collision_mask = ENEMY_MASK
		_query.collide_with_bodies = true
		_query.collide_with_areas = false
	_shape.radius = radius
	_query.transform = Transform3D(Basis.IDENTITY, at)

	var results := space.intersect_shape(_query, MAX_TARGETS)
	# Swarm enemies have no physics bodies: they're found through the Swarm's own grid.
	var swarm_hits := Swarm.query_sphere(at, radius, MAX_SWARM_TARGETS)
	if results.is_empty() and swarm_hits.is_empty():
		return

	# One damage roll per blast: the whole explosion crits or it doesn't.
	var roll := src.roll_explosion_damage()
	var push := src.get_explosion_knockback()
	var pop := src.get_explosion_knockback_up()
	var has_knockback := push > 0.0 or pop > 0.0
	var seen := {}
	var targets : Array = []
	for result in results:
		var enemy := result.collider as Enemy
		if enemy == null or enemy.dead or seen.has(enemy):
			continue   # an enemy with several shapes only gets hit once
		seen[enemy] = true
		targets.append(enemy)
	targets.append_array(swarm_hits)

	for enemy in targets:
		var hit := HitInfo.make(enemy, roll.damage, roll.crit, src, src.explosion_proc_coefficient,
				HitInfo.Kind.EXPLOSION, enemy.get_aim_position())
		HitSystem.deal_hit(hit)
		if hit.killed or enemy.dead:
			continue

		if has_knockback:
			var away: Vector3 = enemy.pos - at
			away.y = 0.0
			var dist := away.length()
			var dir := away / dist if dist > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			var falloff := lerpf(1.0, EDGE_KNOCKBACK, clampf(dist / radius, 0.0, 1.0))
			EnemyManager.knock_back(enemy, dir * push * falloff, pop * falloff)
