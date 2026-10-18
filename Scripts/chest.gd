# Shared base for anything that opens with a rumble + open sound (item chests, gun boxes).
# The open animation calls play_rumble() and play_open() at the right moments.
extends Interactable
class_name Chest

@export_group("Audio")
## Played while the chest shakes before opening.
@export var rumble_sounds : Array[AudioStream]
## Played when the lid pops open.
@export var open_sound : AudioStream
@export var rumble_volume_db := 0.0
@export var open_volume_db := 0.0

@onready var animator : AnimationPlayer = $AnimationPlayer
var open := false

func interact(normal : Vector3) -> void:
	super(normal)
	if open:
		return
	animator.play("open")
	open = true


## Call from the open animation (Call Method track) when the lid is up.
func spawn_reward() -> void:
	var reward := _create_reward()
	if reward == null:
		return
	get_tree().current_scene.add_child(reward)
	reward.global_position = $Marker3D.global_position
	reward.launch(GameManager.player.global_position - global_position)


## Subclasses return the thing to pop out (not yet added to the tree), or null.
func _create_reward() -> FloorPickup:
	return null

## Call from the open animation (Call Method track).
## Call from the open animation (Call Method track) with the sound's index.
func play_rumble(index : int = 0) -> void:
	if index < 0 or index >= rumble_sounds.size():
		push_warning("%s: no rumble sound at index %d" % [name, index])
		return
	_play_sound(rumble_sounds[index], rumble_volume_db)

## Call from the open animation (Call Method track).
func play_open() -> void:
	_play_sound(open_sound, open_volume_db)


# One-shot 3D sound at the chest, freed when it finishes.
func _play_sound(stream : AudioStream, volume_db : float) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = volume_db
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


# Joins the group as soon as it enters the tree, so subclasses with their own
# _ready() (like ItemChest) don't need to call super().
func _enter_tree() -> void:
	add_to_group(&"chests")


## Closes the chest again so it can be reopened.
func reset() -> void:
	animator.stop()
	animator.play("RESET")   # snaps the lid and crate back to their closed pose
	open = false
