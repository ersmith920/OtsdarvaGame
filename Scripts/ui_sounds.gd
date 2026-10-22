# Your own menu sounds. Select res://Sounds/ui_sounds.tres in the FileSystem dock and drag a
# sound file (.wav / .ogg / .mp3) into a slot in the Inspector. Any slot left empty keeps the
# built-in synth bleep for that sound. UIJuice.play() reads this, so every menu (pause, Tab,
# gun store, Combiner, popups) uses it.
class_name UiSounds
extends Resource

@export_group("Hover")
## Plays when the mouse moves onto a button, card or tile.
@export var hover: AudioStream
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var hover_volume_db := 0.0

@export_group("Click")
## Plays when a button, card or tile is pressed / selected.
@export var click: AudioStream
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var click_volume_db := 0.0

@export_group("Variation")
## Random pitch change on each play (0.03 = up to 3% higher or lower), so repeats don't
## sound identical. 0 = always the same pitch.
@export_range(0.0, 0.2, 0.005) var pitch_variation := 0.03
