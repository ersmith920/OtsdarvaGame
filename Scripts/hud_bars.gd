# Temporary HUD: red health bar stacked above a blue battery bar, bottom right.
extends Control

const PADDING := 24
const BAR_SIZE := Vector2(260, 22)
const BAR_GAP := 8

var _health_bar: ProgressBar
var _energy_bar: ProgressBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", BAR_GAP)
	add_child(box)

	_health_bar = _make_bar(Color(0.85, 0.15, 0.15))
	_energy_bar = _make_bar(Color(0.2, 0.5, 1.0))
	box.add_child(_health_bar)   # first child = on top
	box.add_child(_energy_bar)

	# Pin to the bottom right and grow up/left so PADDING stays from the edges.
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, PADDING)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _process(_delta: float) -> void:
	var player := GameManager.player
	if player == null:
		return

	var stats := player.stats_node
	_health_bar.max_value = stats.get_value(&"max_health")
	_health_bar.value = player.health
	_energy_bar.max_value = stats.get_value(&"battery_capacity")
	_energy_bar.value = player.battery_charge
