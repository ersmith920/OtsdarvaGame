# One row of the InteractableSpawner's table: what to spawn and how often compared to the rest.
class_name InteractableSpawnEntry
extends Resource

## The interactable to place (item_chest.tscn, gun_store.tscn, ...).
@export var scene : PackedScene
## Share of the total count. With Total Count 35, chest weight 25 and gun store weight 10,
## you get about 25 chests and 10 stores, varying a little each run.
@export_range(0.0, 100.0, 0.1) var weight := 1.0
## Always place at least this many (taken out of the total first). 0 = no minimum.
@export var min_count := 0
## Never place more than this many. 0 = no limit.
@export var max_count := 0
## Off: always stands straight up (no random tilt or leaning into slopes). Good for stores.
@export var allow_tilt := true
