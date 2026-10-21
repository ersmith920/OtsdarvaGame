# Bottom-of-screen popup shown when the player picks up an item.
# Icon on the left; name (tier colored) with description underneath on the right.
extends Control

const BOTTOM_PADDING := 48
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
	var style := StyleBoxFlat.new()
	style.bg_color = box_color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(BOX_PADDING)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

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
	if name_font != null:
		_name_label.add_theme_font_override("font", name_font)
	_name_label.add_theme_font_size_override("font_size", name_font_size)
	text_column.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if description_font != null:
		_desc_label.add_theme_font_override("font", description_font)
	_desc_label.add_theme_font_size_override("font_size", description_font_size)
	_desc_label.add_theme_color_override("font_color", description_color)
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
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func(): _root.visible = false)


func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
