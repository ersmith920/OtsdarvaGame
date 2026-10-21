# Vitals, bottom right: a KH2-style cluster in a clean, modern style (see HudStyle).
#
#                          .----.
#                        (  core  )|     the HP gauge comes out from underneath the core,
#   HP =================='-------'/      running left; the other end wraps up the core's
#   EN ==========================        right side to the top, as one smooth path;
#                                        energy runs underneath
#
# The HP path is built as a single polygon strip (arc and straight part share one outline),
# so there are no seams or corners where it starts to curve.
# The core shows the player's speed (horizontal, m/s) with a speed arc; the tick ring spins
# faster the faster you go and the core lights up past normal top speed.
# Feel: the gauges glow and a sheen runs along them. Damage comes off the far (left) end
# first, leaving a pale trail that drains a moment later; the gauge flashes and the cluster
# jolts on hits. Healing flares the regained stretch. Below LOW health the gauge pulses and
# a HEALTH CRITICAL tag blinks. The cluster slides in when the level starts.
extends Control

const PADDING := 12
const BLOCK_SIZE := Vector2(440, 140)
## The core (the round readout the HP gauge wraps around).
const CORE_RADIUS := 38.0
const RING_RADIUS := 50.0
const HP_WIDTH := 12.0
## The arc starts at the top of the core (radians), runs clockwise down its right side to the
## bottom, where the straight part takes over and runs left from underneath the core.
const ARC_FROM := -PI * 0.5
const ARC_TO := PI * 0.5
const HP_BAR_LENGTH := 260.0
const EN_HEIGHT := 7.0
## Seconds the damage trail waits before draining.
const GHOST_DELAY := 0.35
const GHOST_SPEED := 4.0
## Below this fraction of health the gauge pulses and HEALTH CRITICAL shows.
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
## The speed readout shows the engine speed times this (24.3 m/s reads 243), to sell the
## mech's size. The speed arc still compares against the real move speed.
const SPEED_DISPLAY_SCALE := 10.0
## Sample spacing along the arc, in pixels (smaller = smoother).
const ARC_STEP := 3.0

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
var _heal := 0.0              # heal flare, fades from 1
var _heal_from := 1.0         # where the regained stretch starts
var _jolt := 0.0
var _jolting := false
var _time := 0.0
var _spin := 0.0
var _speed := 0.0             # shown speed (smoothed)
var _speed_frac := 0.0        # speed / (move speed * SPEED_ARC_MAX)
var _over := 0.0              # 0-1, how far past normal top speed
const _MAX_FRAC := 1.0 / SPEED_ARC_MAX

var _c := Vector2(BLOCK_SIZE.x - 64, BLOCK_SIZE.y - 78)   # core center
var _arc_len := RING_RADIUS * (ARC_TO - ARC_FROM)
var _path_len := _arc_len + HP_BAR_LENGTH
var _bar_y := _c.y + RING_RADIUS                           # center line of the straight part
var _bar_left := _c.x - HP_BAR_LENGTH
var _en_bar := Rect2(_bar_left, _bar_y + HP_WIDTH * 0.5 + 9.0, _c.x - 6.0 - _bar_left, EN_HEIGHT)


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
	_speed_num.position = _c + Vector2(-40, -19)
	_speed_num.size = Vector2(80, 30)
	_speed_num.pivot_offset = _speed_num.size * 0.5
	_block.add_child(_speed_num)
	var unit := HudStyle.make_caption("M/S", 9)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.position = _c + Vector2(-30, 9)
	unit.size = Vector2(60, 12)
	_block.add_child(unit)

	# Tags at the left ends of the gauges.
	var hp_tag := HudStyle.make_caption("HP", 11, HudStyle.WHITE)
	hp_tag.position = Vector2(_bar_left - 30, _bar_y - 8)
	_block.add_child(hp_tag)
	_en_tag = HudStyle.make_caption("EN", 11, HudStyle.WHITE)
	_en_tag.position = Vector2(_bar_left - 30, _en_bar.get_center().y - 8)
	_block.add_child(_en_tag)

	_critical = HudStyle.make_caption("HEALTH CRITICAL", 11, HudStyle.RED)
	_critical.position = Vector2(_bar_left, _bar_y - HP_WIDTH * 0.5 - 20)
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

	# Boot-up: slides in from the right, then the HP gauge fills along its path.
	_block.modulate.a = 0.0
	_hp = 0.0
	_hp_ghost = 0.0
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

	# Hits: flash and jolt, harder for bigger hits. Heals: flare the regained stretch.
	if _last_health >= 0.0:
		if player.health < _last_health - 0.01:
			var lost := (_last_health - player.health) / max_health
			_flash = 1.0
			_jolt = minf(_jolt + 0.4 + lost * 4.0, 1.5)
		elif player.health > _last_health + max_health * 0.02:
			_heal_from = minf(_heal_from, _last_health / max_health) if _heal > 0.0 else _last_health / max_health
			_heal = 1.0
	_last_health = player.health

	# The fill rises smoothly (boot-up and heals) but drops instantly (hits).
	var rise := hp
	if hp > _hp:
		rise = minf(_hp + delta * 1.6, hp)
	var a := _trail(rise, _hp, _hp_ghost, _hp_wait, delta)
	_hp = a[0]; _hp_ghost = a[1]; _hp_wait = a[2]
	var e := _trail(en, _en, _en_ghost, _en_wait, delta)
	_en = e[0]; _en_ghost = e[1]; _en_wait = e[2]
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_heal = maxf(_heal - delta * 1.5, 0.0)
	_jolt = maxf(_jolt - delta * 6.0, 0.0)

	# Speed (horizontal), smoothed a little so the number doesn't jitter.
	var move_speed := maxf(stats.get_value(&"move_speed"), 0.001)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_speed = lerpf(_speed, speed, 1.0 - exp(-12.0 * delta))
	_speed_frac = clampf(_speed / (move_speed * SPEED_ARC_MAX), 0.0, 1.0)
	_over = clampf((_speed - move_speed) / move_speed, 0.0, 1.0)
	_spin += delta * (0.3 + 2.5 * _speed_frac)
	_speed_num.text = "%d" % roundi(_speed * SPEED_DISPLAY_SCALE)
	_speed_num.add_theme_color_override("font_color", HudStyle.WHITE.lerp(HudStyle.CYAN.lerp(Color.WHITE, 0.3), _over))
	_speed_num.scale = Vector2.ONE * (1.0 + 0.12 * _over)

	var low_en := en < 0.2
	_en_tag.add_theme_color_override("font_color",
			HudStyle.AMBER if low_en and fmod(_time, 0.5) < 0.3 else HudStyle.WHITE)
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


# ---------- The HP path ----------
# Distance s runs from the arc's start (0, the top of the core) to the far left end
# of the straight part (_path_len). A fill of f covers s = 0 .. f * _path_len.

func _point(s: float) -> Vector2:
	if s <= _arc_len:
		var a := ARC_FROM + s / RING_RADIUS
		return _c + Vector2(cos(a), sin(a)) * RING_RADIUS
	return Vector2(_c.x - (s - _arc_len), _bar_y)


# Direction of travel at s (the arc's tangent flows straight into the bar's: no corner).
func _tangent(s: float) -> Vector2:
	if s <= _arc_len:
		var a := ARC_FROM + s / RING_RADIUS
		return Vector2(-sin(a), cos(a))
	return Vector2.LEFT


# Sample distances between s0 and s1: dense on the arc, just the ends on the straight part.
func _samples(s0: float, s1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([s0])
	var s := s0
	while true:
		s += ARC_STEP
		if s >= minf(s1, _arc_len):
			break
		out.append(s)
	if s0 < _arc_len and s1 > _arc_len:
		out.append(_arc_len)
	out.append(s1)
	return out


# Fills the HP path between s0 and s1 as one polygon with rounded ends. outer is the color on
# the upper side of the bar (the inside of the curve), inner on the other side, for a soft gloss.
func _strip(ci: CanvasItem, s0: float, s1: float, width: float, outer: Color, inner: Color) -> void:
	s0 = clampf(s0, 0.0, _path_len)
	s1 = clampf(s1, 0.0, _path_len)
	if s1 - s0 < 0.5:
		return
	var half := width * 0.5
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for s in _samples(s0, s1):
		var p := _point(s)
		var n := _tangent(s).rotated(PI * 0.5)   # toward the 'outer' color's side
		outer_pts.append(p + n * half)
		inner_pts.append(p - n * half)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for p in outer_pts:
		pts.append(p)
		cols.append(outer)
	_cap(pts, cols, s1, half, 1.0, outer, inner)
	for i in range(inner_pts.size() - 1, -1, -1):
		pts.append(inner_pts[i])
		cols.append(inner)
	_cap(pts, cols, s0, half, -1.0, inner, outer)
	ci.draw_polygon(pts, cols)
	# Antialiased edges (the polygon itself isn't smoothed).
	ci.draw_polyline(outer_pts, outer, 1.0, true)
	ci.draw_polyline(inner_pts, inner, 1.0, true)


# A rounded end cap at s, swinging from one side to the other through the travel direction
# (dir = 1 at the far end, -1 at the start).
func _cap(pts: PackedVector2Array, cols: PackedColorArray, s: float, half: float, dir: float,
		from_col: Color, to_col: Color) -> void:
	var p := _point(s)
	var t := _tangent(s) * dir
	var n := _tangent(s).rotated(PI * 0.5) * dir
	for k in range(1, 6):
		var ang := PI * k / 6.0
		pts.append(p + (n * cos(ang) + t * sin(ang)) * half)
		cols.append(from_col.lerp(to_col, k / 6.0))


# ---------- Drawing ----------

func _draw_block() -> void:
	# Trough (no panel behind the cluster: just the gauges themselves).
	var trough := Color(0.0, 0.01, 0.03, 0.72)
	_strip(_block, 0.0, _path_len, HP_WIDTH + 3.0, trough, trough)
	var empty := Color(HudStyle.HP_RED, 0.08)
	_strip(_block, 0.0, _path_len, HP_WIDTH, empty, empty)

	# HP: pale damage trail, then the gauge (lighter on the outside edge for a soft gloss).
	_strip(_block, 0.0, _hp_ghost * _path_len, HP_WIDTH, HudStyle.TRAIL, Color(HudStyle.TRAIL, 0.55))
	var col := _hp_color().lerp(Color.WHITE, _flash * 0.6)
	_strip(_block, 0.0, _hp * _path_len, HP_WIDTH, col.lerp(Color.WHITE, 0.22), col.darkened(0.25))
	# Hairline highlight along the top of the fill.
	if _hp > 0.01:
		var hl := PackedVector2Array()
		for s in _samples(0.0, _hp * _path_len):
			hl.append(_point(s) + _tangent(s).rotated(PI * 0.5) * (HP_WIDTH * 0.25))
		_block.draw_polyline(hl, Color(1, 1, 1, 0.3), 1.0, true)
	# Quarter marks across the path.
	for i in range(1, 4):
		var s := _path_len * i / 4.0
		var n := _tangent(s).rotated(PI * 0.5) * (HP_WIDTH * 0.5 - 1.5)
		_block.draw_line(_point(s) - n, _point(s) + n, Color(0, 0, 0, 0.45), 1.0, true)

	# EN gauge.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	HudStyle.draw_gauge(_block, _en_bar, _en, _en_ghost, en_color, Color(0.8, 0.9, 1.0, 0.5))

	_draw_core()


# The round readout: dark glass disc, hairline rings, a spinning tick ring and the speed arc.
func _draw_core() -> void:
	var c := _c
	_block.draw_circle(c, CORE_RADIUS + 2.0, Color(0.0, 0.01, 0.03, 0.85))
	_block.draw_circle(c, CORE_RADIUS, HudStyle.PANEL_TOP.lerp(Color(0.05, 0.2, 0.3, 0.85), _over * 0.6))
	_block.draw_arc(c, CORE_RADIUS, 0.0, TAU, 64, HudStyle.PANEL_EDGE.lerp(Color(HudStyle.CYAN, 0.7), _over), 1.0, true)
	_block.draw_arc(c, CORE_RADIUS + 2.5, 0.0, TAU, 64, Color(HudStyle.CYAN, 0.35), 1.0, true)
	# Tick ring: spins faster the faster you go.
	for i in 24:
		var a := _spin + TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		var major := i % 6 == 0
		_block.draw_line(c + d * (CORE_RADIUS - (6.0 if major else 4.0)), c + d * (CORE_RADIUS - 2.0),
				Color(HudStyle.CYAN, (0.6 if major else 0.25) + 0.3 * _over), 1.0, true)
	# Speed arc: trough, fill, and a tick at normal top speed.
	var r := CORE_RADIUS - 10.0
	_block.draw_arc(c, r, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP, 48, Color(HudStyle.CYAN, 0.12), 3.0, true)
	if _speed_frac > 0.005:
		var col := HudStyle.CYAN.lerp(Color.WHITE, 0.5 * _over)
		_block.draw_arc(c, r, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP * _speed_frac, 48, col, 3.0, true)
	var ma := SPEED_ARC_START + SPEED_ARC_SWEEP * _MAX_FRAC
	var md := Vector2(cos(ma), sin(ma))
	_block.draw_line(c + md * (r - 4.0), c + md * (r + 4.0), Color(HudStyle.WHITE, 0.8), 1.5, true)


func _draw_glow() -> void:
	var breathe := (0.85 + 0.15 * sin(_time * 2.2)) * GLOW_STRENGTH
	var hp_color := _hp_color().lerp(Color.WHITE, _flash * 0.6)
	var k := breathe * (1.0 + _flash)
	var filled := _hp * _path_len
	# HP halo: wider, fainter copies of the path.
	for i in range(4, 0, -1):
		var col := Color(hp_color, 0.05 * k * (1.0 - i / 5.0))
		_strip(_glow, 0.0, filled, HP_WIDTH + i * 5.0, col, col)
	# Bright leading edge at the end of the fill.
	if filled > 0.5:
		var end_pt := _point(filled)
		for i in 4:
			_glow.draw_circle(end_pt, 3.0 + i * 3.0, Color(hp_color.lerp(Color.WHITE, 0.5), 0.14 * k / (i + 1)))
	# Sheen: a light band running along the whole filled path, arc included.
	var t := fposmod(_time / SHEEN_CYCLE, 1.0) * 1.4 - 0.2
	if t >= 0.0 and t <= 1.0 and filled > 1.0:
		var sc := t * filled
		for i in 4:
			var half := 4.0 + i * 6.0
			var col := Color(1, 1, 1, 0.08 * k / (i + 1))
			_strip(_glow, sc - half, minf(sc + half, filled), HP_WIDTH, col, col)
	# Heal flare over the regained stretch.
	if _heal > 0.0:
		var col := Color(1.0, 0.85, 0.8, 0.45 * _heal)
		_strip(_glow, _heal_from * _path_len, filled, HP_WIDTH + 4.0, col, col)
	# EN halo and sheen.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_BLUE
	var en_rect := Rect2(_en_bar.end.x - _en_bar.size.x * _en, _en_bar.position.y, _en_bar.size.x * _en, EN_HEIGHT)
	if _en > 0.005:
		en_rect.size.x = maxf(en_rect.size.x, EN_HEIGHT)
		en_rect.position.x = _en_bar.end.x - en_rect.size.x
		for i in range(4, 0, -1):
			_glow.draw_colored_polygon(HudStyle.rounded_points(en_rect.grow(i * 1.6), EN_HEIGHT * 0.5 + i * 1.6),
					Color(en_color, 0.05 * breathe * (1.0 - i / 5.0)))
		_bar_sheen(en_rect, 0.45, breathe * 0.8)
	# Speed arc glow, stronger past top speed.
	if _speed_frac > 0.005:
		_glow.draw_arc(_c, CORE_RADIUS - 10.0, SPEED_ARC_START, SPEED_ARC_START + SPEED_ARC_SWEEP * _speed_frac,
				48, Color(HudStyle.CYAN, (0.18 + 0.25 * _over) * breathe), 8.0, true)
	if _over > 0.0:
		_glow.draw_circle(_c, CORE_RADIUS, Color(HudStyle.CYAN, 0.08 * _over * breathe))


# A light band sliding right to left across a filled straight gauge.
func _bar_sheen(r: Rect2, phase: float, k: float) -> void:
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
