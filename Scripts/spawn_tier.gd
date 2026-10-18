# One category of enemy (Common, Elite, later Boss...) and how many of it spawn per wave.
# Count = base_count + extra_per_step for every `difficulty_step` increases in difficulty.
class_name SpawnTier
extends Resource

@export var tier_name := "Common"
## Every scene in here can spawn for this tier. List a scene twice to make it twice as likely.
@export var enemies: Array[PackedScene]

@export_group("Wave Size")
## Enemies per wave at difficulty 1.
@export var base_count := 0
## How many difficulty increases it takes to add extra enemies.
@export_range(1, 100) var difficulty_step := 1
## How many enemies get added each time that many increases happen.
@export var extra_per_step := 0


func get_count(difficulty: int) -> int:
	var steps := floori(float(difficulty - 1) / float(difficulty_step))
	return maxi(base_count + steps * extra_per_step, 0)


func pick() -> PackedScene:
	return enemies.pick_random() if not enemies.is_empty() else null
