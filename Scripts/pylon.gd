# Shared base for pylons: a glowing orb, an interact sound, and visuals that follow a state.
# Subclasses override _on_interact() (what it does) and _is_active() (when the orb glows).
extends Interactable
class_name Pylon

@export_group("Glow")
## The ball at the top of the pylon. Its existing material's emission is toggled.
@export var glow_mesh : MeshInstance3D
## Which surface of that mesh holds the glowing material.
@export var glow_surface := 0
## Optional: a light that turns on while the pylon is active.
@export var glow_light : OmniLight3D
@export var glow_color := Color(1.0, 0.1, 0.0, 1.0)
@export var glow_energy := 3.0

@export_group("Audio")
## Played every time the pylon is interacted with.
@export var interact_sound : AudioStream
@export var sound_volume_db := 0.0

var _glow_material : BaseMaterial3D
var _last_active := false


# Subclasses that define their own _ready() must call super() first.
func _ready() -> void:
	if glow_mesh == null:
		push_warning("%s: glow_mesh is not assigned" % name)
	else:
		var source := glow_mesh.get_active_material(glow_surface) as BaseMaterial3D
		if source == null:
			push_warning("%s: surface %d has no StandardMaterial3D to toggle" % [name, glow_surface])
		else:
			# Duplicate so this pylon never modifies a material shared with other pylons.
			_glow_material = source.duplicate()
			_glow_material.emission = glow_color
			_glow_material.emission_energy_multiplier = glow_energy
			glow_mesh.set_surface_override_material(glow_surface, _glow_material)
	_last_active = not _is_active()   # force the first visual refresh
	_refresh_visuals()


func interact(normal : Vector3) -> void:
	super(normal)
	_play_sound()
	_on_interact()


## What this pylon does when the player interacts with it.
func _on_interact() -> void:
	pass


## True while the orb should glow. Polled every frame, so it also reflects
## changes made elsewhere (like the Tab menu toggling the timer).
func _is_active() -> bool:
	return false


func _process(_delta: float) -> void:
	if _is_active() != _last_active:
		_refresh_visuals()


func _refresh_visuals() -> void:
	_last_active = _is_active()
	if _glow_material != null:
		_glow_material.emission_enabled = _last_active
	if glow_light != null:
		glow_light.visible = _last_active


func _play_sound() -> void:
	if interact_sound == null:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = interact_sound
	audio.volume_db = sound_volume_db
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
