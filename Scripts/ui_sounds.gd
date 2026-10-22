# Your own menu sounds and volumes. Select res://Sounds/ui_sounds.tres in the FileSystem dock
# and edit it in the Inspector:
#   - drag a sound file (.wav / .ogg / .mp3) into a slot to replace that sound; its volume
#     is then the file's own loudness plus that many dB,
#   - leave a slot empty to keep the built-in synth sound, and use its volume to make that
#     built-in sound louder or quieter (0 dB = as it is now, -6 dB = about half as loud),
#   - Limits: how often hover and typing sounds may repeat.
# UIJuice.play() reads this, so every menu (pause, Tab, gun store, Combiner, popups) uses it.
class_name UiSounds
extends Resource

@export_group("Hover")
## Plays when the mouse moves onto a button, card or tile.
@export var hover: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var hover_volume_db := 0.0

@export_group("Click")
## Plays when a button is pressed.
@export var click: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var click_volume_db := 0.0

@export_group("Select")
## Picking something: a gun store card, a Combiner pick, dropping a weapon into a slot.
@export var select: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var select_volume_db := 0.0
## Picking or making an Epic / Legendary.
@export var select_rare: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var select_rare_volume_db := 0.0
## Picking or making a Mythic.
@export var select_mythic: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var select_mythic_volume_db := 0.0

@export_group("Menus")
## Opening a menu or page (gun store, settings), and closing one / taking a pick back out.
@export var open: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var open_volume_db := 0.0
@export var close: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var close_volume_db := 0.0
## The screen switching on and off like a CRT (pause, gun store, Combiner, Tab).
@export var power_on: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var power_on_volume_db := 0.0
@export var power_off: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var power_off_volume_db := 0.0
## The keystroke ticks while text types in, and slider ticks.
@export var typing: AudioStream
@export_range(-40.0, 24.0, 0.5, "suffix:dB") var typing_volume_db := 0.0

@export_group("Limits")
## Shortest time between two hover sounds, in milliseconds (so sweeping the mouse over a list
## doesn't stack them). 0 = no limit: every hover plays.
@export_range(0, 300, 1, "suffix:ms") var hover_cooldown_ms := 45
## Shortest time between two typing ticks, in milliseconds. 0 = no limit.
@export_range(0, 300, 1, "suffix:ms") var typing_cooldown_ms := 32

@export_group("Variation")
## Random pitch change on each play (0.03 = up to 3% higher or lower), so repeats don't
## sound identical. 0 = always the same pitch.
@export_range(0.0, 0.2, 0.005) var pitch_variation := 0.03


## The replacement sound (or null) and the volume for one of UIJuice's sounds.
func slot(kind: int) -> Array:
	match kind:
		UIJuice.Sfx.HOVER: return [hover, hover_volume_db]
		UIJuice.Sfx.CLICK: return [click, click_volume_db]
		UIJuice.Sfx.PICK: return [select, select_volume_db]
		UIJuice.Sfx.REWARD: return [select_rare, select_rare_volume_db]
		UIJuice.Sfx.JACKPOT: return [select_mythic, select_mythic_volume_db]
		UIJuice.Sfx.OPEN: return [open, open_volume_db]
		UIJuice.Sfx.CLOSE: return [close, close_volume_db]
		UIJuice.Sfx.BOOT: return [power_on, power_on_volume_db]
		UIJuice.Sfx.SHUTDOWN: return [power_off, power_off_volume_db]
		UIJuice.Sfx.TYPE: return [typing, typing_volume_db]
	return [null, 0.0]
