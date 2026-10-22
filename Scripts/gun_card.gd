# Builds the content of one gun card (gun store, Combiner):
#   spinning model preview / gun name (bold, glowing in its rarity color) / rarity /
#   the gun's stats with its rolls applied (rolled ones lit up, with the roll beside them)
#
# Every card is exactly SIZE, whatever the gun: the stat area always has room for the most
# lines any gun can show, so cards line up and nothing moves when the options change
# (rerolls, Combiner picks). A stat line too wide for the card shrinks its text to fit.
#
# scale shrinks or grows the whole card (fonts, preview, width, gaps) evenly: the gun store
# uses smaller cards than the Combiner. Everything below is the size at scale 1.
class_name GunCard
extends RefCounted

const NAME_FONT := HudStyle.NUMBER_FONT   # VT323 (terminal)
const BODY_FONT := HudStyle.LABEL_FONT    # Share Tech Mono
const NAME_SIZE := 34
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
const STAT_COLOR := Color(0.86, 1.0, 0.89)
## Stats the gun didn't roll a bonus on.
const BASE_STAT_COLOR := Color(0.45, 0.72, 0.52)
const NO_ROLLS_COLOR := Color(0.4, 0.6, 0.45)


## The size every card's content is (and what frames should hold, plus their padding).
static func get_size(scale := 1.0) -> Vector2:
	var line := BODY_FONT.get_height(_px(STAT_SIZE, scale)) + _px(STAT_LINE_GAP, scale)
	var height := _px(PREVIEW_PX.y, scale) + NAME_FONT.get_height(_px(NAME_SIZE, scale)) \
			+ BODY_FONT.get_height(_px(RARITY_SIZE, scale)) + _px(12, scale) \
			+ MAX_STAT_LINES * line + 4 * _px(6, scale)   # 12 = divider, 6 = gaps between parts
	return Vector2(_px(WIDTH, scale), ceilf(height))


# A size at this scale, in whole pixels (never 0).
static func _px(value: float, scale: float) -> int:
	return maxi(roundi(value * scale), 1)


## scene: the gun's .tscn. gun: an instance of it (needed for its name; doesn't need to be in the tree).
## note: an extra line under the stats (the Combiner uses it for "+ 1 random new stat").
## scale: 1 = full size, 0.5 = half (see above).
static func build(scene: PackedScene, gun: Gun, note := "", scale := 1.0) -> Control:
	var roll := gun.roll
	var rarity := gun.get_rarity()
	var color := Rarity.get_color(rarity)

	var column := VBoxContainer.new()
	column.custom_minimum_size = get_size(scale)
	column.add_theme_constant_override("separation", _px(6, scale))
	column.set_meta(&"color", color)   # the popup colors the card frame with this
	column.set_meta(&"rarity", rarity)

	var preview := GunPreview.create(scene, Vector2i(_px(PREVIEW_PX.x, scale), _px(PREVIEW_PX.y, scale)), 0.6)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(preview)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # one line, always
	name_label.clip_text = true
	name_label.custom_minimum_size.x = _px(WIDTH, scale)
	name_label.add_theme_font_override("font", NAME_FONT)
	name_label.add_theme_font_size_override("font_size", _px(NAME_SIZE, scale))
	name_label.set_meta(&"glow_scale", scale)   # a smaller card gets a smaller halo
	column.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.text = Rarity.name_of(rarity).to_upper()
	rarity_label.add_theme_font_override("font", HudStyle.spaced(BODY_FONT, maxi(_px(3, scale), 1)))
	rarity_label.add_theme_font_size_override("font_size", _px(RARITY_SIZE, scale))
	column.add_child(rarity_label)

	# Divider: a hairline with a short segment in the rarity color in the middle (HUD style).
	var divider := Control.new()
	divider.custom_minimum_size.y = _px(12, scale)
	divider.draw.connect(func() -> void:
		var y := roundf(divider.size.y * 0.5)
		divider.draw_rect(Rect2(0, y, divider.size.x, 1), HudStyle.PANEL_EDGE)
		var seg := divider.size.x * 0.22
		divider.draw_rect(Rect2((divider.size.x - seg) * 0.5, y - 1, seg, 3), Color(color, 0.9)))
	column.add_child(divider)

	# The gun's stats with its rolls applied. Rolled stats are lit up in the rarity color,
	# with the roll next to them. The list takes the rest of the card's fixed height.
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", _px(STAT_LINE_GAP, scale))
	stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stats)
	var lit : Array[Label] = []   # labels drawn in the rarity color
	for stat in gun.get_stat_summary():
		stats.add_child(_stat_line(stat, lit, scale))
	if roll == null or roll.bonuses.is_empty():
		stats.add_child(_stat_row("No bonuses", NO_ROLLS_COLOR, scale))
	if not note.is_empty():
		var note_label := _stat_row(note, NO_ROLLS_COLOR, scale)
		lit.append(note_label)
		stats.add_child(note_label)

	TextGlow.set_text(name_label, gun.get_display_name(), color)
	rarity_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	var boost := color.lerp(Color.WHITE, 0.45)
	for label in lit:
		label.add_theme_color_override("font_color", boost)
	# Mythic: everything drawn in the rarity color gets the rolling rainbow.
	for item in [name_label, rarity_label, divider] + lit:
		Rarity.paint(item, rarity)
	return column


# "Damage            230 (+15%)": name on the left, total (and roll) on the right.
static func _stat_line(stat: Dictionary, lit: Array[Label], scale := 1.0) -> Control:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = stat.name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_override("font", BODY_FONT)
	left.add_theme_font_size_override("font_size", _px(STAT_SIZE, scale))
	row.add_child(left)
	var right := Label.new()
	right.text = stat.value + ("  (%s)" % stat.bonus if not stat.bonus.is_empty() else "")
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_override("font", BODY_FONT)
	right.add_theme_font_size_override("font_size", _px(STAT_SIZE, scale))
	row.add_child(right)
	# Too wide for the card (a big number with a big roll)? Shrink this line's text to fit.
	var full := _px(STAT_SIZE, scale)
	var size := full
	while size > _px(MIN_STAT_SIZE, scale) and _text_w(left.text, size) + _text_w(right.text, size) + 10.0 * scale > WIDTH * scale:
		size -= 1
	if size != full:
		left.add_theme_font_size_override("font_size", size)
		right.add_theme_font_size_override("font_size", size)
	if stat.boosted:
		lit.append(left)
		lit.append(right)
	else:
		left.add_theme_color_override("font_color", BASE_STAT_COLOR)
		right.add_theme_color_override("font_color", BASE_STAT_COLOR)
	return row


static func _stat_row(text: String, color: Color, scale := 1.0) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", _px(STAT_SIZE, scale))
	label.add_theme_color_override("font_color", color)
	return label


static func _text_w(text: String, size: int) -> float:
	return BODY_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
