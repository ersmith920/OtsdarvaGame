# HUD bars: red health bar stacked above a blue battery bar, bottom right.
#
# Feel: when a bar drops, a pale "ghost" chunk stays behind and drains away a moment later
# (so you can see how much a hit took), the health bar flashes on damage, and it pulses
# when health is low.
extends Control

const PADDING := 24
const BAR_SIZE := Vector2(260, 22)
const BAR_GAP := 8
## Seconds the ghost chunk waits before draining.
const GHOST_DELAY := 0.35
## How fast the ghost drains (fraction of the gap per second, roughly).
const GHOST_SPEED := 4.0
## Below this fraction of max health the bar pulses.
const LOW_HEALTH := 0.3

var _health_bar: ProgressBar
var _energy_bar: ProgressBar
var _health_ghost: ProgressBar
var _energy_ghost: ProgressBar
var _health_fill: StyleBoxFlat
var _ghost_wait := {}      # ghost bar -> seconds left before it drains
var _last_health := -1.0
var _flash := 0.0
var _pulse_time := 0.0

const HEALTH_COLOR := Color(0.85, 0.15, 0.15)
const ENERGY_COLOR := Color(0.2, 0.5, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", BAR_GAP)
	add_child(box)

	var health := _make_bar_pair(HEALTH_COLOR)
	_health_bar = health[0]
	_health_ghost = health[1]
	_health_fill = _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	var energy := _make_bar_pair(ENERGY_COLOR)
	_energy_bar = energy[0]
	_energy_ghost = energy[1]
	box.add_child(health[2])   # first child = on top
	box.add_child(energy[2])

	# Pin to the bottom right and grow up/left so PADDING stays from the edges.
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, PADDING)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN


# [bar, ghost bar behind it, holder]. The ghost is a pale copy that lags behind the real bar.
func _make_bar_pair(fill_color: Color) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = BAR_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ghost := _make_bar(fill_color.lerp(Color.WHITE, 0.65), Color(0.0, 0.0, 0.0, 0.5))
	var bar := _make_bar(fill_color, Color(0, 0, 0, 0))
	for b in [ghost, bar]:
		holder.add_child(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return [bar, ghost, holder]


func _make_bar(fill_color: Color, back_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.step = 0.0   # smooth, not whole numbers
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	var back := StyleBoxFlat.new()
	back.bg_color = back_color
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _process(delta: float) -> void:
	var player := GameManager.player
	if player == null:
		return

	var stats := player.stats_node
	var max_health := stats.get_value(&"max_health")
	_set_bar(_health_bar, _health_ghost, max_health, player.health, delta)
	_set_bar(_energy_bar, _energy_ghost, stats.get_value(&"battery_capacity"), player.battery_charge, delta)

	# Flash white on damage.
	if _last_health >= 0.0 and player.health < _last_health - 0.01:
		_flash = 1.0
	_last_health = player.health
	_flash = maxf(_flash - delta * 5.0, 0.0)

	# Pulse when low.
	var color := HEALTH_COLOR
	if max_health > 0.0 and player.health / max_health <= LOW_HEALTH and player.health > 0.0:
		_pulse_time += delta
		var p := 0.5 + 0.5 * sin(_pulse_time * TAU * 1.6)
		color = HEALTH_COLOR.lerp(Color(1.0, 0.45, 0.4), p * 0.6)
	else:
		_pulse_time = 0.0
	_health_fill.bg_color = color.lerp(Color.WHITE, _flash * 0.8)


# The real bar jumps to the value; the ghost holds, then drains down after it.
# (Gaining goes the other way: the ghost jumps up with it, so only losses leave a trail.)
func _set_bar(bar: ProgressBar, ghost: ProgressBar, max_value: float, value: float, delta: float) -> void:
	bar.max_value = max_value
	ghost.max_value = max_value
	if value < bar.value - 0.001:
		_ghost_wait[ghost] = GHOST_DELAY   # a new drop: hold the ghost a moment
	bar.value = value
	if ghost.value < value:
		ghost.value = value
		return
	var wait : float = _ghost_wait.get(ghost, 0.0)
	if wait > 0.0:
		_ghost_wait[ghost] = wait - delta
		return
	ghost.value = maxf(lerpf(ghost.value, value, 1.0 - exp(-GHOST_SPEED * delta)) - max_value * 0.05 * delta, value)
