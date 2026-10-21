# Pylon that closes every chest in the world again (item chests, gun boxes, gun stores),
# and vacuums up every gold coin (and later xp) on the floor by briefly boosting the
# player's pickup range to cover the whole map.
# The orb flashes briefly on use, since this pylon has no on/off state.
extends Pylon
class_name ResetPylon

## How long the orb stays lit after use, in seconds.
@export var flash_time := 0.6

@export_group("Vacuum")
## Pull in every pickup on the floor when used.
@export var vacuum_pickups := true
## Pickup range added while vacuuming, in meters. Big enough to cover the whole level.
@export var vacuum_range := 10000.0
## Seconds the boosted range lasts. Coins only latch on once they've landed, so this
## also catches ones still mid-air from a fresh kill.
@export var vacuum_time := 1.0

var _flash_until_ms := 0
var _vacuum_id := 0   # bumped every use, so an older use's timer can't end a newer vacuum


func _on_interact() -> void:
	for chest in get_tree().get_nodes_in_group(&"chests"):
		(chest as Chest).reset()
	for node in get_tree().get_nodes_in_group(&"resettable"):   # e.g. single-use Combiners
		node.reset()
	if vacuum_pickups:
		_start_vacuum()
	_flash_until_ms = Time.get_ticks_msec() + int(flash_time * 1000.0)
	_refresh_visuals()


func _is_active() -> bool:
	return Time.get_ticks_msec() < _flash_until_ms


# Adds the range as this pylon's own modifier, so removing it later leaves every
# other pickup range bonus (items, upgrades) untouched.
func _start_vacuum() -> void:
	var stat := _pickup_range_stat()
	if stat == null:
		return
	_vacuum_id += 1
	stat.remove_source(self)
	stat.add_flat(self, vacuum_range)
	# false = the timer pauses with the game, so the vacuum still lasts its full time.
	get_tree().create_timer(vacuum_time, false).timeout.connect(_end_vacuum.bind(_vacuum_id))


func _end_vacuum(id: int) -> void:
	if id != _vacuum_id:
		return
	var stat := _pickup_range_stat()
	if stat != null:
		stat.remove_source(self)


func _pickup_range_stat() -> Stat:
	if GameManager.player == null:
		return null
	return GameManager.player.stats_node.get_stat(&"pickup_range")


# If the pylon is ever removed mid-vacuum, don't leave the player with a huge range.
func _exit_tree() -> void:
	_vacuum_id += 1
	var stat := _pickup_range_stat()
	if stat != null:
		stat.remove_source(self)
