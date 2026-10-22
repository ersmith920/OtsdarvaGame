# Mission clock, top center (see HudStyle): just the MM:SS digits standing on their own (no
# box; the display's bloom makes them glow), with a heading tape under them that scrolls as
# you turn. This script also draws the HOSTILE and SCRAP blocks in the top left that the enemy
# count (hud_enemy_count.gd) and scrap counter (hud_gold.gd) sit in: a filled tag joined to
# an outlined field, and a line of system data under them. Everything traces itself on when
# the level starts.
extends Label

const FONT_SIZE := 40
## Heading tape: size, and how many pixels one degree of heading takes.
const TAPE_SIZE := Vector2(300, 30)
const TAPE_PX_PER_DEG := 2.4
## Top-left blocks: the tag's width, and where each row's field starts.
const TAG_W := 58.0
const FIELD_X := 62.0
## Where each row's icon sits (the scrap coin, the hostile reticle), from the panel's left.
const ICON_X := 70.0

var _last_second := -1
var _mission_panel : Control
var _tape : Control
var _data : Label
var _boot := 0.0
var _data_timer := 0.0

@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var w := HudStyle.TIME_SIZE.x

	# Heading tape, under the clock.
	_tape = _add_panel(TAPE_SIZE, _draw_tape)
	_tape.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tape.offset_left = -TAPE_SIZE.x * 0.5
	_tape.offset_right = TAPE_SIZE.x * 0.5
	_tape.offset_top = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y + 2
	_tape.offset_bottom = _tape.offset_top + TAPE_SIZE.y

	# HOSTILE and SCRAP blocks, top left.
	_mission_panel = _add_panel(HudStyle.MISSION_SIZE + Vector2(0, 14), _draw_mission_panel)
	_mission_panel.position = HudStyle.MISSION_POS
	# The HOSTILE tag's word, in ink. (The SCRAP word belongs to hud_gold.gd, so it kicks
	# along with the number.)
	var e := HudStyle.make_label("HOSTILE", 12, HudStyle.INK, true)
	e.remove_theme_constant_override("outline_size")
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	e.position = Vector2(0, HudStyle.MISSION_ROW_HOSTILE)
	e.size = Vector2(TAG_W, HudStyle.MISSION_ROW_HEIGHT)
	_mission_panel.add_child(e)
	_data = HudStyle.make_data("", 8)
	_data.position = Vector2(0, HudStyle.MISSION_SIZE.y + 2)
	_mission_panel.add_child(_data)
	_update_data()

	# The time itself, standing on its own.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = HudStyle.TIME_TOP
	offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y
	add_theme_font_override("font", HudStyle.spaced(HudStyle.READOUT_FONT, 1))
	add_theme_font_size_override("font_size", FONT_SIZE)
	HudStyle.bolden(self, HudStyle.ORANGE_HOT, 2)

	_update_text()

	# Boot-up: the blocks trace themselves on, then the text flickers in.
	var t := create_tween()
	t.tween_property(self, "_boot", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for c : CanvasItem in [self, _data]:
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


func _draw_mission_panel(panel: Control) -> void:
	for row in [HudStyle.MISSION_ROW_HOSTILE, HudStyle.MISSION_ROW_SCRAP]:
		var h := HudStyle.MISSION_ROW_HEIGHT
		var tag := Rect2(0, row, TAG_W * _boot, h)
		panel.draw_rect(tag, HudStyle.ORANGE)
		var field := Rect2(FIELD_X, row, HudStyle.MISSION_SIZE.x - FIELD_X, h)
		panel.draw_colored_polygon(HudStyle.chamfer_points(field, 7.0), HudStyle.HUD_BACKING)
		HudStyle.draw_frame(panel, field, HudStyle.ORANGE, _boot, 2.0, 0.0, 7.0)
	# The HOSTILE row's icon, where the SCRAP row has its coin: a small target reticle.
	if _boot > 0.6:
		var c := Vector2(ICON_X + 8.0, HudStyle.MISSION_ROW_HOSTILE + HudStyle.MISSION_ROW_HEIGHT * 0.5)
		var col := Color(HudStyle.RED, smoothstep(0.6, 1.0, _boot))
		panel.draw_arc(c, 5.5, 0.0, TAU, 20, col, 1.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			panel.draw_line(c + d * 4.0, c + d * 8.5, col, 1.5)
		panel.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


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
				var tw := HudStyle.READOUT_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				panel.draw_string(HudStyle.READOUT_FONT, Vector2(x - tw * 0.5, base + 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		deg += 5
	# Caret and the heading in a filled box.
	var caret := Color(HudStyle.ORANGE_HOT, _boot)
	panel.draw_colored_polygon(PackedVector2Array([Vector2(mid - 5, base - 7), Vector2(mid + 5, base - 7), Vector2(mid, base)]), caret)
	var text := "%03d" % posmod(roundi(heading), 360)
	var box := Rect2(mid + 9, base - 11, 28, 13)
	panel.draw_rect(box, Color(HudStyle.ORANGE, _boot))
	panel.draw_string(HudStyle.READOUT_FONT, Vector2(box.position.x + 3, box.end.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HudStyle.INK)


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
		_mission_panel.queue_redraw()
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
	# Each new minute: the digits punch.
	if minute_turned:
		pivot_offset = size * 0.5
		UIJuice.punch(self, 0.15)
	@warning_ignore("integer_division")
	text = "%02d:%02d" % [_last_second / 60, _last_second % 60]
