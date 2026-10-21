# Bottom-of-screen popup shown when the player picks up an item, in the style of KH2's
# "obtained" banners: a glossy blue command plate on a mech metal backing, with an
# "OBTAINED" tab on top. Icon on the left; name (tier colored) with description underneath.
# Slides in from the left with a little overshoot, then slides out to the right.
extends Control

const BOTTOM_PADDING := 150   # above the vitals cluster
const BOX_PADDING := 14
const ICON_DISPLAY_SIZE := 64     # 32x32 source at 2x keeps pixel art crisp
const ICON_TEXT_GAP := 14
const LINE_GAP := 4
const MAX_TEXT_WIDTH := 420.0     # description wraps beyond this
const FADE_IN := 0.15
const HOLD_TIME := 3.0
const FADE_OUT := 0.4

@export var name_font: Font
@export var description_font: Font
@export var name_font_size := 26
@export var description_font_size := 18
@export var description_color := Color(0.85, 0.85, 0.85)
@export var box_color := Color(0.06, 0.06, 0.06, 0.85)

var _root: CenterContainer
var _icon: TextureRect
var _name_label: Label
var _desc_label: Label
var _tween: Tween
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# CenterContainer shrinks its child to the minimum size and centers it,
	# so the box always hugs its content.
	_root = CenterContainer.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, BOTTOM_PADDING)
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.visible = false

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(BOX_PADDING)
	style.content_margin_left = BOX_PADDING + 6
	style.content_margin_right = BOX_PADDING + 10
	style.content_margin_top = BOX_PADDING + 4
	panel.add_theme_stylebox_override("panel", style)
	panel.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, panel.size)
		HudStyle.draw_backing(panel, r.grow(4.0))
		HudStyle.draw_plate(panel, Rect2(r.position + Vector2(2, 4), r.size - Vector2(4, 6)), HudStyle.PLATE_TOP,
				HudStyle.PLATE_BOTTOM, HudStyle.PLATE_RIM, 12.0)
		# "OBTAINED" tab sitting on the top edge.
		var tab := Rect2(14, -8, 92, 18)
		HudStyle.draw_plate(panel, tab, Color(1, 1, 1, 0.98), Color(0.75, 0.82, 0.95, 0.98), Color(0.1, 0.2, 0.45), 9.0)
		panel.draw_string(HudStyle.MENU_FONT, Vector2(tab.position.x, tab.end.y - 4.0), "OBTAINED!",
				HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 12, Color(0.08, 0.16, 0.42)))
	_root.add_child(panel)
	_panel = panel

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ICON_TEXT_GAP)
	panel.add_child(row)

	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.custom_minimum_size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)

	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_column.add_theme_constant_override("separation", LINE_GAP)
	row.add_child(text_column)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.add_theme_font_override("font", HudStyle.MENU_FONT)
	_name_label.add_theme_font_size_override("font_size", name_font_size)
	_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.1, 0.95))
	_name_label.add_theme_constant_override("outline_size", 6)
	text_column.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_override("font", HudStyle.LABEL_FONT)
	_desc_label.add_theme_font_size_override("font_size", description_font_size)
	_desc_label.add_theme_color_override("font_color", HudStyle.WHITE)
	_desc_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.1, 0.9))
	_desc_label.add_theme_constant_override("outline_size", 4)
	text_column.add_child(_desc_label)

	GameManager.item_picked_up.connect(show_item)


func show_item(item: ItemData) -> void:
	_icon.texture = item.icon
	_icon.visible = item.icon != null   # no icon assigned yet: just show the text

	var tier_color := item.get_tier_color()
	_name_label.add_theme_color_override("font_color", tier_color)
	TextGlow.set_text(_name_label, item.display_name, tier_color)
	Rarity.paint_tier(_name_label, item.tier)   # Legendary items shine
	_desc_label.text = item.description
	_desc_label.visible = not item.description.is_empty()

	# Size the text column to the longer line (capped), so short text gives a small box
	# and long descriptions wrap instead of stretching across the screen.
	var width := minf(maxf(_text_width(_name_label), _text_width(_desc_label)), MAX_TEXT_WIDTH)
	width = ceilf(width) + 2.0   # tiny slack so rounding never forces a wrap
	_name_label.custom_minimum_size.x = width
	_desc_label.custom_minimum_size.x = width

	# A new pickup replaces the current popup and restarts the timer.
	if _tween != null:
		_tween.kill()
	_root.modulate.a = 0.0
	_root.visible = true
	_root.scale = Vector2.ONE
	_panel.queue_redraw()
	_tween = create_tween()
	# Slides in from the left with an overshoot.
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_method(_slide, -140.0, 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if item.tier <= 2:
		UIJuice.flash(_name_label, 1.0, 0.5)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_method(_slide, 0.0, 120.0, FADE_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): _root.visible = false)


# Horizontal slide, through the offsets so the bottom anchoring is never disturbed.
func _slide(x: float) -> void:
	_root.offset_left = x
	_root.offset_right = x


func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
