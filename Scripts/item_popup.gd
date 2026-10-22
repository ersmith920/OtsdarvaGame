# Popup shown in the top right when the player picks up an item, in the HUD's vector style
# (see HudStyle): a framed box in the item's tier color topped by an inverted strip
# ("ITEM ACQUIRED", tier on the right, a blinking cursor), then the icon, the name (flickers
# on) and the description (types itself out). Slides in from the right edge, a scan line
# sweeps it, holds, then it slides back out. The rarity chime plays with it.
extends Control

const MARGIN := 14                # from the top and right screen edges
const BOX_PADDING := 12
const ICON_DISPLAY_SIZE := 48
const ICON_TEXT_GAP := 12
const LINE_GAP := 2
const MAX_TEXT_WIDTH := 300.0     # description wraps beyond this
const NAME_SIZE := 20
const DESCRIPTION_SIZE := 13
const SLIDE := 160.0              # how far it slides in from
const FADE_IN := 0.15
const HOLD_TIME := 3.0
const FADE_OUT := 0.35

# Unused now: the popup uses HudStyle's fonts and sizes (kept so the scene still loads).
@export var name_font: Font
@export var description_font: Font
@export var name_font_size := 26
@export var description_font_size := 18
@export var description_color := Color(0.85, 0.85, 0.85)
@export var box_color := Color(0.06, 0.06, 0.06, 0.85)

var _root: HBoxContainer
var _icon: TextureRect
var _name_label: Label
var _desc_label: Label
var _tween: Tween
var _panel: PanelContainer
var _accent := HudStyle.CYAN
var _glint := 0.0
var _caption : Label
var _tier_label : Label
var _header : PanelContainer
var _header_fill : StyleBoxFlat
var _blink : Tween
const CAPTION := "ITEM ACQUIRED"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A right-aligned row across the top, so the box hugs its content against the right edge.
	_root = HBoxContainer.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.alignment = BoxContainer.ALIGNMENT_END
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.offset_top = MARGIN
	_root.offset_left = 0
	_root.offset_right = -MARGIN
	_root.visible = false

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, panel.size)
		panel.draw_rect(r, Color(0.0, 0.025, 0.03, 0.8))
		HudStyle.draw_frame(panel, r, _accent, 1.0, 1.0, 1.2)
		HudStyle.draw_glint(panel, r, _glint, 1.2))
	_root.add_child(panel)
	_panel = panel

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	panel.add_child(stack)

	# Header: an inverted strip in the item's tier color, "ITEM ACQUIRED" left, tier right.
	_header = PanelContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_fill = StyleBoxFlat.new()
	_header_fill.content_margin_left = 8
	_header_fill.content_margin_right = 8
	_header_fill.content_margin_top = 1
	_header_fill.content_margin_bottom = 1
	_header.add_theme_stylebox_override("panel", _header_fill)
	stack.add_child(_header)
	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(header_row)
	_caption = HudStyle.make_label(CAPTION + "_", 10, HudStyle.INK)
	_caption.remove_theme_constant_override("outline_size")
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_caption)
	_tier_label = HudStyle.make_label("", 10, HudStyle.INK)
	_tier_label.remove_theme_constant_override("outline_size")
	header_row.add_child(_tier_label)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, BOX_PADDING - 2)
	pad.add_theme_constant_override("margin_left", BOX_PADDING)
	pad.add_theme_constant_override("margin_right", BOX_PADDING + 4)
	stack.add_child(pad)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ICON_TEXT_GAP)
	pad.add_child(row)

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

	_name_label = HudStyle.make_label("", NAME_SIZE, HudStyle.WHITE, true)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(_name_label)

	_desc_label = HudStyle.make_label("", DESCRIPTION_SIZE, Color(HudStyle.WHITE, 0.85))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(_desc_label)

	GameManager.item_picked_up.connect(show_item)
	UIJuice.warm_chimes()


func show_item(item: ItemData) -> void:
	_icon.texture = item.icon
	_icon.visible = item.icon != null   # no icon assigned yet: just show the text

	var tier_color := item.get_tier_color()
	_accent = tier_color
	_header_fill.bg_color = tier_color
	_tier_label.text = Rarity.name_of(Rarity.from_tier(item.tier)).to_upper()
	Rarity.paint_tier(_header, item.tier)   # Legendary shine / Mythic rainbow on the strip
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
	_panel.queue_redraw()
	_tween = create_tween()
	# Slides in from the right edge and settles.
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_method(_slide, SLIDE, 0.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Terminal feel: the name flickers on, the description types itself out, and a cursor
	# blinks after the caption.
	var flick := create_tween()
	_name_label.modulate.a = 0.0
	flick.tween_interval(0.12)
	for a in [1.0, 0.2, 1.0, 0.5, 1.0]:
		flick.tween_property(_name_label, "modulate:a", a, 0.04)
	_desc_label.visible_ratio = 0.0
	var typing := create_tween()
	typing.tween_interval(0.25)
	typing.tween_property(_desc_label, "visible_ratio", 1.0, clampf(item.description.length() * 0.012, 0.15, 0.8))
	if _blink != null:
		_blink.kill()
	_blink = create_tween().set_loops(int((HOLD_TIME + 1.0) / 0.8))
	_blink.tween_callback(func() -> void: _caption.text = CAPTION + "_")
	_blink.tween_interval(0.4)
	_blink.tween_callback(func() -> void: _caption.text = CAPTION + " ")
	_blink.tween_interval(0.4)
	# A scan line sweeps down the panel as it lands, and the icon pops.
	var fx := create_tween()
	fx.tween_interval(0.15)
	fx.tween_method(func(v: float) -> void:
		_glint = v
		_panel.queue_redraw(), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_icon.pivot_offset = _icon.custom_minimum_size * 0.5
	UIJuice.pop_in(_icon, 0.12, 0.6)
	UIJuice.play_chime(Rarity.from_tier(item.tier))
	if item.tier <= 2:
		UIJuice.flash(_name_label, 1.0, 0.5)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_method(_slide, 0.0, SLIDE, FADE_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): _root.visible = false)


# Horizontal slide, through the offsets so the anchoring is never disturbed.
func _slide(x: float) -> void:
	_root.offset_left = x
	_root.offset_right = -MARGIN + x


func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
