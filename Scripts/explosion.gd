# Spherical blast spawned by a Bullet on impact. Damages every Enemy inside the radius.
extends Node3D
class_name Explosion

## Blast radius in meters. Later: multiplied by the player's area_size stat.
@export var radius := 4.0
## Scales the firing gun's damage (player damage stat included). 1.0 = same as the gun's damage.
@export var damage := 0
## How long the visual stays up.
@export var lifetime := 0.25
## Physics layers the blast looks for (1 = world + enemies, same as bullets).
@export_flags_3d_physics var damage_mask := 1 | 16
@export var max_targets := 128
@export var visual_color := Color(1.0, 1.0, 1.0, 0.5)



var source: Gun


## Called by the Bullet right after the explosion is added to the tree.
func detonate(at: Vector3, src: Gun) -> void:
	source = src
	global_position = at
	var r := get_radius()
	_spawn_visual(r)
	_damage_area(r)


## One place to apply the future area_size stat, e.g.:
##   return radius * source.get_area_size()
func get_radius() -> float:
	return radius


func _damage_area(r: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = r
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = damage_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit_enemies: Array[Enemy] = []
	for result in get_world_3d().direct_space_state.intersect_shape(query, max_targets):
		var enemy := result.collider as Enemy
		if enemy == null or hit_enemies.has(enemy):
			continue   # world geometry, or an enemy with several shapes already handled
		hit_enemies.append(enemy)

		var stats := GameManager.player.stats_node
		var dmg := damage * stats.get_value(&"damage")
		var is_crit := randf() < stats.get_value(&"crit_chance")
		if is_crit:
			dmg *= 1.0 + stats.get_value(&"crit_damage")
		enemy.take_damage(dmg, is_crit)
		_apply_effects(enemy)


## Hook for future on-hit effects (burn, slow, knockback...). Called once per damaged enemy.
func _apply_effects(_enemy: Enemy) -> void:
	pass


# ---------- Placeholder visual ----------

func _spawn_visual(r: float) -> void:
	# Replace by adding your own child named "Visual" to explosion.tscn.
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()   # radius 0.5 / height 1.0 by default
		sphere.radius = 1.0
		sphere.height = 2.0
		mesh.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = visual_color  # alpha 0.5 = 50% opacity
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		visual = mesh

	# The visual is a unit-radius sphere, so scaling by r matches the damage radius.
	visual.scale = Vector3.ONE * r * 0.3
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE * r, lifetime * 0.4)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(lifetime * 0.6)
	tween.tween_callback(queue_free)
