# Vitals, bottom right: an instrument cluster in the HUD's vector style (see HudStyle).
#
#                          .----.
#                        ( dial )|       the HP bar graph comes out from underneath the speed
#   HP ||||||||||||||||||'-----'/        dial, running left; the other end wraps up the
#   EN |||||||||||||||||||||||           dial's right side, as one path of segments drawn
#                                        between two thin guide lines
#
# The dial is an analog speedometer: a glowing needle over a tick scale (the amber tick is
# normal top speed) with a digital readout (engine m/s x SPEED_DISPLAY_SCALE).
# Feel: the frames draw themselves on when the level starts and the HP gauge fills along its
# path. Damage comes off the far (left) end first, leaving a pale trail that drains a moment
# later; the gauge flashes and the cluster jolts on hits. Healing flares the regained
# stretch. Health turns amber at half and red below LOW, with a blinking warning.
# Also adds HudMotion to the HUD layer (the projected-glass sway).
extends Control

const PADDING := 12
const BLOCK_SIZE := Vector2(440, 146)
## The core (the round readout the HP gauge wraps around).
const CORE_RADIUS := 44.0
const RING_RADIUS := 56.0
const HP_WIDTH := 9.0
## Length of one HP segment along the path (including its gap) and the gap, in pixels.
const HP_SEGMENT := 7.0
const HP_GAP := 2.0
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
## Health turns amber below this fraction.
const CAUTION := 0.5
## Glow brightness (0 = none).
const GLOW_STRENGTH := 0.9
## The speed arc is full at this multiple of the player's move speed (the tick on the arc
## marks normal top speed).
const SPEED_ARC_MAX := 2.0
## The speed arc: starts bottom left and sweeps clockwise this far.
const SPEED_ARC_START := PI * 0.8
const SPEED_ARC_SWEEP := PI * 1.4
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
var _boot := 0.0              # 0-1 while the frames draw on at level start
var _speed := 0.0             # shown speed (smoothed)
var _speed_frac := 0.0        # speed / (move speed * SPEED_ARC_MAX)
var _over := 0.0              # 0-1, how far past normal top speed
const _MAX_FRAC := 1.0 / SPEED_ARC_MAX

var _c := Vector2(BLOCK_SIZE.x - 70, BLOCK_SIZE.y - 84)   # core center
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
	# The HUD layer trails the view like a projected display.
	if get_parent() is CanvasLayer:
		get_parent().add_child.call_deferred(HudMotion.new())

	# Speed in the core: the number, "M/S" under it.
	_speed_num = HudStyle.make_label("0", 20, HudStyle.PHOSPHOR, true)
	_speed_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# In the wedge at the bottom of the dial, which the needle never sweeps through.
	_speed_num.position = _c + Vector2(-30, 7)
	_speed_num.size = Vector2(60, 22)
	_speed_num.pivot_offset = _speed_num.size * 0.5
	_block.add_child(_speed_num)
	var unit := HudStyle.make_caption("M/S", 8)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.position = _c + Vector2(-30, 30)
	unit.size = Vector2(60, 10)
	_block.add_child(unit)

	# Tags at the left ends of the gauges.
	var hp_tag := HudStyle.make_caption("HP", 11)
	hp_tag.position = Vector2(_bar_left - 30, _bar_y - 8)
	_block.add_child(hp_tag)
	_en_tag = HudStyle.make_caption("EN", 11)
	_en_tag.position = Vector2(_bar_left - 30, _en_bar.get_center().y - 8)
	_block.add_child(_en_tag)

	_critical = HudStyle.make_label("HEALTH CRITICAL", 11, HudStyle.RED, true)
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
	t.parallel().tween_property(self, "_boot", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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
	_speed_num.text = "%03d" % roundi(_speed * SPEED_DISPLAY_SCALE)
	HudStyle.add_phosphor(_speed_num, HudStyle.PHOSPHOR.lerp(HudStyle.AMBER, _over * 0.8), 0.3 + 0.3 * _over)
	_speed_num.scale = Vector2.ONE * (1.0 + 0.1 * _over)

	var low_en := en < 0.2
	_en_tag.add_theme_color_override("font_color", HudStyle.AMBER if low_en and fmod(_time, 0.5) < 0.3 else HudStyle.CYAN_DIM)
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
		return HudStyle.RED.lerp(Color(1, 0.62, 0.55), 0.5 + 0.5 * sin(_time * TAU * 1.6))
	if _hp <= CAUTION:
		return HudStyle.AMBER
	return HudStyle.HP_COLOR


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
func _strip(ci: CanvasItem, s0: float, s1: float, width: float, outer: Color, inner: Color,
		caps := true) -> void:
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
	if caps:
		_cap(pts, cols, s1, half, 1.0, outer, inner)
	for i in range(inner_pts.size() - 1, -1, -1):
		pts.append(inner_pts[i])
		cols.append(inner)
	if caps:
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
	# Guide lines along both edges of the HP path (drawn on at boot), no filled trough.
	var reach := _path_len * _boot
	for side in [-1.0, 1.0]:
		var line := PackedVector2Array()
		for sv in _samples(0.0, reach):
			line.append(_point(sv) + _tangent(sv).rotated(PI * 0.5) * side * (HP_WIDTH * 0.5 + 2.5))
		if line.size() > 1:
			_block.draw_polyline(line, Color(HudStyle.FRAME, 0.45), 1.0, true)

	# HP segments: lit up to the fill, the pale trail after that, faint beyond.
	var col := _hp_color().lerp(Color.WHITE, _flash * 0.6)
	var count := maxi(roundi(_path_len / HP_SEGMENT), 1)
	var seg := _path_len / count
	for i in count:
		var s0 := i * seg + HP_GAP * 0.5
		var s1 := (i + 1) * seg - HP_GAP * 0.5
		var mid := (i + 0.5) * seg
		var c := Color(col, 0.07)
		if mid <= _hp * _path_len:
			c = col
		elif mid <= _hp_ghost * _path_len:
			c = HudStyle.TRAIL
		_strip(_block, s0, s1, HP_WIDTH, c, c, false)

	# EN bar graph.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_COLOR
	HudStyle.draw_gauge(_block, _en_bar, _en, _en_ghost, en_color, Color(0.8, 1.0, 0.9, 0.5), true, 5.0)

	_draw_core()


# The speed dial: a thin ring (drawn on at boot) over a faint backing, a tick scale along the
# needle's sweep (amber tick = normal top speed), and the needle on a small hub.
func _draw_core() -> void:
	var c := _c
	var green := HudStyle.PHOSPHOR
	_block.draw_circle(c, CORE_RADIUS, HudStyle.HUD_BACKING)
	var ring_to := -PI * 0.5 + TAU * _boot
	for g in [[7.0, 0.05], [3.5, 0.1]]:
		_block.draw_arc(c, CORE_RADIUS, -PI * 0.5, ring_to, 72, Color(HudStyle.FRAME, g[1]), 1.0 + g[0], true)
	_block.draw_arc(c, CORE_RADIUS, -PI * 0.5, ring_to, 72, HudStyle.FRAME, 1.0, true)
	# Tick scale (lit up to the current speed).
	var r := CORE_RADIUS - 5.0
	for i in 29:
		var f := i / 28.0
		if f > _boot:
			break
		var a := SPEED_ARC_START + SPEED_ARC_SWEEP * f
		var d := Vector2(cos(a), sin(a))
		var major := i % 7 == 0
		var lit := f <= _speed_frac
		_block.draw_line(c + d * (r - (6.0 if major else 3.0)), c + d * r,
				Color(green, (0.95 if lit else 0.45) if major else (0.8 if lit else 0.22)), 1.0, true)
	var ma := SPEED_ARC_START + SPEED_ARC_SWEEP * _MAX_FRAC
	var md := Vector2(cos(ma), sin(ma))
	_block.draw_line(c + md * (r - 8.0), c + md * (r + 1.0), HudStyle.AMBER, 1.5, true)
	# Needle (shivers a little past top speed) with its glow, and the hub.
	var na := SPEED_ARC_START + SPEED_ARC_SWEEP * _speed_frac + sin(_time * 40.0) * 0.02 * _over
	var nd := Vector2(cos(na), sin(na))
	var needle := HudStyle.PHOSPHOR.lerp(HudStyle.AMBER, _over)
	HudStyle.draw_glow_line(_block, c, c + nd * (r - 2.0), needle, 1.5, 1.0 + _over)
	_block.draw_circle(c, 2.5, needle)


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
	# Heal flare over the regained stretch.
	if _heal > 0.0:
		var col := Color(1.0, 0.85, 0.8, 0.45 * _heal)
		_strip(_glow, _heal_from * _path_len, filled, HP_WIDTH + 4.0, col, col)
	# EN halo and sheen.
	var en_color := HudStyle.AMBER if _en < 0.2 else HudStyle.EN_COLOR
	var en_rect := Rect2(_en_bar.end.x - _en_bar.size.x * _en, _en_bar.position.y, _en_bar.size.x * _en, EN_HEIGHT)
	if _en > 0.005:
		en_rect.size.x = maxf(en_rect.size.x, EN_HEIGHT)
		en_rect.position.x = _en_bar.end.x - en_rect.size.x
		for i in range(3, 0, -1):
			_glow.draw_rect(en_rect.grow(i * 1.6), Color(en_color, 0.04 * breathe * (1.0 - i / 4.0)))
	# The face warms to amber past top speed.
	if _over > 0.0:
		_glow.draw_circle(_c, CORE_RADIUS, Color(HudStyle.AMBER, 0.06 * _over * breathe))
