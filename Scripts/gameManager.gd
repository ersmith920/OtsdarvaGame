extends Node

var player : Player
var levelTime = 0
var difficulty = 1
var stageTime = 0
var timer_paused := true   # starts paused; the debug pylon (and the Tab menu) toggles it
var enemy_hp_per_difficulty := 0.15
signal item_picked_up(item: ItemData)
var mouse_sensitivity := 0.008
var master_volume := 1.0
signal enemy_damaged(amount: float, is_crit: bool)
signal gold_changed(total: int)

func get_enemy_health_multiplier() -> float:
	return 1.0 + enemy_hp_per_difficulty * (difficulty - 1)

func _process(delta: float) -> void:
	if timer_paused:
		return
	stageTime += delta
	if stageTime >= 60:
		difficulty += 1
		stageTime = 0
		print('Difficulty has increased: ', difficulty-1, ' -> ', difficulty)
	levelTime += delta
