# Plays a sound for every instance of damage the player deals to an enemy.
# Non-positional, so it's heard at any range. Listens to GameManager.enemy_damaged.
extends Node

const BUS_NAME := &"HitSound"

@export var sounds : Array[AudioStream]
## Adjust to taste. Negative = quieter.
@export var volume_db := -6.0
## Hard ceiling on the loudest this sound can get, even when many hits overlap.
@export var max_volume_db := -3.0
## Random pitch wobble so rapid hits don't sound identical (0.05 = +/-5%).
@export_range(0.0, 0.3) var pitch_variance := 0.05
## Minimum time between sounds. Stops one explosion hitting 30 enemies from firing 30 sounds.
@export var min_gap_ms := 20
## Most sounds allowed to play at once.
@export var max_voices := 8

var _active := 0
var _last_ms := 0


func _ready() -> void:
	_ensure_bus()
	GameManager.enemy_damaged.connect(_on_enemy_damaged)


# A dedicated bus with a limiter is what enforces the volume ceiling.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, &"Master")
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = max_volume_db
	AudioServer.add_bus_effect(idx, limiter)


func _on_enemy_damaged(amount: float, _is_crit: bool) -> void:
	if amount <= 0.0 or sounds.is_empty() or _active >= max_voices:
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms < min_gap_ms:
		return
	_last_ms = now
	_active += 1

	# Plain AudioStreamPlayer (not 3D): no distance falloff, so it plays at any range.
	var audio := AudioStreamPlayer.new()
	audio.stream = sounds.pick_random()
	audio.volume_db = volume_db
	audio.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	audio.bus = BUS_NAME
	add_child(audio)
	audio.play()
	audio.finished.connect(_on_voice_finished.bind(audio))


func _on_voice_finished(audio: AudioStreamPlayer) -> void:
	_active -= 1
	audio.queue_free()
