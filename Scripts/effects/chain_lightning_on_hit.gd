## On hit: lightning jumps from the hit to the nearest enemies, one after another.
## Each jump is its own hit (with a low proc coefficient), so it can trigger other items,
## but never another chain lightning from the same chain.
class_name ChainLightningOnHit
extends OnHitEffect

## Damage of each jump, as a fraction of the original hit's damage.
@export var damage_fraction := 0.6
## How many enemies the lightning jumps to with 1 stack.
@export var jumps := 3
## Extra jumps per stack after the first.
@export var jumps_per_stack := 2
## Farthest the lightning can jump from one enemy to the next (meters).
@export var jump_range := 12.0
## Proc coefficient of each jump: the chance multiplier for items triggered by the lightning.
@export_range(0.0, 1.0, 0.05) var child_proc_coefficient := 0.2
@export var bolt_color := Color(0.55, 0.85, 1.0)
@export var bolt_width := 0.06

const BOLT_TIME := 0.12
const MAX_BOLTS := 40

static var _bolt_mesh: BoxMesh
static var _bolt_materials := {}
static var _active_bolts := 0


func _apply(info: HitInfo, stacks: int) -> void:
	var player := GameManager.player
	if player == null:
		return
	var chain := child_chain(info)
	var already := {info.enemy: true}
	var from := info.position
	var dmg := info.damage * damage_fraction
	var count := jumps + jumps_per_stack * (stacks - 1)

	for i in count:
		var target := EnemyManager.find_nearest(from, jump_range, already)
		if target == null:
			break
		already[target] = true
		var to := target.get_aim_position()
		_draw_bolt(player, from, to)
		var hit := HitInfo.make(target, dmg, info.crit, info.source, child_proc_coefficient,
				HitInfo.Kind.EFFECT, to)
		hit.chain = chain
		HitSystem.deal_hit(hit)
		from = to


# A thin glowing box stretched between the two points, gone after BOLT_TIME.
func _draw_bolt(player: Node, from: Vector3, to: Vector3) -> void:
	if _active_bolts >= MAX_BOLTS:
		return
	var length := from.distance_to(to)
	if length < 0.05:
		return
	if _bolt_mesh == null:
		_bolt_mesh = BoxMesh.new()
		_bolt_mesh.size = Vector3.ONE
	var mat: StandardMaterial3D = _bolt_materials.get(bolt_color)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = bolt_color
		mat.emission_enabled = true
		mat.emission = bolt_color
		mat.emission_energy_multiplier = 4.0
		_bolt_materials[bolt_color] = mat

	var bolt := MeshInstance3D.new()
	bolt.mesh = _bolt_mesh
	bolt.material_override = mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	player.get_tree().current_scene.add_child(bolt)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	bolt.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3(bolt_width, bolt_width, length)),
			(from + to) * 0.5)
	_active_bolts += 1
	player.get_tree().create_timer(BOLT_TIME).timeout.connect(ChainLightningOnHit._release_bolt.bind(bolt))


static func _release_bolt(bolt: Node) -> void:
	_active_bolts -= 1
	if is_instance_valid(bolt):
		bolt.queue_free()
