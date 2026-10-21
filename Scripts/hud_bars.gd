# Status block, bottom left: armor (health) and energy (battery) as segmented mech gauges
# on an angled HUD panel (see HudStyle).
#
#   ARMOR                    0100
#   ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱
#   ENERGY                     72
#   ▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱
#
# Feel: when a gauge drops, the lost segments stay as a pale trail that drains a moment later;
# armor flashes and the panel jolts on hits; armor turns amber at half and red when critical,
# with a blinking warning above the panel. It slides in when the level starts.
extends Control

const PADDING := 18
const BLOCK_SIZE := Vector2(292, 82)
const ARMOR_SEGMENTS := 40
const ENERGY_SEGMENTS := 40
## Seconds the lost segments wait before draining away.
const GHOST_DELAY := 0.35
## How fast that trail drains (fraction of the gap per second, roughly).
const GHOST_SPEED := 4.0
## Armor turns amber below this fraction, red (and warns) below LOW.
const CAUTION := 0.5
const LOW := 0.25
const ENERGY_COLOR := Color(0.4, 0.7, 1.0)

var _block : Control          # the panel (first child: the Tab menu keeps clear of it)
var _armor_num : Label
var _energy_num : Label
var _warning : Label
var _armor := 1.0
var _armor_ghost := 1.0
var _energy := 1.0
var _energy_ghost := 1.0
var _armor_wait := 0.0
var _energy_wait := 0.0
var _last_health := -1.0
var _flash := 0.0
var _jolt := 0.0
var _time := 0.0
var _jolting := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_block = Control.new()
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.custom_minimum_size = BLOCK_SIZE
	add_child(_block)
	_block.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_block.offset_left = PADDING
	_block.offset_right = PADDING + BLOCK_SIZE.x
	_block.offset_top = -PADDING - BLOCK_SIZE.y
	_block.offset_bottom = -PADDING
	_block.draw.connect(_draw_block)

	_block.add_child(_caption("ARMOR", Vector2(14, 10)))
	_armor_num = HudStyle.make_label("0100", 20, HudStyle.CYAN, true)
	_armor_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_armor_num.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_armor_num.position = Vector2(BLOCK_SIZE.x - 14 - 120, 4)
	_armor_num.size = Vector2(120, 24)
	_block.add_child(_armor_num)

	_block.add_child(_caption("ENERGY", Vector2(14, 48)))
	_energy_num = HudStyle.make_label("100", 13, ENERGY_COLOR, true)
	_energy_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_energy_num.position = Vector2(BLOCK_SIZE.x - 14 - 80, 46)
	_energy_num.size = Vector2(80, 16)
	_block.add_child(_energy_num)

	_warning = HudStyle.make_label("ARMOR CRITICAL", 13, HudStyle.RED, true)
	_warning.position = Vector2(4, -22)
	_warning.visible = false
	_block.add_child(_warning)

	# Boot-up: slides in from the left.
	_block.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(_block, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(_block, "position:x", _block.position.x, 0.35).from(_block.position.x - 60.0) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _caption(text: String, at: Vector2) -> Label:
	var l := HudStyle.make_label(HudStyle.caption(text), 10, HudStyle.CYAN_DIM)
	l.position = at
	return l


func _process(delta: float) -> void:
	var player := GameManager.player
	if player == null:
		return
	_time += delta
	var stats := player.stats_node
	var max_health := maxf(stats.get_value(&"max_health"), 0.001)
	var max_energy := maxf(stats.get_value(&"battery_capacity"), 0.001)
	var armor := clampf(player.health / max_health, 0.0, 1.0)
	var energy := clampf(player.battery_charge / max_energy, 0.0, 1.0)

	# Hits: flash and jolt, harder for bigger hits.
	if _last_health >= 0.0 and player.health < _last_health - 0.01:
		var lost := (_last_health - player.health) / max_health
		_flash = 1.0
		_jolt = minf(_jolt + 0.4 + lost * 4.0, 1.5)
	_last_health = player.health

	var a := _trail(armor, _armor, _armor_ghost, _armor_wait, delta)
	_armor = a[0]; _armor_ghost = a[1]; _armor_wait = a[2]
	var e := _trail(energy, _energy, _energy_ghost, _energy_wait, delta)
	_energy = e[0]; _energy_ghost = e[1]; _energy_wait = e[2]

	_flash = maxf(_flash - delta * 5.0, 0.0)
	_jolt = maxf(_jolt - delta * 6.0, 0.0)

	var color := _armor_color()
	_armor_num.text = "%04d" % ceili(player.health)
	_armor_num.add_theme_color_override("font_color", color.lerp(Color.WHITE, _flash * 0.7))
	_energy_num.text = "%d" % roundi(energy * 100.0)
	_energy_num.add_theme_color_override("font_color", HudStyle.AMBER if energy < 0.2 else ENERGY_COLOR)

	var critical := armor <= LOW and player.health > 0.0
	_warning.visible = critical and fmod(_time, 0.6) < 0.4
	if _jolt > 0.0:
		_block.position.x = PADDING + randf_range(-1.0, 1.0) * 4.0 * _jolt
		_jolting = true
	elif _jolting:
		_block.position.x = PADDING
		_jolting = false
	_block.queue_redraw()


# [shown fill, trail, trail wait]: the fill jumps, the trail holds then drains after it.
func _trail(value: float, shown: float, ghost: float, wait: float, delta: float) -> Array:
	if value < shown - 0.0001:
		wait = GHOST_DELAY
	shown = value
	if ghost < value:
		return [shown, value, 0.0]
	if wait > 0.0:
		return [shown, ghost, wait - delta]
	ghost = maxf(lerpf(ghost, value, 1.0 - exp(-GHOST_SPEED * delta)) - 0.05 * delta, value)
	return [shown, ghost, 0.0]


func _armor_color() -> Color:
	var c := HudStyle.CYAN
	if _armor <= LOW:
		c = HudStyle.RED.lerp(Color(1, 0.6, 0.55), 0.5 + 0.5 * sin(_time * TAU * 1.6))   # pulsing
	elif _armor <= CAUTION:
		c = HudStyle.AMBER
	return c


func _draw_block() -> void:
	var color := _armor_color()
	var accent := color if _armor <= CAUTION else HudStyle.CYAN
	HudStyle.draw_panel(_block, Rect2(Vector2.ZERO, BLOCK_SIZE), accent)
	var bar_color := color.lerp(Color.WHITE, _flash * 0.8)
	HudStyle.draw_segment_bar(_block, Rect2(14, 30, BLOCK_SIZE.x - 28, 12), _armor, _armor_ghost,
			bar_color, ARMOR_SEGMENTS)
	var energy_color := HudStyle.AMBER if _energy < 0.2 else ENERGY_COLOR
	HudStyle.draw_segment_bar(_block, Rect2(14, 64, BLOCK_SIZE.x - 28, 6), _energy, _energy_ghost,
			energy_color, ENERGY_SEGMENTS, 2.0, 2.0)
