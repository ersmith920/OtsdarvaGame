# Vitals, bottom right: a KH2-style cluster in a clean, modern style (see HudStyle).
#
#                       .---HP---.
#   HP ================'  (core)  )      the HP gauge wraps over the core, then runs left
#   EN ===========        '------'       energy below it
#
# The core is a round readout showing the player's speed (horizontal, in m/s) with a speed
# arc inside it, a slowly turning tick ring and a glow.
# Feel: the gauges glow (a halo, a bright end, a sheen sweeping along them). Damage comes off
# the far (left) end first, leaving a pale trail that drains a moment later; the gauge
# flashes and the cluster jolts on hits. Below LOW health the gauge pulses and a CRITICAL
# tag blinks. The cluster slides in when the level starts.
extends Control

const PADDING := 12
const BLOCK_SIZE := Vector2(440, 128)
## The core (the round readout the HP gauge wraps over).
const CORE_RADIUS := 38.0
const RING_RADIUS := 50.0
const HP_WIDTH := 12.0
const ARC_FROM := -0.14     # radians: where the arc starts (just right of the top)
const ARC_TO := -3.0        # where it ends, on the left, and the straight gauge begins
const HP_BAR_LENGTH := 260.0
const EN_BAR_LENGTH := 230.0
const EN_HEIGHT := 7.0
## Seconds the damage trail waits before draining.
const GHOST_DELAY := 0.35
const GHOST_SPEED := 4.0
## Below this fraction of health the gauge pulses and CRITICAL shows.
const LOW := 0.25
## Glow brightness (0 = none) and seconds between sheens along the gauges.
const GLOW_STRENGTH := 0.9
const SHEEN_CYCLE := 2.6
## The speed arc is full at this multiple of the player's move speed (the tick on the arc
## marks normal top speed).
const SPEED_ARC_MAX := 2.0
## The speed arc: starts bottom left and sweeps clockwise this far.
const SPEED_ARC_START := PI * 0.75
const SPEED_ARC_SWEEP := PI * 1.5

var _block : Control          # the cluster (first child: the Tab menu keeps clear of it)
var _glow : Control           # additive glow drawn over the gauges
var _speed_num : Label
var _en_tag : Label
var _critical : Label
var _hp := 1.0
var _hp_ghost := 1.0
var _en := 1.0
var _en_ghost := 1.0
var _hp_wait := 0.0
var _en_wait := 0.0
var _last_health := -1.0
var _flash := 0.0
var _jolt := 0.0
var _jolting := false
var _time := 0.0
var _speed := 0.0             # shown speed (smoothed)
var _speed_frac := 0.0        # speed / (move speed * SPEED_ARC_MAX)
var _max_frac := 0.5          # where normal top speed sits on the arc

var _core_center := Vector2(BLOCK_SIZE.x - 64, BLOCK_SIZE.y - 60)
var _arc_end := _core_center + Vector2(cos(ARC_TO), sin(ARC_TO)) * RING_RADIUS
var _hp_bar := Rect2(_arc_end.x - HP_BAR_LENGTH, _arc_end.y - HP_WIDTH * 0.5, HP_BAR_LENGTH + 2.0, HP_WIDTH)
var _en_bar := Rect2(_arc_end.x - EN_BAR_LENGTH - 6.0, _arc_end.y + HP_WIDTH * 0.5 + 9.0, EN_BAR_LENGTH, EN_HEIGHT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_block = Control.new()
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.custom_minimum_size = BLOCK_SIZE
	add_child(_block)
	_block.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_block.offset_left = -PADDING - BLOCK_SIZE.x
	_block.offset_right = -PADDING
	_block.offset_top = -PADDING - BLOCK_SIZE.y
	_block.offset_bottom = -PADDING
	_block.draw.connect(_draw_block)

	# Speed in the core: the number, "M/S" under it.
	_speed_num = HudStyle.make_label("0", 24, HudStyle.WHITE, true)
	_speed_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_num.position = _core_center + Vector2(-40, -19)
	_speed_num.size = Vector2(80, 30)
	_block.add_child(_speed_num)
	var unit := HudStyle.make_caption("M/S", 9)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.position = _core_center + Vector2(-30, 9)
	unit.size = Vector2(60, 12)
	_block.add_child(unit)

	# Tags at the left ends of the gauges.
	var hp_tag := HudStyle.make_caption("HP", 11, HudStyle.WHITE)
	hp_tag.position = Vector2(_hp_bar.position.x - 28, _hp_bar.position.y - 2)
	_block.add_child(hp_tag)
	_en_tag = HudStyle.make_caption("EN", 11, HudStyle.WHITE)
	_en_tag.position = Vector2(_en_bar.position.x - 28, _en_bar.position.y - 5)
	_block.add_child(_en_tag)

	_critical = HudStyle.make_caption("HEALTH CRITICAL", 11, HudStyle.RED)
	_critical.position = Vector2(_hp_bar.position.x, _hp_bar.position.y - 22)
	_critical.visible = false
	_block.add_child(_critical)

	# Glow layer over the gauges (additive, so it only ever brightens).
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.size = BLOCK_SIZE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	_block.add_child(_glow)
	_block.move_child(_glow, 0)   # under the labels

	# Boot-up: slides in from the right.
	_block.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(_block, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(_block, "position:x", _block.position.x, 0.4).from(_block.position.x + 80.0) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var player := GameManager.player
	if player == null:
		return
	_time += delta
	var stats := player.stats_node
	var max_health := maxf(stats.get_value(&"max_health"), 0.001)
	var max_energy := maxf(stats.get_value(&"battery_capacity"), 0.001)
	var hp := clampf(player.health / max_health, 0.0, 1.0)
	var en := clampf(player.battery_charge / max_energy, 0.0, 1.0)

	# Hits: flash and jolt, harder for bigger hits.
	if _last_health >= 0.0 and player.health < _last_health - 0.01:
		var lost := (_last_health - player.health) / max_health
		_flash = 1.0
		_jolt = minf(_jolt + 0.4 + lost * 4.0, 1.5)
	_last_health = player.health

	var a := _trail(hp, _hp, _hp_ghost, _hp_wait, delta)
	_hp = a[0]; _hp_ghost = a[1]; _hp_wait = a[2]
	var e := _trail(en, _en, _en_ghost, _en_wait, delta)
	_en = e[0]; _en_ghost = e[1]; _en_wait = e[2]
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_jolt = maxf(_jolt - delta * 6.0, 0.0)

	# Speed (horizontal), smoothed a little so the number doesn't jitter.
	var move_speed := maxf(stats.get_value(&"move_speed"), 0.001)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_speed = lerpf(_speed, speed, 1.0 - exp(-12.0 * delta))
	_speed_frac = clampf(_speed / (move_speed * SPEED_ARC_MAX), 0.0, 1.0)
	_max_frac = 1.0 / SPEED_ARC_MAX
	_speed_num.text = "%d" % roundi(_speed)
	var over := clampf((_speed - move_speed) / move_speed, 0.0, 1.0)
	_speed_num.add_theme_color_override("font_color", HudStyle.WHITE.lerp(HudStyle.CYAN, over))

	_en_tag.add_theme_color_override("font_color", HudStyle.AMBER if en < 0.2 else HudStyle.WHITE)
	var critical := hp <= LOW and player.health > 0.0
	_critical.visible = critical and fmod(_time, 0.8) < 0.55
	if _jolt > 0.0:
		_block.position += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * _jolt
		_block.position = _block.position.lerp(_rest_pos(), 0.5)
		_jolting = true
	elif _jolting:
		_block.position = _rest_pos()
		_jolting = false
	_block.queue_redraw()
	_glow.queue_redraw()


func _rest_pos() -> Vector2:
	return Vector2(size.x - PADDING - BLOCK_SIZE.x, size.y - PADDING - BLOCK_SIZE.y)


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


func _hp_color() -> Color:
	if _hp <= LOW:
		return HudStyle.HP_RED.lerp(Color(1, 0.62, 0.62), 0.5 + 0.5 * sin(_time * TAU * 1.6))
	return HudStyle.HP_RED


# ---------- Drawing ----------

func _arc_length() -> float:
	return RING_RADIUS * absf(ARC_TO - ARC_FROM)


# Draws the part of the HP path (arc over the core, then the straight gauge to the left) from
# its start up to `amount` (0-1 of the whole path).
func _draw_hp_path(ci: CanvasItem, amount: float, color: Color) -> void:
	if amount <= 0.0:
		return
	var arc_len := _arc_length()
	var total := arc_len + HP_BAR_LENGTH
	var shown := amount * total
	var arc_part := minf(shown, arc_len) / arc_len
	HudStyle.draw_gauge_arc(ci, _core_center, RING_RADIUS, ARC_FROM, ARC_FROM + (ARC_TO - ARC_FROM) * arc_part, HP_WIDTH, color)
	var bar_part := maxf(shown - arc_len, 0.0)
	if bar_part > 0.0:
		var w := maxf(bar_part, HP_WIDTH)
		HudStyle._gloss_fill(ci, Rect2(_hp_bar.end.x - w, _hp_bar.position.y, w, HP_WIDTH), color, HP_WIDTH * 0.5)


func _draw_block() -> void:
	# Troughs (no panel behind the cluster: just the gauges themselves).
	var trough := Color(0.0, 0.01, 0.03, 0.7)
	_block.draw_arc(_core_center, RING_RADIUS, ARC_FROM, ARC_TO, 40, trough, HP_WIDTH + 3.0, true)
	_block.draw_colored_polygon(HudStyle.rounded_points(_hp_bar.grow(1.5), HP_WIDTH * 0.5 + 1.5), trough)

	# HP: pale damage trail, then the gauge itself.
	_draw_hp_path(_block, _hp_ghost, HudStyle.TRAIL)
	_draw_hp_path(_block, _hp, _hp_color().lerp(Color.WHITE, _flash * 0.6))
	# Quarter marks across the HP path.
	for i in range(1, 4):
		var at := i / 4.0 * (_arc_length() + HP_BAR_LENGTH)
		if at > _arc_length():
			var x := _hp_bar.end.x - (at - _arc_length())
			_block.draw_line(Vector2(x, _hp_bar.position.y + 2), Vector2(x, _hp_bar.end.y - 2), Color(0, 0, 0, 0.45), 1.0)

	# EN gauge.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	HudStyle.draw_gauge(_block, _en_bar, _en, _en_ghost, en_color, Color(0.8, 0.9, 1.0, 0.5))

	_draw_core()


# The round readout: dark glass disc, hairline rings, a turning tick ring and the speed arc.
func _draw_core() -> void:
	var c := _core_center
	_block.draw_circle(c, CORE_RADIUS + 2.0, Color(0.0, 0.01, 0.03, 0.85))
	_block.draw_circle(c, CORE_RADIUS, HudStyle.PANEL_TOP)
	_block.draw_arc(c, CORE_RADIUS, 0.0, TAU, 64, HudStyle.PANEL_EDGE, 1.0, true)
	_block.draw_arc(c, CORE_RADIUS + 2.5, 0.0, TAU, 64, Color(HudStyle.CYAN, 0.35), 1.0, true)
	# Turning tick ring.
	var spin := _time * 0.4
	for i in 24:
		var a := spin + TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		var major := i % 6 == 0
		_block.draw_line(c + d * (CORE_RADIUS - (6.0 if major else 4.0)), c + d * (CORE_RADIUS - 2.0),
				Color(HudStyle.CYAN, 0.6 if major else 0.25), 1.0, true)
	# Speed arc: trough, fill, and a tick at normal top speed.
	var r := CORE_RADIUS - 10.0
	_block.draw_arc(c, r, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP, 48, Color(HudStyle.CYAN, 0.12), 3.0, true)
	if _speed_frac > 0.005:
		var over := _speed_frac > _max_frac
		var col := HudStyle.CYAN.lerp(Color.WHITE, 0.5) if over else HudStyle.CYAN
		_block.draw_arc(c, r, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP * _speed_frac, 48, col, 3.0, true)
	var ma := SPEED_ARC_START + SPEED_ARC_SWEEP * _max_frac
	var md := Vector2(cos(ma), sin(ma))
	_block.draw_line(c + md * (r - 4.0), c + md * (r + 4.0), Color(HudStyle.WHITE, 0.8), 1.5, true)


func _draw_glow() -> void:
	var breathe := (0.85 + 0.15 * sin(_time * 2.2)) * GLOW_STRENGTH
	var hp_color := _hp_color().lerp(Color.WHITE, _flash * 0.6)
	var k := breathe * (1.0 + _flash)
	# HP halo: wide faint copies of the path.
	var arc_len := _arc_length()
	var shown := _hp * (arc_len + HP_BAR_LENGTH)
	var arc_to := ARC_FROM + (ARC_TO - ARC_FROM) * minf(shown, arc_len) / arc_len
	for i in range(5, 0, -1):
		var w := HP_WIDTH + i * 4.0
		var col := Color(hp_color, 0.05 * k * (1.0 - i / 6.0))
		_glow.draw_arc(_core_center, RING_RADIUS, ARC_FROM, arc_to, 40, col, w, true)
		var bar_part := maxf(shown - arc_len, 0.0)
		if bar_part > 0.0:
			_glow.draw_rect(Rect2(_hp_bar.end.x - bar_part, _hp_bar.position.y, bar_part, HP_WIDTH).grow(i * 2.0), col)
	# Bright leading edge at the end of the HP gauge.
	var end_pt : Vector2
	if shown <= arc_len:
		end_pt = _core_center + Vector2(cos(arc_to), sin(arc_to)) * RING_RADIUS
	else:
		end_pt = Vector2(_hp_bar.end.x - (shown - arc_len), _hp_bar.get_center().y)
	for i in 4:
		_glow.draw_circle(end_pt, 3.0 + i * 3.0, Color(hp_color.lerp(Color.WHITE, 0.5), 0.14 * k / (i + 1)))
	# Sheens sweeping along the straight gauges.
	_sheen(Rect2(_hp_bar.end.x - maxf(shown - arc_len, 0.0), _hp_bar.position.y, maxf(shown - arc_len, 0.0), HP_WIDTH), 0.0, k)
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	var en_rect := Rect2(_en_bar.end.x - _en_bar.size.x * _en, _en_bar.position.y, _en_bar.size.x * _en, EN_HEIGHT)
	for i in range(4, 0, -1):
		_glow.draw_rect(en_rect.grow(i * 1.6), Color(en_color, 0.05 * breathe * (1.0 - i / 5.0)))
	_sheen(en_rect, 0.45, breathe * 0.8)
	# Faint glow on the speed arc.
	if _speed_frac > 0.005:
		_glow.draw_arc(_core_center, CORE_RADIUS - 10.0, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP * _speed_frac,
				48, Color(HudStyle.CYAN, 0.18 * breathe), 8.0, true)


# A light band sliding right to left (toward the far end) across a filled gauge.
func _sheen(r: Rect2, phase: float, k: float) -> void:
	if r.size.x <= 1.0:
		return
	var t := fposmod(_time / SHEEN_CYCLE + phase, 1.0) * 1.4 - 0.2
	if t < 0.0 or t > 1.0:
		return
	var center := r.end.x - r.size.x * t
	for i in 6:
		var half := 3.0 + i * 4.0
		var x0 := maxf(center - half, r.position.x)
		var x1 := minf(center + half, r.end.x)
		if x1 > x0:
			_glow.draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color(1, 1, 1, 0.07 * k / (i + 1)))
