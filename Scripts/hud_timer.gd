# Run timer, top center of the HUD, on its own panel (see HudStyle). This script also draws
# the panel in the top left that the hostile count (hud_enemy_count.gd) and scrap counter
# (hud_gold.gd) sit on.
extends Label

const FONT_SIZE := 24

var _last_second := -1
var _time_panel : Control
var _mission_panel : Control
var _glint := 0.0

@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Timer panel, top center.
	var w := HudStyle.TIME_SIZE.x
	_time_panel = _make_panel(HudStyle.TIME_SIZE, false)
	_time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_panel.offset_left = -w * 0.5
	_time_panel.offset_right = w * 0.5
	_time_panel.offset_top = HudStyle.TIME_TOP
	_time_panel.offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y
	var cap := _caption("MISSION TIME", Vector2.ZERO)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.position = Vector2(0, 5)
	cap.size = Vector2(w, 14)
	_time_panel.add_child(cap)

	# Mission panel, top left: hostiles and scrap.
	_mission_panel = _make_panel(HudStyle.MISSION_SIZE, true)
	_mission_panel.position = HudStyle.MISSION_POS
	_mission_panel.add_child(_caption("HOSTILE", Vector2(14, HudStyle.MISSION_ROW_HOSTILE + 8)))
	_mission_panel.add_child(_caption("SCRAP", Vector2(38, HudStyle.MISSION_ROW_SCRAP + 8)))

	# The time itself, centered in its panel.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = HudStyle.TIME_TOP + 16
	offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y - 2
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", HudStyle.WHITE)
	add_theme_color_override("font_shadow_color", Color(HudStyle.CYAN, 0.25))
	add_theme_constant_override("shadow_offset_x", 0)
	add_theme_constant_override("shadow_offset_y", 0)
	add_theme_constant_override("shadow_outline_size", 8)   # soft glow behind the digits
	add_theme_color_override("font_outline_color", Color(HudStyle.SHADOW, 0.8))
	add_theme_constant_override("outline_size", 3)

	_update_text()

	# Boot-up: the panels and readout flicker on when the level starts.
	for c : CanvasItem in [_time_panel, _mission_panel, self]:
		c.modulate.a = 0.0
		var t := c.create_tween()
		t.tween_interval(0.1)
		t.tween_property(c, "modulate:a", 1.0, 0.05)
		t.tween_property(c, "modulate:a", 0.3, 0.05)
		t.tween_property(c, "modulate:a", 1.0, 0.08)


# A HUD panel added behind the readouts (drawn under this label and its siblings).
# divided: a hairline between the hostile and scrap rows.
func _make_panel(panel_size: Vector2, divided: bool) -> Control:
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = panel_size
	panel.draw.connect(func() -> void:
		HudStyle.draw_panel(panel, Rect2(Vector2.ZERO, panel_size))
		if not divided:
			HudStyle.draw_glint(panel, Rect2(Vector2.ZERO, panel_size), _glint)
		if divided:
			HudStyle.draw_divider(panel, Vector2(10, HudStyle.MISSION_ROW_SCRAP - 1), panel_size.x - 20))
	get_parent().add_child.call_deferred(panel)
	get_parent().move_child.call_deferred(panel, get_index())
	return panel


func _caption(text: String, at: Vector2) -> Label:
	var l := HudStyle.make_caption(text, 10)
	l.position = at
	return l


func _process(_delta: float) -> void:
	# Only touch the text when the displayed second actually changes.
	if int(GameManager.levelTime) != _last_second:
		_update_text()


func _update_text() -> void:
	@warning_ignore("integer_division")
	var minute_turned := _last_second >= 0 and int(GameManager.levelTime) / 60 != _last_second / 60
	_last_second = int(GameManager.levelTime)
	# Each new minute: a glint across the panel and a little punch on the digits.
	if minute_turned:
		var t := create_tween()
		t.tween_method(func(v: float) -> void:
			_glint = v
			_time_panel.queue_redraw(), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		pivot_offset = size * 0.5
		UIJuice.punch(self, 0.15)
	@warning_ignore("integer_division")
	text = "%02d:%02d" % [_last_second / 60, _last_second % 60]
