# Projectile fired by enemies. Flies straight and sweeps a ray every physics tick,
# so even a very fast shell can't skip through a thin wall. Damages the player on hit.
extends Node3D
class_name EnemyProjectile

@export var speed := 80.0
@export var damage := 20.0
@export var knockback_force := 10.0
@export var knockback_up := 4.0
## Seconds before it despawns if it never hits anything.
@export var lifetime := 5.0

# Layer 1 = world + player. Enemies sit on layer 16, so shells pass through them.
const HIT_MASK := 1

var _age := 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return

	# Same convention as Bullet: the projectile's +Z is its forward direction.
	var motion := global_basis.z * speed * delta
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + motion, HIT_MASK)
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		global_position += motion
		return

	global_position = result.position
	_on_hit(result.collider, motion.normalized())


func _on_hit(collider: Object, direction: Vector3) -> void:
	if collider is Player:
		var hit_player := collider as Player
		hit_player.take_damage(damage)
		hit_player.apply_knockback(direction, knockback_force, knockback_up)
	queue_free()
