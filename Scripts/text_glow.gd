# Fakes an emissive neon glow on a Label: a whitened text core plus stacked, additive,
# tier-tinted outlines behind it. The inner layers lean white, the outer ones stay colored.
class_name TextGlow
extends RefCounted

## 0 = text stays the tier color, 1 = pure white.
const CORE_WHITEN := 0.7

## Extra space between letters, as a fraction of the font size (it's rounded to whole pixels).
const LETTER_SPACING := 0.1

## [outline thickness in px, opacity, whiten toward white], outer soft halo to tight inner core.
const LAYERS := [
	[18, 0.07, 0.0],
	[11, 0.14, 0.0],
	[6, 0.28, 0.2],
	[3, 0.45, 0.55],
	[1, 0.60, 0.85],
]

static var _additive: CanvasItemMaterial


## Sets the label's text and tints its glow. Use this instead of `label.text = ...`.
static func set_text(label: Label, text: String, color: Color, strength := 1.0) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color.lerp(Color.WHITE, CORE_WHITEN))
	var glows: Array = label.get_meta(&"glow_layers") if label.has_meta(&"glow_layers") else _build(label)
	for i in glows.size():
		var glow := glows[i] as Label
		glow.text = text
		var tint := color.lerp(Color.WHITE, LAYERS[i][2])
		glow.add_theme_color_override("font_outline_color", Color(tint, minf(LAYERS[i][1] * strength, 1.0)))


static func _build(label: Label) -> Array:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# One spaced font shared by the label and its glow layers, so they stay aligned.
	var font_size := label.get_theme_font_size("font_size")
	var spaced := FontVariation.new()
	spaced.base_font = label.get_theme_font("font")
	spaced.spacing_glyph = roundi(font_size * LETTER_SPACING)
	label.add_theme_font_override("font", spaced)

	var glows: Array = []
	for layer in LAYERS:
		var glow := Label.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.show_behind_parent = true
		glow.material = _additive
		glow.horizontal_alignment = label.horizontal_alignment
		glow.vertical_alignment = label.vertical_alignment
		glow.autowrap_mode = label.autowrap_mode
		glow.add_theme_font_override("font", spaced)
		glow.add_theme_font_size_override("font_size", font_size)
		glow.add_theme_font_size_override("font_size", label.get_theme_font_size("font_size"))
		glow.add_theme_color_override("font_color", Color(0, 0, 0, 0))   # only the halo is drawn
		glow.add_theme_constant_override("outline_size", layer[0])
		label.add_child(glow)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glows.append(glow)
	label.set_meta(&"glow_layers", glows)
	return glows
