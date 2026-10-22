# Run timer, top center of the HUD, on its own panel (see HudStyle). This script also draws
# the panel in the top left that the hostile count (hud_enemy_count.gd) and scrap counter
# (hud_gold.gd) sit on.
extends Label

const FONT_SIZE := 34

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
	# (The SCRAP caption belongs to hud_gold.gd, so it kicks along with the number.)

	# The time itself, centered in its panel.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = HudStyle.TIME_TOP + 16
	offset_bottom = HudStyle.TIME_TOP + HudStyle.TIME_SIZE.y - 2
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	HudStyle.add_phosphor(self, HudStyle.WHITE, 0.35)   # soft phosphor glow behind the digits

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
			HudStyle.draw_divider(panel, Vector2(10, HudStyle.MISSION_ROW_SCRAP - 1), panel_size.x - 20)
			# Dotted leaders from each caption toward its number, like a printed readout.
			_leader(panel, 68.0, 128.0, HudStyle.MISSION_ROW_HOSTILE + HudStyle.MISSION_ROW_HEIGHT * 0.5 + 3.0)
			_leader(panel, 82.0, 104.0, HudStyle.MISSION_ROW_SCRAP + HudStyle.MISSION_ROW_HEIGHT * 0.5 + 3.0))
	get_parent().add_child.call_deferred(panel)
	get_parent().move_child.call_deferred(panel, get_index())
	return panel


func _leader(ci: CanvasItem, x0: float, x1: float, y: float) -> void:
	var x := x0
	while x < x1:
		ci.draw_rect(Rect2(x, y, 1.0, 1.0), Color(HudStyle.PHOSPHOR, 0.35))
		x += 4.0


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
