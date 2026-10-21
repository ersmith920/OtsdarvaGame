# Builds the content of one gun card for the ChoicePopup:
#   spinning model preview / gun name (bold, glowing in its rarity color) / rarity / one row per rolled stat
class_name GunCard
extends RefCounted

const NAME_FONT := preload("res://Fonts/KHMenu-Bold.otf")
const BODY_FONT := preload("res://Fonts/KHMenu.otf")
const NAME_SIZE := 26
const RARITY_SIZE := 17
const STAT_SIZE := 18
const PREVIEW_PX := Vector2i(268, 200)
const STAT_COLOR := Color(0.88, 0.9, 0.92)
const NO_ROLLS_COLOR := Color(0.6, 0.6, 0.6)


## scene: the gun's .tscn. gun: an instance of it (needed for its name; doesn't need to be in the tree).
static func build(scene: PackedScene, gun: Gun) -> Control:
	var roll := gun.roll
	var color := roll.get_color() if roll != null else Rarity.get_color(Rarity.COMMON)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.set_meta(&"color", color)   # the popup colors the card frame with this

	column.add_child(GunPreview.create(scene, PREVIEW_PX, 0.6))

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", NAME_FONT)
	name_label.add_theme_font_size_override("font_size", NAME_SIZE)
	column.add_child(name_label)
	TextGlow.set_text(name_label, gun.get_display_name(), color)

	var rarity_label := Label.new()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.text = roll.get_rarity_name() if roll != null else "Common"
	rarity_label.add_theme_font_override("font", BODY_FONT)
	rarity_label.add_theme_font_size_override("font_size", RARITY_SIZE)
	rarity_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	column.add_child(rarity_label)

	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 10)
	column.add_child(divider)

	var lines := roll.describe() if roll != null else PackedStringArray()
	if lines.is_empty():
		column.add_child(_stat_row("No bonuses", NO_ROLLS_COLOR))
	for line in lines:
		column.add_child(_stat_row(line, STAT_COLOR))
	return column


static func _stat_row(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", STAT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label
