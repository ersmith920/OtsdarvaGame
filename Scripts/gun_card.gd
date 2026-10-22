# Builds the content of one gun card (gun store, Combiner), as a terminal record:
#   spinning model preview on a scope grid / gun name (bold mono, glowing in its rarity
#   color) / the rarity on an inverted bar / the gun's stats as a dotted-leader table with
#   its rolls applied (rolled ones lit up, with the roll beside them)
#
# Every card is exactly SIZE, whatever the gun: the stat area always has room for the most
# lines any gun can show, so cards line up and nothing moves when the options change
# (rerolls, Combiner picks). A stat line too wide for the card shrinks its text to fit.
#
# scale shrinks or grows the whole card (fonts, preview, width, gaps) evenly: the gun store
# uses smaller cards than the Combiner. Everything below is the size at scale 1.
class_name GunCard
extends RefCounted

const NAME_FONT := HudStyle.TERM_BOLD
const BODY_FONT := HudStyle.TERM_FONT
const VALUE_FONT := HudStyle.READOUT_FONT
const NAME_SIZE := 28
const RARITY_SIZE := 15
const STAT_SIZE := 15
## Smallest a stat line's text shrinks to when it doesn't fit the card's width.
const MIN_STAT_SIZE := 11
## Width of every card's content (the frame around it adds its own padding).
const WIDTH := 290.0
const PREVIEW_PX := Vector2i(290, 150)
## Most stat lines a card can show (every stat a gun can have, plus the note line).
const MAX_STAT_LINES := 14
const STAT_LINE_GAP := 2
const STAT_COLOR := Color(1.0, 0.94, 0.86)
## Shorter stat names on the cards, so every line fits at full size.
const SHORT_NAMES := {"Projectile Speed": "Proj. Speed", "Explosion Damage": "Blast Damage",
		"Explosion Size": "Blast Radius", "Ricochet Chance": "Ricochet %", "Ricochet Bounces": "Bounces"}
## Stats the gun didn't roll a bonus on.
const BASE_STAT_COLOR := Color(1.0, 0.55, 0.25, 0.8)
const NO_ROLLS_COLOR := Color(1.0, 0.42, 0.06, 0.6)


## The size every card's content is (and what frames should hold, plus their padding).
static func get_size(scale := 1.0) -> Vector2:
	var line := maxf(BODY_FONT.get_height(_px(STAT_SIZE, scale)), VALUE_FONT.get_height(_px(STAT_SIZE + 1, scale))) \
			+ _px(STAT_LINE_GAP, scale)
	var height := _px(PREVIEW_PX.y, scale) + NAME_FONT.get_height(_px(NAME_SIZE, scale)) \
			+ NAME_FONT.get_height(_px(RARITY_SIZE, scale)) \
			+ MAX_STAT_LINES * line + 3 * _px(6, scale)   # the rarity bar, then 6 = gaps between parts
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

	# The model turning over a faint scope grid with corner ticks, like a vector display.
	var view_size := Vector2(_px(PREVIEW_PX.x, scale), _px(PREVIEW_PX.y, scale))
	var scope := Control.new()
	scope.custom_minimum_size = view_size
	scope.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scope.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, scope.size)
		var grid := Color(color, 0.1)
		var step := 18.0 * scale
		var x := fmod(r.size.x * 0.5, step)
		while x < r.size.x:
			scope.draw_line(Vector2(x, 0), Vector2(x, r.size.y), grid, 1.0)
			x += step
		var y := fmod(r.size.y * 0.5, step)
		while y < r.size.y:
			scope.draw_line(Vector2(0, y), Vector2(r.size.x, y), grid, 1.0)
			y += step
		var tick := 10.0 * scale
		var tc := Color(color, 0.7)
		for corner in [r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]:
			var sx := 1.0 if corner.x < r.size.x * 0.5 else -1.0
			var sy := 1.0 if corner.y < r.size.y * 0.5 else -1.0
			scope.draw_line(corner, corner + Vector2(tick * sx, 0), tc, 1.5)
			scope.draw_line(corner, corner + Vector2(0, tick * sy), tc, 1.5))
	var preview := GunPreview.create(scene, Vector2i(view_size), 0.6)
	scope.add_child(preview)
	column.add_child(scope)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # one line, always
	name_label.clip_text = true
	name_label.custom_minimum_size.x = _px(WIDTH, scale)
	name_label.add_theme_font_override("font", NAME_FONT)
	name_label.add_theme_font_size_override("font_size", _px(NAME_SIZE, scale))
	name_label.set_meta(&"glow_scale", scale)   # a smaller card gets a smaller halo
	column.add_child(name_label)

	# The rarity on an inverted bar in its color, with the record's class on the right.
	var divider := PanelContainer.new()
	var band := StyleBoxFlat.new()
	band.bg_color = color
	band.content_margin_left = _px(8, scale)
	band.content_margin_right = _px(8, scale)
	divider.add_theme_stylebox_override("panel", band)
	var band_row := HBoxContainer.new()
	divider.add_child(band_row)
	var rarity_label := Label.new()
	rarity_label.text = Rarity.name_of(rarity).to_upper()
	rarity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rarity_label.add_theme_font_override("font", HudStyle.spaced(NAME_FONT, maxi(_px(2, scale), 1)))
	rarity_label.add_theme_font_size_override("font_size", _px(RARITY_SIZE, scale))
	band_row.add_child(rarity_label)
	var class_label := Label.new()
	class_label.text = "ARMS RECORD"
	class_label.add_theme_font_override("font", BODY_FONT)
	class_label.add_theme_font_size_override("font_size", _px(RARITY_SIZE - 3, scale))
	class_label.add_theme_color_override("font_color", HudStyle.INK)
	class_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	class_label.size_flags_vertical = Control.SIZE_FILL
	band_row.add_child(class_label)
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
	rarity_label.add_theme_color_override("font_color", HudStyle.INK)
	var boost := color.lerp(Color.WHITE, 0.45)
	for label in lit:
		label.add_theme_color_override("font_color", boost)
	# Mythic: everything drawn in the rarity color gets the rolling rainbow.
	for item in [name_label, divider] + lit:
		Rarity.paint(item, rarity)
	return column


# "DAMAGE ........ 230 (+15%)": name on the left, total (and roll) on the right, dots between.
static func _stat_line(stat: Dictionary, lit: Array[Label], scale := 1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(4, scale))
	var left := Label.new()
	left.text = String(SHORT_NAMES.get(stat.name, stat.name)).to_upper()
	left.add_theme_font_override("font", BODY_FONT)
	left.add_theme_font_size_override("font_size", _px(STAT_SIZE, scale))
	row.add_child(left)
	var dots := Control.new()
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.draw.connect(func() -> void:
		var c := left.get_theme_color("font_color")
		var y := dots.size.y * 0.5 + _px(STAT_SIZE, scale) * 0.25
		var x := 1.0
		while x < dots.size.x - 1.0:
			dots.draw_rect(Rect2(x, y, 1.5, 1.5), Color(c, 0.35))
			x += 5.0 * maxf(scale, 0.6))
	row.add_child(dots)
	var right := Label.new()
	right.text = stat.value + (" (%s)" % stat.bonus if not stat.bonus.is_empty() else "")
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_override("font", VALUE_FONT)
	right.add_theme_font_size_override("font_size", _px(STAT_SIZE + 1, scale))
	row.add_child(right)
	# Too wide for the card (a big number with a big roll)? Shrink this line's text to fit.
	var full := _px(STAT_SIZE, scale)
	var size := full
	while size > _px(MIN_STAT_SIZE, scale) and _text_w(left.text, size) + _text_w(right.text, size) + 24.0 * scale > WIDTH * scale:
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
