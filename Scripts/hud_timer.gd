# Mission clock, top center (see HudStyle): a block with 作戦時間 / MISSION TIME, big digits
# and fast-ticking hundredths, a heading tape under it that scrolls as you turn, and a line
# of system data. This script also draws the HOSTILE and SCRAP blocks in the top left that
# the enemy count (hud_enemy_count.gd) and scrap counter (hud_gold.gd) sit in: a filled
# kanji tag joined to an outlined field. Everything traces itself on when the level starts.
extends Label

const FONT_SIZE := 34
## Heading tape: size, and how many pixels one degree of heading takes.
const TAPE_SIZE := Vector2(300, 30)
const TAPE_PX_PER_DEG := 2.4
## Top-left blocks: the kanji tag's width, and where each row's field starts.
const TAG_W := 46.0
const FIELD_X := 50.0

var _last_second := -1
var _time_panel : Control
var _mission_panel : Control
var _tape : Control
var _hundredths : Label
var _data : Label
var _glint := 0.0
var _boot := 0.0
var _data_timer := 0.0

@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Clock block, top center.
	var w := HudStyle.TIME_SIZE.x
	_time_panel = _add_panel(HudStyle.TIME_SIZE, _draw_time_panel)
	_time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_panel.offset_left = -w * 0.5
	_time_panel.offset_right = w * 0.5
	_time_panel.offset_top = HudStyle.TIME_TOP
	_time_panel.offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y
	var kanji := HudStyle.make_kanji("作戦時間", 11, HudStyle.INK)
	kanji.position = Vector2(8, 0)
	_time_panel.add_child(kanji)
	var cap := HudStyle.make_label("MISSION TIME", 9, HudStyle.INK, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.position = Vector2(0, 1)
	cap.size = Vector2(w - 8, 12)
	_time_panel.add_child(cap)
	_hundredths = HudStyle.make_label(".00", 14, HudStyle.ORANGE, true)
	_hundredths.position = Vector2(w - 34, 27)
	_time_panel.add_child(_hundredths)

	# Heading tape, under the clock.
	_tape = _add_panel(TAPE_SIZE, _draw_tape)
	_tape.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tape.offset_left = -TAPE_SIZE.x * 0.5
	_tape.offset_right = TAPE_SIZE.x * 0.5
	_tape.offset_top = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y + 6
	_tape.offset_bottom = _tape.offset_top + TAPE_SIZE.y

	# HOSTILE and SCRAP blocks, top left.
	_mission_panel = _add_panel(HudStyle.MISSION_SIZE + Vector2(0, 14), _draw_mission_panel)
	_mission_panel.position = HudStyle.MISSION_POS
	for row in [[HudStyle.MISSION_ROW_HOSTILE, "敵影", "HOSTILE"], [HudStyle.MISSION_ROW_SCRAP, "資材", ""]]:
		var k := HudStyle.make_kanji(row[1], 13, HudStyle.INK)
		k.remove_theme_constant_override("outline_size")
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		k.position = Vector2(0, row[0] + 1)
		k.size = Vector2(TAG_W, 16)
		_mission_panel.add_child(k)
		if not String(row[2]).is_empty():
			var e := HudStyle.make_label(row[2], 8, HudStyle.INK, true)
			e.remove_theme_constant_override("outline_size")
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.position = Vector2(0, row[0] + 16)
			e.size = Vector2(TAG_W, 10)
			_mission_panel.add_child(e)
	# (The SCRAP caption belongs to hud_gold.gd, so it kicks along with the number.)
	_data = HudStyle.make_data("", 8)
	_data.position = Vector2(0, HudStyle.MISSION_SIZE.y + 2)
	_mission_panel.add_child(_data)
	_update_data()

	# The time itself, in its block.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -w * 0.5
	offset_right = w * 0.5 - 18
	offset_top = HudStyle.TIME_TOP + 13
	offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	HudStyle.add_phosphor(self, HudStyle.ORANGE_HOT)

	_update_text()

	# Boot-up: the blocks trace themselves on, then the text flickers in.
	var t := create_tween()
	t.tween_property(self, "_boot", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for c : CanvasItem in [self, _hundredths, _data]:
		c.modulate.a = 0.0
		var f := c.create_tween()
		f.tween_interval(0.45)
		f.tween_property(c, "modulate:a", 1.0, 0.04)
		f.tween_property(c, "modulate:a", 0.2, 0.05)
		f.tween_property(c, "modulate:a", 1.0, 0.06)


# A drawing surface added behind the readouts (under this label and its siblings).
func _add_panel(panel_size: Vector2, painter: Callable) -> Control:
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = panel_size
	panel.draw.connect(painter.bind(panel))
	get_parent().add_child.call_deferred(panel)
	get_parent().move_child.call_deferred(panel, get_index())
	return panel


func _draw_time_panel(panel: Control) -> void:
	var r := Rect2(Vector2.ZERO, panel.size)
	panel.draw_colored_polygon(HudStyle.chamfer_points(r, 10.0), HudStyle.HUD_BACKING)
	# Filled header strip, then the block outline.
	if _boot > 0.3:
		panel.draw_rect(Rect2(0, 0, r.size.x * smoothstep(0.3, 0.8, _boot), 14), HudStyle.ORANGE)
	HudStyle.draw_frame(panel, r, HudStyle.ORANGE, _boot, 2.0, 0.0, 10.0)
	HudStyle.draw_glint(panel, r, _glint)


func _draw_mission_panel(panel: Control) -> void:
	for row in [HudStyle.MISSION_ROW_HOSTILE, HudStyle.MISSION_ROW_SCRAP]:
		var h := HudStyle.MISSION_ROW_HEIGHT
		var tag := Rect2(0, row, TAG_W * _boot, h)
		panel.draw_rect(tag, HudStyle.ORANGE)
		var field := Rect2(FIELD_X, row, HudStyle.MISSION_SIZE.x - FIELD_X, h)
		panel.draw_colored_polygon(HudStyle.chamfer_points(field, 7.0), HudStyle.HUD_BACKING)
		HudStyle.draw_frame(panel, field, HudStyle.ORANGE, _boot, 2.0, 0.0, 7.0)


# The heading tape: ticks every 5 degrees, longer every 15, labels every 30 (N / E / S / W at
# the cardinals); the current heading sits in a box under a fixed caret in the middle.
func _draw_tape(panel: Control) -> void:
	var w := panel.size.x
	var mid := w * 0.5
	var base := 11.0
	var heading := _heading()
	var font := HudStyle.NUMBER_FONT
	panel.draw_line(Vector2(mid - w * 0.5 * _boot, base), Vector2(mid + w * 0.5 * _boot, base), Color(HudStyle.ORANGE, 0.8), 2.0)
	var deg := int(floor((heading - mid / TAPE_PX_PER_DEG) / 5.0)) * 5
	while true:
		var x := mid + (deg - heading) * TAPE_PX_PER_DEG
		if x > w:
			break
		if x >= 0.0:
			# Fades toward the ends, like the tape rolling off a drum.
			var edge := (1.0 - pow(absf(x - mid) / mid, 3.0)) * _boot
			var c := Color(HudStyle.ORANGE, edge)
			var d := posmod(deg, 360)
			var tick := 8.0 if d % 15 == 0 else 4.0
			panel.draw_line(Vector2(x, base), Vector2(x, base + tick), c, 1.5 if d % 15 == 0 else 1.0)
			if d % 30 == 0:
				var text : String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, "%02d" % (d / 10))
				var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				panel.draw_string(font, Vector2(x - tw * 0.5, base + 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)
		deg += 5
	# Caret and the heading in a filled box.
	var caret := Color(HudStyle.ORANGE_HOT, _boot)
	panel.draw_colored_polygon(PackedVector2Array([Vector2(mid - 5, base - 7), Vector2(mid + 5, base - 7), Vector2(mid, base)]), caret)
	var text := "%03d" % posmod(roundi(heading), 360)
	var box := Rect2(mid + 9, base - 11, 28, 13)
	panel.draw_rect(box, Color(HudStyle.ORANGE, _boot))
	panel.draw_string(font, Vector2(box.position.x + 4, box.end.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.INK)


# Compass heading of the view, in degrees (0 = north = -Z, increasing clockwise).
func _heading() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = get_tree().root.get_camera_3d()
	if cam == null:
		return 0.0
	var fwd := -cam.global_basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _process(delta: float) -> void:
	_tape.queue_redraw()
	if _boot < 1.0:
		_time_panel.queue_redraw()
		_mission_panel.queue_redraw()
	# Hundredths tick every frame; the rest only when the second changes.
	_hundredths.text = ".%02d" % (int(fmod(GameManager.levelTime, 1.0) * 100.0) % 100)
	if int(GameManager.levelTime) != _last_second:
		_update_text()
	_data_timer -= delta
	if _data_timer <= 0.0:
		_data_timer = 0.35
		_update_data()


# A line of system data under the top-left blocks (some of it drifting, for life).
func _update_data() -> void:
	var sync := 97.0 + 2.5 * sin(Time.get_ticks_msec() / 2300.0) + randf_range(-0.3, 0.3)
	_data.text = "LINK:OK  SYNC %.1f%%  CODE:%03d" % [sync, (Time.get_ticks_msec() / 1000) % 1000]


func _update_text() -> void:
	@warning_ignore("integer_division")
	var minute_turned := _last_second >= 0 and int(GameManager.levelTime) / 60 != _last_second / 60
	_last_second = int(GameManager.levelTime)
	# Each new minute: a scan line sweeps the block and the digits punch.
	if minute_turned:
		var t := create_tween()
		t.tween_method(func(v: float) -> void:
			_glint = v
			_time_panel.queue_redraw(), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		pivot_offset = size * 0.5
		UIJuice.punch(self, 0.15)
	@warning_ignore("integer_division")
	text = "%02d:%02d" % [_last_second / 60, _last_second % 60]
