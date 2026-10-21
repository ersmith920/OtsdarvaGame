class_name PlayerStats
extends Node

# Defaults, tweak these in the inspector
@export var base_max_health := 100.0
@export var base_health_regen := 1.0    # percent of max health restored per second (1.0 = 1%)
@export var base_damage := 1
@export var base_projectile_count := 1.0   # floored when firing; multiplies each gun's own projectile_count
@export var base_ricochet_chance := 0.0     # 0.15 = 15% chance per bullet
@export var base_ricochet_bounces := 0.0    # extra enemies a ricocheting bullet can chain to
## Enemies a bullet passes through before it stops. Added to each gun's own Pierce Count.
## Decimals are a chance: 1.3 = pierces once, then a 30% chance to pierce again.
@export var base_pierce_count := 0.0
@export var base_attack_speed := 1.0
@export var base_reload_speed := 1.0        # 1.0 = 100% (normal); 2.0 = reloads take half as long
@export var base_accuracy := 1.0
@export var base_crit_chance := 0.05
@export var base_crit_damage := 1.0
@export var base_armor := 0.0
@export var base_move_speed := 7
@export var base_acceleration := 7
@export var base_jump_height := 6.0
@export var base_jump_strength := 8.0
@export var base_jet_strength := 36.0
@export var base_dash_speed := 15               # m/s during a dash (can exceed move_speed)
@export var base_dash_duration := 0.2             # seconds
@export var base_battery_capacity := 100.0
@export var base_battery_recharge_rate := 20.0    # charge per second
@export var base_battery_recharge_delay := 2    #seconds until charging commences after using charge
@export var base_lock_fov := 2.0       # degrees from screen center a target can be locked from
@export var base_lock_strength := 2.0   # how fast the crosshair moves onto targets
@export var base_pickup_range := 4.0       # meters; gold (and later xp) inside this gets pulled in
@export var base_gold_multiplier := 1.0
## Extra rolls on chest/gun rarity, keeping the best. 1 = best of 2, 0.5 = 50% chance of a 2nd roll.
@export var base_luck := 0.0

var stats: Dictionary = {}

func _ready() -> void:
	stats = {
		&"max_health": Stat.new(base_max_health),
		&"health_regen": Stat.new(base_health_regen),
		&"damage": Stat.new(base_damage),
		&"projectile_count": Stat.new(base_projectile_count),
		&"ricochet_chance": Stat.new(base_ricochet_chance),
		&"ricochet_bounces": Stat.new(base_ricochet_bounces),
		&"pierce_count": Stat.new(base_pierce_count),
		&"attack_speed": Stat.new(base_attack_speed),
		&"reload_speed": Stat.new(base_reload_speed),
		&"accuracy": Stat.new(base_accuracy),
		&"crit_chance": Stat.new(base_crit_chance),
		&"crit_damage": Stat.new(base_crit_damage),
		&"armor": Stat.new(base_armor),
		&"jump_strength": Stat.new(base_jump_strength),
		&"jump_height": Stat.new(base_jump_height),
		&"jet_strength": Stat.new(base_jet_strength),
		&"move_speed": Stat.new(base_move_speed),
		&"acceleration": Stat.new(base_acceleration),
		&"dash_speed": Stat.new(base_dash_speed),
		&"dash_duration": Stat.new(base_dash_duration),
		&"battery_capacity": Stat.new(base_battery_capacity),
		&"battery_recharge_rate": Stat.new(base_battery_recharge_rate),
		&"battery_recharge_delay": Stat.new(base_battery_recharge_delay),
		&"lock_fov": Stat.new(base_lock_fov),
		&"lock_strength": Stat.new(base_lock_strength),
		&"pickup_range": Stat.new(base_pickup_range),
		&"gold_multiplier": Stat.new(base_gold_multiplier),
		&"luck": Stat.new(base_luck),
	}

func get_stat(stat_name: StringName) -> Stat:
	return stats[stat_name]

func get_value(stat_name: StringName) -> float:
	return stats[stat_name].value
