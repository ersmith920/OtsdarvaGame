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

@export_group("Spawn Distance")
## Enemies of this tier spawn between these two distances from the spawner (horizontal, meters).
@export_range(0.0, 500.0, 0.5, "suffix:m") var min_spawn_distance := 15.0
@export_range(0.0, 500.0, 0.5, "suffix:m") var max_spawn_distance := 100.0

@export_group("Gold Drop")
## Gold each enemy of this tier drops at difficulty 1.
@export var gold_per_enemy := 5
## Extra gold per difficulty above 1, as a fraction of the base (0.15 = +15% per difficulty).
@export var gold_difficulty_scaling := 0.15

func get_count(difficulty: int) -> int:
	var steps := floori(float(difficulty - 1) / float(difficulty_step))
	return maxi(base_count + steps * extra_per_step, 0)


func pick() -> PackedScene:
	return enemies.pick_random() if not enemies.is_empty() else null
	
func get_gold(difficulty: int) -> int:
	var mult := 1.0 + gold_difficulty_scaling * float(difficulty - 1)
	return maxi(roundi(gold_per_enemy * mult), 0)
