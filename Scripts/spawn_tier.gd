# One category of enemy (Minor, Major, later Boss...) and how it spawns and scales.
# Count = base_count + extra_per_step for every `difficulty_step` increases in difficulty.
class_name SpawnTier
extends Resource

@export var tier_name := "Minor"
## Every scene in here can spawn for this tier. List a scene twice to make it twice as likely.
@export var enemies: Array[PackedScene]
## Whether enemies from this tier can roll as elites (settings live on the EnemySpawner).
@export var allow_elites := true
## Whether swarms multiply this tier's wave size (settings live on the EnemySpawner).
@export var boosted_by_swarms := true

@export_group("Wave Frequency")
## This tier spawns every this many waves. 1 = every wave, 2 = every other wave, 3 = every third...
@export_range(1, 100) var wave_interval := 1
## The first wave this tier spawns on (waves are counted from 1).
## With wave_interval 2: first_wave 1 spawns on waves 1, 3, 5... and first_wave 2 on waves 2, 4, 6...
@export_range(1, 100) var first_wave := 1

@export_group("Wave Size")
## Enemies per wave at difficulty 1.
@export var base_count := 0
## How many difficulty increases it takes to add extra enemies.
@export_range(1, 100) var difficulty_step := 1
## How many enemies get added each time that many increases happen.
@export var extra_per_step := 0

@export_group("Health Scaling")
## Extra health per difficulty above 1, as a fraction of the enemy's base health
## (0.15 = +15% per difficulty, so difficulty 5 = 1.6x health).
@export var health_per_difficulty := 0.15

@export_group("Spawn Distance")
## Enemies of this tier spawn between these two distances from the spawner (horizontal, meters).
@export_range(0.0, 500.0, 0.5, "suffix:m") var min_spawn_distance := 15.0
@export_range(0.0, 500.0, 0.5, "suffix:m") var max_spawn_distance := 100.0

@export_group("Clumps")
## Enemies per clump. A wave is split into this many per group around the player,
## leaving gaps between groups. 1 or less = spread evenly around the ring (no clumps).
@export var enemies_per_clump := 8
## Radius of a clump of enemies_per_clump enemies, in meters. Bigger clumps (swarms) grow
## so they stay about as dense.
@export_range(0.5, 50.0, 0.5, "suffix:m") var clump_radius := 4.0
## Most clumps one wave of this tier splits into. Past this, clumps get bigger instead of more numerous.
@export_range(1, 32) var max_clumps := 4
## Clumps in the same wave are at least this many degrees apart around the player,
## so there are always lanes between them.
@export_range(0.0, 180.0, 1.0, "suffix:°") var clump_min_gap_deg := 50.0

@export_group("Gold Drop")
## Gold each enemy of this tier drops at difficulty 1.
@export var gold_per_enemy := 5
## Extra gold per difficulty above 1, as a fraction of the base (0.15 = +15% per difficulty).
@export var gold_difficulty_scaling := 0.15


## True if this tier takes part in the given wave (waves are counted from 1).
func spawns_on_wave(wave: int) -> bool:
	return wave >= first_wave and (wave - first_wave) % wave_interval == 0


func get_count(difficulty: int) -> int:
	var steps := floori(float(difficulty - 1) / float(difficulty_step))
	return maxi(base_count + steps * extra_per_step, 0)


func get_health_multiplier(difficulty: int) -> float:
	return maxf(1.0 + health_per_difficulty * float(difficulty - 1), 0.01)


func pick() -> PackedScene:
	return enemies.pick_random() if not enemies.is_empty() else null


func get_gold(difficulty: int) -> int:
	var mult := 1.0 + gold_difficulty_scaling * float(difficulty - 1)
	return maxi(roundi(gold_per_enemy * mult), 0)
