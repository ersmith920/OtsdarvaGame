# Mission clock, top center, as a boxed readout in the HUD's vector style (see HudStyle),
# with a heading tape under it: a compass scale that scrolls as you turn, like a fighter
# HUD. This script also draws the block in the top left that the hostile count
# (hud_enemy_count.gd) and scrap counter (hud_gold.gd) sit in: a caption and a boxed field
# per row. The frames draw themselves on when the level starts.
extends Label

const FONT_SIZE := 26
## Heading tape: size, and how many pixels one degree of heading takes.
const TAPE_SIZE := Vector2(260, 30)
const TAPE_PX_PER_DEG := 2.2
## Where each row's boxed field starts in the top-left block.
const FIELD_X := 96.0

var _last_second := -1
var _time_panel : Control
var _mission_panel : Control
var _tape : Control
var _glint := 0.0
var _boot := 0.0

@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Clock, top center.
	var w := HudStyle.TIME_SIZE.x
	_time_panel = _add_panel(HudStyle.TIME_SIZE, _draw_time_panel)
	_time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_panel.offset_left = -w * 0.5
	_time_panel.offset_right = w * 0.5
	_time_panel.offset_top = HudStyle.TIME_TOP
	_time_panel.offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y
	var cap := HudStyle.make_caption("MISSION TIME", 9)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.position = Vector2(0, 3)
	cap.size = Vector2(w, 12)
	_time_panel.add_child(cap)

	# Heading tape, under the clock.
	_tape = _add_panel(TAPE_SIZE, _draw_tape)
	_tape.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tape.offset_left = -TAPE_SIZE.x * 0.5
	_tape.offset_right = TAPE_SIZE.x * 0.5
	_tape.offset_top = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y + 6
	_tape.offset_bottom = _tape.offset_top + TAPE_SIZE.y

	# Hostile and scrap block, top left.
	_mission_panel = _add_panel(HudStyle.MISSION_SIZE, _draw_mission_panel)
	_mission_panel.position = HudStyle.MISSION_POS
	var hostile := HudStyle.make_caption("HOSTILE", 10)
	hostile.position = Vector2(0, HudStyle.MISSION_ROW_HOSTILE + 5)
	_mission_panel.add_child(hostile)
	# (The SCRAP caption belongs to hud_gold.gd, so it kicks along with the number.)

	# The time itself, in its box.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = HudStyle.TIME_TOP + 13
	offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y - 2
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	HudStyle.add_phosphor(self, HudStyle.PHOSPHOR, 0.3)

	_update_text()

	# Boot-up: the frames trace themselves on, then the text flickers in.
	var t := create_tween()
	t.tween_property(self, "_boot", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for c : CanvasItem in [self, cap, hostile]:
		c.modulate.a = 0.0
		var f := c.create_tween()
		f.tween_interval(0.35)
		f.tween_property(c, "modulate:a", 1.0, 0.04)
		f.tween_property(c, "modulate:a", 0.3, 0.04)
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
	panel.draw_rect(r, HudStyle.HUD_BACKING)
	HudStyle.draw_frame(panel, r, HudStyle.FRAME, _boot, 1.0, 1.0)
	HudStyle.draw_glint(panel, r, _glint)


func _draw_mission_panel(panel: Control) -> void:
	for row in [HudStyle.MISSION_ROW_HOSTILE, HudStyle.MISSION_ROW_SCRAP]:
		var field := Rect2(FIELD_X, row, panel.size.x - FIELD_X, HudStyle.MISSION_ROW_HEIGHT)
		panel.draw_rect(field, HudStyle.HUD_BACKING)
		HudStyle.draw_frame(panel, field, HudStyle.FRAME, _boot, 1.0, 0.8)
		# A short tick joining the caption to its field.
		panel.draw_line(Vector2(FIELD_X - 8.0, field.get_center().y), Vector2(FIELD_X, field.get_center().y),
				Color(HudStyle.FRAME, 0.6 * _boot), 1.0)


# The heading tape: ticks every 5 degrees, longer every 15, labels every 30 (N / E / S / W at
# the cardinals); the current heading sits under a fixed caret in the middle.
func _draw_tape(panel: Control) -> void:
	var w := panel.size.x
	var mid := w * 0.5
	var base := 9.0
	var heading := _heading()
	var font := HudStyle.LABEL_FONT
	var dim := Color(HudStyle.PHOSPHOR, 0.55 * _boot)
	panel.draw_line(Vector2(mid - w * 0.5 * _boot, base), Vector2(mid + w * 0.5 * _boot, base), Color(HudStyle.FRAME, 0.5), 1.0)
	var first := int(floor((heading - mid / TAPE_PX_PER_DEG) / 5.0)) * 5
	var deg := first
	while true:
		var x := mid + (deg - heading) * TAPE_PX_PER_DEG
		if x > w:
			break
		if x >= 0.0:
			# Fade toward the ends, like the tape rolling off a drum.
			var edge := 1.0 - pow(absf(x - mid) / mid, 3.0)
			var c := Color(dim, dim.a * edge)
			var d := posmod(deg, 360)
			var tick := 7.0 if d % 15 == 0 else 3.0
			panel.draw_line(Vector2(x, base), Vector2(x, base + tick), c, 1.0)
			if d % 30 == 0:
				var text : String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, "%02d" % (d / 10))
				var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				panel.draw_string(font, Vector2(x - tw * 0.5, base + 19.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, c)
		deg += 5
	# Caret and the heading in a small box above it.
	var caret := Color(HudStyle.PHOSPHOR, _boot)
	panel.draw_colored_polygon(PackedVector2Array([Vector2(mid - 4, base - 5), Vector2(mid + 4, base - 5), Vector2(mid, base)]), caret)
	var text := "%03d" % posmod(roundi(heading), 360)
	var box := Rect2(mid + 8, base - 9, 26, 12)
	panel.draw_rect(box, HudStyle.HUD_BACKING)
	panel.draw_rect(box, Color(HudStyle.FRAME, 0.7 * _boot), false, 1.0)
	panel.draw_string(font, Vector2(box.position.x + 3, box.end.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, caret)


# Compass heading of the view, in degrees (0 = north = -Z, increasing clockwise).
func _heading() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var fwd := -cam.global_basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _process(_delta: float) -> void:
	_tape.queue_redraw()
	if _boot < 1.0:
		_time_panel.queue_redraw()
		_mission_panel.queue_redraw()
	# Only touch the text when the displayed second actually changes.
	if int(GameManager.levelTime) != _last_second:
		_update_text()


func _update_text() -> void:
	@warning_ignore("integer_division")
	var minute_turned := _last_second >= 0 and int(GameManager.levelTime) / 60 != _last_second / 60
	_last_second = int(GameManager.levelTime)
	# Each new minute: a scan line sweeps the box and the digits punch.
	if minute_turned:
		var t := create_tween()
		t.tween_method(func(v: float) -> void:
			_glint = v
			_time_panel.queue_redraw(), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		pivot_offset = size * 0.5
		UIJuice.punch(self, 0.15)
	@warning_ignore("integer_division")
	text = "%02d:%02d" % [_last_second / 60, _last_second % 60]
