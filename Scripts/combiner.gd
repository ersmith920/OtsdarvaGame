# Combiner: merges two of the player's guns of the same kind (two Krsws, two Hammer Guns...)
# into one stronger gun. Pressing E pauses the game and opens the CombinerMenu:
#   left = the player's guns, middle = the two picks, right = what they'll make.
#
# Combining adds both guns' rolled bonuses together. Different rarities: the result takes the
# higher one. Same rarity: it goes up a rarity and gets a new random stat (two Legendaries make
# a Mythic with a Mythic roll on every stat). Rules live in WeaponRollTable.combine().
# The new gun replaces the first pick in its slot; both picks are used up.
extends Interactable
class_name Combiner

## Off: can be used any number of times (handy for testing). On: one combine, then it's spent
## (the Reset Pylon makes it usable again).
@export var single_use := false
## The roll table the new stat / Mythic rolls come from (Items/weapon_roll_table.tres).
@export var roll_table : WeaponRollTable
@export var title := "Combiner"

@export_group("Audio")
@export var open_sound : AudioStream
## Played when the two guns are combined.
@export var combine_sound : AudioStream
## Played when it can't be used (already spent).
@export var deny_sound : AudioStream
@export var volume_db := 0.0

@export_group("Used Look")
## Meshes that change to Used Material once a single-use Combiner is spent.
@export var used_meshes : Array[MeshInstance3D]
## Empty = the meshes are just hidden.
@export var used_material : Material

var used := false
var _saved_materials := {}


func _ready() -> void:
	add_to_group(&"resettable")


func interact(_normal: Vector3) -> void:
	if GameManager.choice_open or GameManager.player == null:
		return
	if used:
		_play(deny_sound)
		return
	if roll_table == null:
		push_warning("Combiner: assign roll_table")
		return
	_play(open_sound)
	var layer := CanvasLayer.new()
	layer.layer = 20   # above the HUD
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(layer)
	var menu := CombinerMenu.new()
	menu.combiner = self
	layer.add_child(menu)
	menu.closed.connect(layer.queue_free)


## Turns two guns of the same kind into one, put in a's slot. Called by the menu.
func combine(a: Gun, b: Gun) -> Gun:
	var scene := load(a.scene_file_path) as PackedScene
	var slot := a.get_parent() as Node3D
	var gun := scene.instantiate() as Gun
	gun.apply_roll(roll_table.combine(gun, a.roll, b.roll))
	for old in [a, b]:
		old.get_parent().remove_child(old)
		old.queue_free()
	get_tree().current_scene.add_child(gun)
	gun.global_position = global_position
	gun.equip(slot)
	_play(combine_sound)
	if single_use:
		used = true
		_set_used_look(true)
	return gun


## The Reset Pylon makes a spent Combiner usable again.
func reset() -> void:
	used = false
	_set_used_look(false)


func _set_used_look(is_used: bool) -> void:
	for mesh in used_meshes:
		if mesh == null:
			continue
		if not _saved_materials.has(mesh):
			_saved_materials[mesh] = mesh.material_override
		if used_material == null:
			mesh.visible = not is_used
		else:
			mesh.material_override = used_material if is_used else _saved_materials[mesh]


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
