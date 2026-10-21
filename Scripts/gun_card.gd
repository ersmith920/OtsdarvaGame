# Builds the content of one gun card (gun store, Combiner):
#   spinning model preview / gun name (bold, glowing in its rarity color) / rarity /
#   the gun's stats with its rolls applied (rolled ones lit up, with the roll beside them)
#
# Every card is exactly SIZE, whatever the gun: the stat area always has room for the most
# lines any gun can show, so cards line up and nothing moves when the options change
# (rerolls, Combiner picks). A stat line too wide for the card shrinks its text to fit.
class_name GunCard
extends RefCounted

const NAME_FONT := preload("res://Fonts/KHMenu-Bold.otf")
const BODY_FONT := preload("res://Fonts/KHMenu.otf")
const NAME_SIZE := 26
const RARITY_SIZE := 17
const STAT_SIZE := 16
## Smallest a stat line's text shrinks to when it doesn't fit the card's width.
const MIN_STAT_SIZE := 11
## Width of every card's content (the frame around it adds its own padding).
const WIDTH := 290.0
const PREVIEW_PX := Vector2i(290, 150)
## Most stat lines a card can show (every stat a gun can have, plus the note line).
const MAX_STAT_LINES := 14
const STAT_LINE_GAP := 2
const STAT_COLOR := Color(0.88, 0.9, 0.92)
## Stats the gun didn't roll a bonus on.
const BASE_STAT_COLOR := Color(0.62, 0.64, 0.68)
const NO_ROLLS_COLOR := Color(0.6, 0.6, 0.6)


## The size every card's content is (and what frames should hold, plus their padding).
static func get_size() -> Vector2:
	var line := BODY_FONT.get_height(STAT_SIZE) + STAT_LINE_GAP
	var height := PREVIEW_PX.y + NAME_FONT.get_height(NAME_SIZE) + BODY_FONT.get_height(RARITY_SIZE) \
			+ 12.0 + MAX_STAT_LINES * line + 4 * 6.0   # 12 = divider, 6 = gaps between parts
	return Vector2(WIDTH, ceilf(height))


## scene: the gun's .tscn. gun: an instance of it (needed for its name; doesn't need to be in the tree).
## note: an extra line under the stats (the Combiner uses it for "+ 1 random new stat").
static func build(scene: PackedScene, gun: Gun, note := "") -> Control:
	var roll := gun.roll
	var rarity := gun.get_rarity()
	var color := Rarity.get_color(rarity)

	var column := VBoxContainer.new()
	column.custom_minimum_size = get_size()
	column.add_theme_constant_override("separation", 6)
	column.set_meta(&"color", color)   # the popup colors the card frame with this
	column.set_meta(&"rarity", rarity)

	var preview := GunPreview.create(scene, PREVIEW_PX, 0.6)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(preview)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # one line, always
	name_label.clip_text = true
	name_label.custom_minimum_size.x = WIDTH
	name_label.add_theme_font_override("font", NAME_FONT)
	name_label.add_theme_font_size_override("font_size", NAME_SIZE)
	column.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.text = Rarity.name_of(rarity)
	rarity_label.add_theme_font_override("font", BODY_FONT)
	rarity_label.add_theme_font_size_override("font_size", RARITY_SIZE)
	column.add_child(rarity_label)

	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 12)
	column.add_child(divider)

	# The gun's stats with its rolls applied. Rolled stats are lit up in the rarity color,
	# with the roll next to them. The list takes the rest of the card's fixed height.
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", STAT_LINE_GAP)
	stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stats)
	var lit : Array[Label] = []   # labels drawn in the rarity color
	for stat in gun.get_stat_summary():
		stats.add_child(_stat_line(stat, lit))
	if roll == null or roll.bonuses.is_empty():
		stats.add_child(_stat_row("No bonuses", NO_ROLLS_COLOR))
	if not note.is_empty():
		var note_label := _stat_row(note, NO_ROLLS_COLOR)
		lit.append(note_label)
		stats.add_child(note_label)

	TextGlow.set_text(name_label, gun.get_display_name(), color)
	rarity_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	var boost := color.lerp(Color.WHITE, 0.45)
	for label in lit:
		label.add_theme_color_override("font_color", boost)
	# Mythic: everything drawn in the rarity color gets the rolling rainbow.
	for item in [name_label, rarity_label] + lit:
		Rarity.paint(item, rarity)
	return column


# "Damage            230 (+15%)": name on the left, total (and roll) on the right.
static func _stat_line(stat: Dictionary, lit: Array[Label]) -> Control:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = stat.name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_override("font", BODY_FONT)
	left.add_theme_font_size_override("font_size", STAT_SIZE)
	row.add_child(left)
	var right := Label.new()
	right.text = stat.value + ("  (%s)" % stat.bonus if not stat.bonus.is_empty() else "")
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_override("font", BODY_FONT)
	right.add_theme_font_size_override("font_size", STAT_SIZE)
	row.add_child(right)
	# Too wide for the card (a big number with a big roll)? Shrink this line's text to fit.
	var size := STAT_SIZE
	while size > MIN_STAT_SIZE and _text_w(left.text, size) + _text_w(right.text, size) + 10.0 > WIDTH:
		size -= 1
	if size != STAT_SIZE:
		left.add_theme_font_size_override("font_size", size)
		right.add_theme_font_size_override("font_size", size)
	if stat.boosted:
		lit.append(left)
		lit.append(right)
	else:
		left.add_theme_color_override("font_color", BASE_STAT_COLOR)
		right.add_theme_color_override("font_color", BASE_STAT_COLOR)
	return row


static func _stat_row(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", STAT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


static func _text_w(text: String, size: int) -> float:
	return BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
