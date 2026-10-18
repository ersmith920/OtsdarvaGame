# Debug pylon: toggles the game timer (spawns, difficulty, HUD timer).
# Reads/writes GameManager.timer_paused directly, so it stays in sync with the Tab menu toggle.
extends Pylon
class_name TimerPylon


func _on_interact() -> void:
	GameManager.timer_paused = not GameManager.timer_paused
	print("Timer ", "PAUSED" if GameManager.timer_paused else "RUNNING")


func _is_active() -> bool:
	return not GameManager.timer_paused
