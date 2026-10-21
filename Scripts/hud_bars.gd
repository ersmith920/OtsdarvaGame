# Vitals, bottom right, in the Kingdom Hearts 2 style crossed with mech hardware (see HudStyle):
#
#                       .---HP---.
#   HP ================'  (core)  )      the HP gauge wraps over the core, then runs left
#   EN ===========        '------'       energy below it, like KH's MP gauge
#
# The core is a round mech emblem standing in for KH's portrait: health number in the middle,
# a slowly turning tick ring, and a glow in the health color.
# Feel: the gauges glow (a halo, a bright end, a sheen sweeping along them). Damage comes off
# the far (left) end first, KH style, leaving a red trail that drains a moment later; the
# gauge flashes white and the cluster jolts on hits. Health turns amber at half, and red with
# a blinking DANGER tag when critical. The cluster slides in when the level starts.
extends Control

const PADDING := 12
const BLOCK_SIZE := Vector2(440, 128)
## The core (the round emblem the HP gauge wraps over).
const CORE_RADIUS := 38.0
const RING_RADIUS := 50.0
const HP_WIDTH := 14.0
const ARC_FROM := -0.14     # radians: where the arc starts (just right of the top)
const ARC_TO := -3.0        # where it ends, on the left, and the straight gauge begins
const HP_BAR_LENGTH := 260.0
const EN_BAR_LENGTH := 230.0
const EN_HEIGHT := 9.0
## Seconds the red damage trail waits before draining.
const GHOST_DELAY := 0.35
const GHOST_SPEED := 4.0
## Health turns amber below this fraction, red (with DANGER) below LOW.
const CAUTION := 0.5
const LOW := 0.25
## Glow brightness (0 = none) and seconds between sheens along the gauges.
const GLOW_STRENGTH := 1.0
const SHEEN_CYCLE := 2.6

var _block : Control          # the cluster (first child: the Tab menu keeps clear of it)
var _glow : Control           # additive glow drawn over the gauges
var _hp_num : Label
var _en_num : Label
var _danger : Label
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

var _core_center := Vector2(BLOCK_SIZE.x - 64, BLOCK_SIZE.y - 60)
var _arc_end := _core_center + Vector2(cos(ARC_TO), sin(ARC_TO)) * RING_RADIUS
var _hp_bar := Rect2(_arc_end.x - HP_BAR_LENGTH, _arc_end.y - HP_WIDTH * 0.5, HP_BAR_LENGTH + 2.0, HP_WIDTH)
var _en_bar := Rect2(_arc_end.x - EN_BAR_LENGTH - 6.0, _arc_end.y + HP_WIDTH * 0.5 + 8.0, EN_BAR_LENGTH, EN_HEIGHT)


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

	# Health number in the core, "HP" above it.
	var tag := HudStyle.make_label("HP", 10, HudStyle.CYAN_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = _core_center + Vector2(-30, -26)
	tag.size = Vector2(60, 14)
	_block.add_child(tag)
	_hp_num = HudStyle.make_label("100", 22, HudStyle.WHITE, true)
	_hp_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_num.position = _core_center + Vector2(-40, -14)
	_hp_num.size = Vector2(80, 30)
	_block.add_child(_hp_num)

	# Tags at the left ends of the gauges.
	var hp_tag := HudStyle.make_label("HP", 12, HudStyle.HP_GREEN, true)
	hp_tag.position = Vector2(_hp_bar.position.x - 30, _hp_bar.position.y - 3)
	_block.add_child(hp_tag)
	_en_num = HudStyle.make_label("EN", 11, HudStyle.EN_BLUE, true)
	_en_num.position = Vector2(_en_bar.position.x - 30, _en_bar.position.y - 5)
	_block.add_child(_en_num)

	_danger = HudStyle.make_label("DANGER", 16, HudStyle.RED, true)
	_danger.position = Vector2(_hp_bar.position.x, _hp_bar.position.y - 30)
	_danger.visible = false
	_block.add_child(_danger)

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

	_hp_num.text = "%d" % ceili(player.health)
	_hp_num.add_theme_color_override("font_color", HudStyle.WHITE.lerp(_hp_color(), 0.35 if _hp <= CAUTION else 0.0))
	_en_num.add_theme_color_override("font_color", HudStyle.AMBER if en < 0.2 else HudStyle.EN_BLUE)

	var critical := hp <= LOW and player.health > 0.0
	_danger.visible = critical and fmod(_time, 0.6) < 0.42
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
		return HudStyle.RED.lerp(Color(1, 0.6, 0.55), 0.5 + 0.5 * sin(_time * TAU * 1.6))
	if _hp <= CAUTION:
		return HudStyle.AMBER
	return HudStyle.HP_GREEN


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
	# Gritty metal backing behind the gauges.
	HudStyle.draw_backing(_block, Rect2(_hp_bar.position.x - 40, _hp_bar.position.y - 16,
			_core_center.x - _hp_bar.position.x + 40, _en_bar.end.y - _hp_bar.position.y + 30))

	# Troughs.
	var trough := Color(0.02, 0.03, 0.06, 0.92)
	_block.draw_arc(_core_center, RING_RADIUS, ARC_FROM, ARC_TO, 32, trough, HP_WIDTH + 4.0, true)
	_block.draw_colored_polygon(HudStyle.rounded_points(_hp_bar.grow(2.0), HP_WIDTH * 0.5 + 2.0), trough)

	# HP: red damage trail, then the gauge itself.
	_draw_hp_path(_block, _hp_ghost, HudStyle.RED)
	_draw_hp_path(_block, _hp, _hp_color().lerp(Color.WHITE, _flash * 0.7))

	# EN gauge.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	HudStyle.draw_gauge(_block, _en_bar, _en, _en_ghost, en_color, Color(0.75, 0.85, 1.0, 0.6))

	_draw_core()


# The round emblem: metal disc, beveled rim, a glow in the health color, a turning tick ring.
func _draw_core() -> void:
	var c := _core_center
	var hp_color := _hp_color()
	_block.draw_circle(c, CORE_RADIUS + 3.0, Color(0.02, 0.03, 0.06, 0.95))
	_block.draw_circle(c, CORE_RADIUS, Color(0.12, 0.13, 0.16, 0.95))
	# Inner glow, stronger when hurt.
	for i in 5:
		var r := CORE_RADIUS * (0.85 - i * 0.14)
		_block.draw_circle(c, r, Color(hp_color, 0.07 + 0.03 * i + 0.1 * _flash))
	# Bevel: light on top, dark underneath.
	_block.draw_arc(c, CORE_RADIUS - 1.5, PI, TAU, 24, Color(1, 1, 1, 0.35), 2.0, true)
	_block.draw_arc(c, CORE_RADIUS - 1.5, 0.0, PI, 24, Color(0, 0, 0, 0.5), 2.0, true)
	_block.draw_arc(c, CORE_RADIUS + 1.5, 0.0, TAU, 48, HudStyle.PLATE_RIM, 2.0, true)
	# Turning tick ring.
	var spin := _time * 0.6
	for i in 16:
		var a := spin + TAU * i / 16.0
		var d := Vector2(cos(a), sin(a))
		var long := i % 4 == 0
		_block.draw_line(c + d * (CORE_RADIUS - 9.0 - (3.0 if long else 0.0)), c + d * (CORE_RADIUS - 5.0),
				Color(HudStyle.CYAN, 0.7 if long else 0.35), 2.0 if long else 1.0, true)


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
		_glow.draw_arc(_core_center, RING_RADIUS, ARC_FROM, arc_to, 32, col, w, true)
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
		_glow.draw_circle(end_pt, 3.0 + i * 3.0, Color(hp_color.lerp(Color.WHITE, 0.5), 0.16 * k / (i + 1)))
	# Sheens sweeping along the straight gauges.
	_sheen(Rect2(_hp_bar.end.x - maxf(shown - arc_len, 0.0), _hp_bar.position.y, maxf(shown - arc_len, 0.0), HP_WIDTH), 0.0, k)
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	var en_rect := Rect2(_en_bar.end.x - _en_bar.size.x * _en, _en_bar.position.y, _en_bar.size.x * _en, EN_HEIGHT)
	for i in range(4, 0, -1):
		_glow.draw_rect(en_rect.grow(i * 1.6), Color(en_color, 0.05 * breathe * (1.0 - i / 5.0)))
	_sheen(en_rect, 0.45, breathe * 0.8)


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
			_glow.draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color(1, 1, 1, 0.08 * k / (i + 1)))
