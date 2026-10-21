# Everything the Swarm needs to know about one kind of swarm enemy, read once from its
# normal enemy scene (e.g. forklift.tscn). You keep editing the scene and its Enemy exports
# as usual; the swarm copies the stats and merges the model into one instanced mesh.
class_name SwarmType
extends RefCounted

const ENEMY_SCRIPT := preload("res://Scripts/enemy.gd")

var scene : PackedScene
## This type's index in the swarm core (set when the first one spawns).
var core_index := -1
## False if the scene can't be a swarm enemy (custom script like the tank, or Use Swarm off).
var valid := false

# Stats, copied from the scene's Enemy exports.
var max_health := 100.0
var speed := 5.0
var radius := 0.9
var height := 1.6
var step_height := 1.0
var can_climb := false
var climb_speed := 6.0
var max_climb_height := 6.0
var knockback_resist := 0.0
var attack_damage := 10.0
var attack_cooldown := 1.0
var knockback_force := 8.0
var knockback_up := 3.0
var attack_reach := 0.3
var emerge_time := 0.8
var emerge_pause := 0.3
var emerge_extra_depth := 0.1
var flash_time := 0.08
var gold_coins := 6
var hit_volume_db := 0.0
var hit_sounds : Array[AudioStream] = []
var death_sounds : Array[AudioStream] = []
var cast_shadows := false
## Height of the AimPoint marker above the enemy's feet (lock-on, damage numbers, ricochet).
var aim_height := 0.5

# Rendering: every enemy of this type is one instance in this MultiMesh. The swarm core
# writes the transforms; the Swarm autoload pushes them in every physics tick.
var mesh : ArrayMesh
var mm_instance : MultiMeshInstance3D
var multimesh : MultiMesh


## Reads the scene. Returns null if it isn't a usable swarm enemy.
static func from_scene(p_scene: PackedScene) -> SwarmType:
	var t := SwarmType.new()
	t.scene = p_scene
	var inst := p_scene.instantiate()
	if inst.get_script() != ENEMY_SCRIPT or not inst.get(&"use_swarm"):
		inst.free()
		return t   # valid stays false: spawned as a normal node instead
	var e := inst as Enemy
	t.max_health = e.maxHealth
	t.speed = e.speed
	t.radius = e.radius
	t.height = e.height
	t.step_height = e.step_height
	t.can_climb = e.can_climb
	t.climb_speed = e.climb_speed
	t.max_climb_height = e.max_climb_height
	t.knockback_resist = e.knockback_resist
	t.attack_damage = e.attack_damage
	t.attack_cooldown = e.attack_cooldown
	t.knockback_force = e.knockback_force
	t.knockback_up = e.knockback_up
	t.attack_reach = e.attack_reach
	t.emerge_time = e.emerge_time
	t.emerge_pause = e.emerge_pause
	t.emerge_extra_depth = e.emerge_extra_depth
	t.flash_time = e.flash_time
	t.gold_coins = e.gold_coins
	t.hit_volume_db = e.hit_volume_db
	t.hit_sounds = e.hitSounds
	t.death_sounds = e.deathSounds
	t.cast_shadows = e.swarm_cast_shadows
	var aim := e.get_node_or_null(^"AimPoint") as Node3D
	if aim != null:
		t.aim_height = aim.position.y
	t.mesh = _merge_meshes(e)
	inst.free()
	t.valid = t.mesh != null and t.mesh.get_surface_count() > 0
	if not t.valid:
		push_warning("Swarm: %s has no meshes, so it can't be drawn as a swarm enemy" % p_scene.resource_path)
	return t


# Merges every MeshInstance3D under the enemy into one mesh in the enemy's own space,
# one surface per material, so a whole enemy is a single instance.
static func _merge_meshes(root: Node3D) -> ArrayMesh:
	var by_material := {}   # Material (or null) -> SurfaceTool
	var order : Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var xf := _transform_to(root, mi)
		for s in mi.mesh.get_surface_count():
			var mat : Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.material_override
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var st : SurfaceTool = by_material.get(mat)
			if st == null:
				st = SurfaceTool.new()
				by_material[mat] = st
				order.append(mat)
			st.append_from(mi.mesh, s, xf)
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for mat in order:
		var st : SurfaceTool = by_material[mat]
		st.commit(out)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


# node's transform relative to root, without needing the scene in the tree.
static func _transform_to(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Makes the MultiMesh node that draws this type. `parent` is the Swarm autoload.
func build_renderer(parent: Node, flash_material: Material, world_aabb: AABB) -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true   # custom.r = hit flash
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	mm_instance = MultiMeshInstance3D.new()
	mm_instance.name = "Swarm_%s" % scene.resource_path.get_file().get_basename()
	mm_instance.multimesh = multimesh
	mm_instance.material_overlay = flash_material
	mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The whole swarm is one object, so give it a box covering the level (no culling).
	mm_instance.custom_aabb = world_aabb.grow(20.0)
	parent.add_child(mm_instance)


func free_renderer() -> void:
	if mm_instance != null and is_instance_valid(mm_instance):
		mm_instance.queue_free()
	mm_instance = null
	multimesh = null
