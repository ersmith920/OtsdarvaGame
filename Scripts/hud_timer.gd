# Mission panel, top left of the HUD (see HudStyle): the run time as a big readout, with the
# hostile count and credits (gold) underneath. This script draws the panel and its captions
# and shows the time; the EnemyCount and Gold labels place themselves inside it.
extends Label

const FONT_SIZE := 26

var _last_second := -1
var _panel : Control

@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# The panel behind the time, hostiles and credits.
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = HudStyle.MISSION_POS
	_panel.size = HudStyle.MISSION_SIZE
	_panel.draw.connect(_draw_panel)
	get_parent().add_child.call_deferred(_panel)
	get_parent().move_child.call_deferred(_panel, get_index())   # drawn behind the readouts

	_panel.add_child(_caption("MISSION TIME", Vector2(14, 8)))
	_panel.add_child(_caption("HOSTILE", Vector2(14, HudStyle.MISSION_ROW_HOSTILE + 3)))
	_panel.add_child(_caption("CREDITS", Vector2(38, HudStyle.MISSION_ROW_CREDITS + 3)))

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = HudStyle.MISSION_POS + Vector2(12, 24)
	size = Vector2(HudStyle.MISSION_SIZE.x - 24, 34)
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", HudStyle.WHITE)
	add_theme_color_override("font_shadow_color", Color(HudStyle.CYAN, 0.35))
	add_theme_constant_override("shadow_offset_x", 0)
	add_theme_constant_override("shadow_offset_y", 0)
	add_theme_constant_override("shadow_outline_size", 6)   # soft cyan glow behind the digits

	_update_text()

	# Boot-up: the panel and readouts flicker on when the level starts.
	for c : CanvasItem in [_panel, self]:
		c.modulate.a = 0.0
		var t := c.create_tween()
		t.tween_interval(0.1)
		t.tween_property(c, "modulate:a", 1.0, 0.05)
		t.tween_property(c, "modulate:a", 0.3, 0.05)
		t.tween_property(c, "modulate:a", 1.0, 0.08)


func _caption(text: String, at: Vector2) -> Label:
	var l := HudStyle.make_label(HudStyle.caption(text), 10, HudStyle.CYAN_DIM)
	l.position = at
	return l


func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, HudStyle.MISSION_SIZE)
	HudStyle.draw_panel(_panel, r)
	# Divider under the time.
	var y := HudStyle.MISSION_ROW_HOSTILE - 6.0
	_panel.draw_line(Vector2(14, y), Vector2(r.size.x - 14, y), HudStyle.CYAN_FAINT, 1.0)
	_panel.draw_line(Vector2(14, y), Vector2(50, y), HudStyle.CYAN_DIM, 1.0)


func _process(_delta: float) -> void:
	# Only touch the text when the displayed second actually changes.
	if int(GameManager.levelTime) != _last_second:
		_update_text()


func _update_text() -> void:
	_last_second = int(GameManager.levelTime)
	@warning_ignore("integer_division")
	text = "%02d:%02d" % [_last_second / 60, _last_second % 60]
