# Weapon status stack down the left edge of the HUD (see HudStyle), like the numbered
# defence-line list on a NERV screen: one row per gun slot, angled as if it were on a side
# panel of the canopy.
#
#   [01] UL  RIFLE            ////////////////   24/30
#
# The number tag shows the slot's state: green = ready, amber = magazine low, red = reloading
# or empty (blinking RELOAD while the magazine refills, the bar filling back up). The
# gun's name is in its rarity color. Empty slots show a dim dashed row. Rows draw in one by
# one when the level starts.
class_name WeaponStack
extends Control

const ORIGIN := Vector2(18, 118)
const ROW_H := 22.0
const ROW_GAP := 5.0
const WIDTH := 210.0
const TAG_W := 24.0
## How much the panel leans (radians of skew) and how far each lower row steps right,
## together making it read as a tilted side display.
const SKEW := 0.0
const STEP_X := 0.0
## Below this fraction of the magazine, the row turns amber.
const LOW_AMMO := 0.25
## Most segments a magazine bar shows (big magazines share segments).
const MAX_SEGMENTS := 24

var _boot := 0.0
var _time := 0.0
var _reload_started := {}   # Gun -> msec when its reload began


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_property(self, "_boot", 1.0, 0.9)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _slots() -> Array:
	var player := GameManager.player
	if player == null:
		return []
	var order := [Player.Quadrant.UPPER_LEFT, Player.Quadrant.UPPER_RIGHT,
			Player.Quadrant.LOWER_LEFT, Player.Quadrant.LOWER_RIGHT]
	# Only slots holding a gun get a row (numbered by slot, so a gun keeps its number).
	var out := []
	var n := 0
	for q in order:
		for slot in player.get_quadrant_slots(q):
			n += 1
			if slot.get_child_count() > 0 and slot.get_child(0) is Gun:
				out.append([slot, q, n])
	return out


func _draw() -> void:
	var rows := _slots()
	if GameManager.player == null:
		return
	var font := HudStyle.NUMBER_FONT
	# Header: a filled WEAPONS tag and a rule.
	draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, SKEW, ORIGIN))
	var head := Rect2(0, -20, 62 * minf(_boot * 3.0, 1.0), 15)
	draw_rect(head, HudStyle.ORANGE)
	if _boot > 0.2:
		draw_string(font, Vector2(6, -8), "WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudStyle.INK)
		draw_line(Vector2(66, -12), Vector2(WIDTH * _boot, -12), Color(HudStyle.ORANGE, 0.7), 2.0)
	if rows.is_empty():
		_dashed(Rect2(0, 0, WIDTH * _boot, ROW_H), Color(HudStyle.ORANGE, 0.3))
		if fmod(_time, 1.0) < 0.6:
			draw_string(font, Vector2(8, 15), "NO ARMS MOUNTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(HudStyle.ORANGE, 0.5 * _boot))

	for i in rows.size():
		var appear := clampf(_boot * rows.size() * 1.4 - i, 0.0, 1.0)
		if appear <= 0.0:
			break
		var slot : Node3D = rows[i][0]
		var quadrant : int = rows[i][1]
		var number : int = rows[i][2]
		var y := i * (ROW_H + ROW_GAP)
		draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, SKEW, ORIGIN + Vector2(i * STEP_X, 0)))
		var row := Rect2(0, y, WIDTH * appear, ROW_H)
		var gun : Gun = slot.get_child(0) as Gun if slot.get_child_count() > 0 else null
		var code := _quadrant_code(quadrant)
		if gun == null:
			_dashed(row, Color(HudStyle.ORANGE, 0.3))
			draw_string(font, Vector2(6, y + 15), "%02d  %s  ----  EMPTY" % [number, code], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(HudStyle.ORANGE, 0.35 * appear))
			continue
		var mag := maxi(gun.get_mag_size(), 1)
		var shots := clampi(gun.shotsLeft, 0, mag)
		var frac := float(shots) / mag
		var status := HudStyle.GREEN
		var reloading := gun.reloading
		if reloading:
			if not _reload_started.has(gun):
				_reload_started[gun] = Time.get_ticks_msec()
			var dur := maxf(gun.get_reload_duration(), 0.01)
			frac = clampf((Time.get_ticks_msec() - _reload_started[gun]) / 1000.0 / dur, 0.0, 1.0)
			status = HudStyle.RED
		else:
			_reload_started.erase(gun)
			if shots == 0:
				status = HudStyle.RED
			elif frac <= LOW_AMMO:
				status = HudStyle.AMBER
		# Backing and frame.
		draw_rect(row, HudStyle.HUD_BACKING)
		draw_rect(row, Color(status, 0.8 * appear), false, 1.5)
		# Number tag.
		draw_rect(Rect2(0, y, TAG_W, ROW_H), status)
		draw_string(font, Vector2(3, y + 16), "%02d" % number, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HudStyle.INK)
		# Quadrant code and name.
		var rarity_color := Rarity.get_color(gun.get_rarity())
		if gun.get_rarity() >= Rarity.MYTHIC:
			rarity_color = Rarity.rainbow()
		draw_string(font, Vector2(TAG_W + 5, y + 15), code, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(HudStyle.ORANGE, appear))
		draw_string(font, Vector2(TAG_W + 24, y + 15), gun.get_display_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 74, 12,
				Color(rarity_color, appear))
		# Magazine bar of slanted segments (reloading: it fills back up, red).
		var bar := Rect2(122, y + 6, WIDTH - 122 - 36, ROW_H - 12)
		var count := mini(mag, MAX_SEGMENTS)
		var seg := bar.size.x / count
		for s in count:
			var lit := (s + 0.5) / count <= frac
			var c := status if lit else Color(status, 0.12)
			var x0 := bar.position.x + s * seg
			var x1 := x0 + seg - minf(1.5, seg * 0.3)
			var sl := 0.0   # square segments
			draw_colored_polygon(PackedVector2Array([Vector2(x0 + sl, bar.position.y), Vector2(x1, bar.position.y),
					Vector2(x1 - sl, bar.end.y), Vector2(x0, bar.end.y)]), Color(c, c.a * appear))
		# Count, or the reload alert.
		if reloading:
			if fmod(_time, 0.5) < 0.32:
				draw_string(font, Vector2(WIDTH - 36, y + 15), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudStyle.RED)
		else:
			draw_string(HudStyle.DATA_FONT, Vector2(WIDTH - 33, y + 14), "%02d/%02d" % [shots, mini(mag, 99)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(status, appear))
	draw_set_transform_matrix(Transform2D.IDENTITY)


static func _quadrant_code(q: int) -> String:
	return ["LR", "LL", "UR", "UL"][q]


func _dashed(r: Rect2, color: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a : Vector2 = pts[i]
		var b : Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var d := 0.0
		while d < len:
			draw_line(a.lerp(b, d / len), a.lerp(b, minf(d + 5.0, len) / len), color, 1.0)
			d += 9.0
