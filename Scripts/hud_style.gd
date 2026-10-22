# The HUD's look in one place: late-80s / 90s anime cyberpunk cockpit displays (NERV's MAGI
# screens in Evangelion, Akira, Ghost in the Shell, Lain) seen through the mech's canopy.
#
# Rules this style is built on:
#   - Color carries meaning. NERV orange is the system chrome. Green = nominal, cyan = power
#     and info, red = alert, yellow / black hazard stripes = danger. Rarity keeps its colors.
#   - Type is bilingual and heavy: big black-weight Mincho kanji (Noto Serif JP Black) as the
#     primary label, condensed English (Barlow Condensed) under or beside it, and tiny
#     monospace data lines (Share Tech Mono) for texture. No letter-spaced captions.
#   - Shapes are bold: thick outlines, solid gradient-filled blocks, angled 45 degree cuts,
#     tag boxes, numbered segments, hex cells and hazard stripes. Nothing is a thin hairline
#     box with corner brackets.
#   - Light comes from the display, not from the shapes: the HUD is rendered off-screen and
#     shown through a CRT pass (hud_display.gd) with heavy phosphor bloom, a slight canopy
#     curve, color fringing and scanlines; menus get a screen-space bloom pass. So elements
#     here are drawn crisp and bright and the bloom is real.
#   - Motion: boot-up sequences, ticking data, blinking alerts, the HUD swaying on its glass.
# HUD scripts use these colors, fonts and drawing helpers so everything matches.
class_name HudStyle
extends RefCounted

# ---- Colors ----
const ORANGE := Color(1.0, 0.42, 0.06)
const ORANGE_DIM := Color(1.0, 0.42, 0.06, 0.55)
const ORANGE_HOT := Color(1.0, 0.78, 0.5)
const GREEN := Color(0.3, 1.0, 0.42)
const INFO := Color(0.3, 0.92, 1.0)
const RED := Color(1.0, 0.12, 0.08)
const YELLOW := Color(1.0, 0.85, 0.08)
const AMBER := Color(1.0, 0.68, 0.08)
## Warm white for important numbers.
const WHITE := Color(1.0, 0.94, 0.86)
const GOLD := Color(1.0, 0.84, 0.35)
## Older names for the main accent (system orange).
const PHOSPHOR := ORANGE
const FRAME := ORANGE
const CYAN := ORANGE
const CYAN_DIM := ORANGE_DIM
const CYAN_FAINT := Color(1.0, 0.42, 0.06, 0.15)
## Gauges.
const HP_COLOR := GREEN
const EN_COLOR := INFO
const HP_RED := HP_COLOR
const EN_BLUE := EN_COLOR
## The pale trail left on a gauge when it drops.
const TRAIL := Color(1.0, 0.92, 0.7, 0.8)
## Screen backing (menus), and the faint backing behind HUD readouts.
const PANEL_TOP := Color(0.05, 0.015, 0.0, 0.9)
const PANEL_BOTTOM := Color(0.02, 0.005, 0.0, 0.92)
const HUD_BACKING := Color(0.03, 0.008, 0.0, 0.45)
const PANEL_EDGE := Color(1.0, 0.42, 0.06, 0.7)
## Dark ink for text on filled blocks.
const INK := Color(0.08, 0.02, 0.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.85)

# ---- Fonts (all open license, see Fonts/*-OFL.txt) ----
## Heavy Mincho for kanji and big titles (only the characters the HUD uses are in this cut;
## see Fonts/NotoSerifJP-Black-HUD-characters.txt).
const KANJI_FONT := preload("res://Fonts/NotoSerifJP-Black-HUD.ttf")
## Condensed English labels and numbers.
const NUMBER_FONT := preload("res://Fonts/BarlowCondensed-Bold.ttf")
const MENU_FONT := preload("res://Fonts/BarlowCondensed-Bold.ttf")
const LABEL_FONT := preload("res://Fonts/BarlowCondensed-SemiBold.ttf")
## Tiny monospace data lines.
const DATA_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
const NUMBER_SCALE := 1.0

## Default 45 degree corner cut on blocks.
const CUT := 8.0
const CAPTION_SPACING := 0

## Kanji for the English words the UI uses, shown with them (menus look these up).
const KANJI := {
	"MISSION TIME": "作戦時間", "HOSTILE": "敵影", "SCRAP": "資材", "HP": "機体耐久",
	"EN": "動力", "SPEED": "速度", "HEADING": "方位", "WARNING": "警告", "DANGER": "危険",
	"WEAPONS": "兵装", "YOUR WEAPONS": "兵装", "ITEM ACQUIRED": "取得", "ITEMS": "物資",
	"PAUSE": "一時停止", "SYSTEM PAUSED": "一時停止", "SETTINGS": "設定", "SYSTEM CONFIG": "設定",
	"RESUME": "再開", "EXIT": "終了", "REROLL": "再抽選", "CLOSE": "閉鎖", "CANCEL": "中止",
	"COMBINE": "融合", "COMBINER": "兵装融合", "RESULT": "結果", "STATS": "能力値",
	"DEV TOOLS": "開発用", "GUN STORE": "兵装調達", "DEV GUN STORE": "兵装調達", "BACK": "設定",
	"RELOAD": "装填", "CRITICAL": "臨界",
}

# ---- Layout (base UI pixels, 1152 x 648) ----
## Hostile and scrap blocks, top left (hud_timer.gd draws them; the enemy count and scrap
## counter sit inside them).
const MISSION_POS := Vector2(18, 16)
const MISSION_SIZE := Vector2(200, 64)
const MISSION_ROW_HOSTILE := 0.0
const MISSION_ROW_SCRAP := 34.0
const MISSION_ROW_HEIGHT := 28.0
## The mission clock, top center.
const TIME_SIZE := Vector2(170, 52)
const TIME_TOP := 12.0

static var _scratch := HudPanelStyle.new()   # reused by draw_panel
static var _spaced_fonts := {}
static var _theme : Theme


# ======================================================================
# Text
# ======================================================================

## Caption text: upper case.
static func caption(text: String) -> String:
	return text.to_upper()


static func caption_font() -> Font:
	return LABEL_FONT


## The kanji for an English UI word, or "" if there isn't one.
static func kanji_for(text: String) -> String:
	return KANJI.get(text.to_upper(), "")


## A label: condensed English. number: the bold cut, for readouts.
static func make_label(text: String, size: int, color := WHITE, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", roundi(size * (NUMBER_SCALE if number else 1.0)))
	add_phosphor(l, color)
	return l


## Colors a label (the bloom comes from the display pass). A very faint dark edge keeps it
## readable over bright scenery. glow adds a soft halo for places without a bloom pass.
static func add_phosphor(l: Control, color: Color, glow := 0.0) -> void:
	var size := l.get_theme_font_size("font_size")
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("outline_size", 1)
	if glow > 0.0:
		l.add_theme_color_override("font_shadow_color", Color(color, color.a * glow))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.add_theme_constant_override("shadow_outline_size", maxi(roundi(size * 0.5), 4))


## A small caption ("HOSTILE"): condensed, dim system orange.
static func make_caption(text: String, size := 10, color := ORANGE_DIM) -> Label:
	return make_label(caption(text), size, color)


## A kanji label in the heavy Mincho.
static func make_kanji(text: String, size: int, color := ORANGE) -> Label:
	var l := make_label(text, size, color)
	l.add_theme_font_override("font", KANJI_FONT)
	return l


## A tiny monospace data line.
static func make_data(text: String, size := 8, color := ORANGE_DIM) -> Label:
	var l := make_label(text, size, color)
	l.add_theme_font_override("font", DATA_FONT)
	return l


## A font with extra space between letters (cached, so labels can share it).
static func spaced(base: Font, spacing: int) -> Font:
	if spacing == 0:
		return base
	var key := [base, spacing]
	if not _spaced_fonts.has(key):
		var f := FontVariation.new()
		f.base_font = base
		f.spacing_glyph = spacing
		_spaced_fonts[key] = f
	return _spaced_fonts[key]


# ======================================================================
# Shapes
# ======================================================================

## Points around a rounded rectangle (clockwise from the top-left).
static func rounded_points(r: Rect2, radius: float, steps := 6) -> PackedVector2Array:
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if radius <= 0.01:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(radius, radius), PI],
		[Vector2(r.end.x - radius, r.position.y + radius), PI * 1.5],
		[r.end - Vector2(radius, radius), 0.0],
		[Vector2(r.position.x + radius, r.end.y - radius), PI * 0.5],
	]
	for c in corners:
		for i in steps + 1:
			var a : float = c[1] + PI * 0.5 * i / steps
			var p : Vector2 = c[0] + Vector2(cos(a), sin(a)) * radius
			# Skip repeats (zero-length sides), which break triangulation.
			if pts.is_empty() or not p.is_equal_approx(pts[pts.size() - 1]):
				pts.append(p)
	if pts.size() > 1 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		pts.remove_at(pts.size() - 1)
	return pts


## The corners of a block with its top-right and bottom-left corners cut at 45 degrees
## (cut <= 0.5: a plain rectangle).
## Off: blocks are square rectangles. On: the old 45-degree cut corners come back.
const FORCE_CUTS := false

static func chamfer_points(r: Rect2, cut := CUT) -> PackedVector2Array:
	# Style rule: every block is a plain rectangle (flat, square, like a vector terminal), so
	# the cut is ignored unless FORCE_CUTS is turned back on.
	if cut <= 0.5 or not FORCE_CUTS:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	cut = minf(cut, minf(r.size.x, r.size.y) * 0.45)
	return PackedVector2Array([
		r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut),
		r.end, Vector2(r.position.x + cut, r.end.y), Vector2(r.position.x, r.end.y - cut),
	])


## A block (HudPanelStyle drawn straight onto a CanvasItem). lit: 0-1 fills it with the
## accent.
static func draw_panel(ci: CanvasItem, r: Rect2, accent := ORANGE, lit := 0.0) -> void:
	_scratch.accent = accent
	_scratch.edge = accent
	_scratch.lit = lit
	_scratch.fill_top = HUD_BACKING
	_scratch.fill_bottom = HUD_BACKING
	HudPanelStyle.paint(ci.get_canvas_item(), r, _scratch)


## A block's outline drawn on: traced from the top-left up to `progress` (0-1), following its
## cut corners. Boot-up animations tween progress from 0 to 1.
static func draw_frame(ci: CanvasItem, r: Rect2, color: Color, progress := 1.0, width := 2.0,
		_glow := 0.0, cut := CUT) -> void:
	if progress <= 0.0:
		return
	var pts := chamfer_points(r, cut)
	pts.append(pts[0])
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var left := total * clampf(progress, 0.0, 1.0)
	for i in pts.size() - 1:
		if left <= 0.0:
			break
		var a := pts[i]
		var b := pts[i + 1]
		var len := a.distance_to(b)
		ci.draw_line(a, a.lerp(b, minf(left / len, 1.0)), color, width)
		left -= len


## Yellow / black hazard stripes filling a rect (danger zones, warnings).
static func draw_hazard(ci: CanvasItem, r: Rect2, color := YELLOW, stripe := 6.0, offset := 0.0) -> void:
	ci.draw_rect(r, Color(0.05, 0.03, 0.0, 0.85))
	var x := r.position.x - r.size.y + fposmod(offset, stripe * 2.0) - stripe * 2.0
	while x < r.end.x:
		var poly := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + stripe, r.end.y),
				Vector2(x + stripe + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)])
		for piece in Geometry2D.intersect_polygons(poly, PackedVector2Array([r.position,
				Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])):
			ci.draw_colored_polygon(piece, color)
		x += stripe * 2.0


## A hexagon cell (flat top), outlined or filled.
static func draw_hex(ci: CanvasItem, center: Vector2, radius: float, color: Color, filled := false, width := 1.5) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 3.0 * i
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	if filled:
		ci.draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, color, width, true)


## A "+" mark.
static func draw_mark(ci: CanvasItem, at: Vector2, color := ORANGE, size := 5.0) -> void:
	ci.draw_line(at - Vector2(size, 0), at + Vector2(size, 0), color, 1.5)
	ci.draw_line(at - Vector2(0, size), at + Vector2(0, size), color, 1.5)


## A line with a soft glow around it (for places without a bloom pass).
static func draw_glow_line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width := 2.0, glow := 1.0) -> void:
	for i in [[8.0, 0.06], [4.0, 0.12]]:
		ci.draw_line(a, b, Color(color, color.a * i[1] * glow), width + i[0], true)
	ci.draw_line(a, b, color, width, true)


## A thick rule.
static func draw_divider(ci: CanvasItem, from: Vector2, length: float, color := PANEL_EDGE) -> void:
	ci.draw_line(from, from + Vector2(length, 0), color, 2.0)


## A bar graph of square segments inside a frame.
## fill and ghost are 0-1; segments between them show in the trail color. from_right: drains
## from the left end. segment: width of one segment including its gap, in pixels.
static func draw_gauge(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		trail := TRAIL, from_right := true, segment := 7.0) -> void:
	ci.draw_rect(r.grow(2.5), Color(color, 0.55), false, 1.5)
	var count := maxi(roundi(r.size.x / segment), 1)
	var seg_w := r.size.x / count
	var gap := minf(2.0, seg_w * 0.35)
	var slant := 0.0   # square segments (flat terminal look)
	for i in count:
		var k := (count - 1 - i) if from_right else i
		var at := (k + 0.5) / count
		var c := Color(color, 0.1)
		if at <= fill:
			c = color
		elif at <= ghost:
			c = trail
		var x0 := r.position.x + i * seg_w
		var x1 := x0 + seg_w - gap
		var sl := slant if x1 - x0 > slant + 0.5 else 0.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + sl, r.position.y), Vector2(x1, r.position.y),
				Vector2(x1 - sl, r.end.y), Vector2(x0, r.end.y)]), c)


## A flat fill (kept for older callers).
static func _gloss_fill(ci: CanvasItem, r: Rect2, color: Color, _radius: float) -> void:
	ci.draw_rect(r, color)


## A thick arc (kept for older callers).
static func draw_gauge_arc(ci: CanvasItem, center: Vector2, radius: float, from_angle: float,
		to_angle: float, width: float, color: Color) -> void:
	if absf(to_angle - from_angle) > 0.001:
		ci.draw_arc(center, radius, from_angle, to_angle, 40, color, width, true)


## A scan sweep down a panel: a bright line with a short fading trail. t: 0-1 progress.
static func draw_glint(ci: CanvasItem, r: Rect2, t: float, strength := 1.0) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	var y := lerpf(r.position.y, r.end.y, t)
	var top := maxf(y - 18.0, r.position.y)
	if y > top:
		ci.draw_rect(Rect2(r.position.x + 2.0, top, r.size.x - 4.0, y - top), Color(ORANGE_HOT, 0.08 * strength))
	ci.draw_rect(Rect2(r.position.x + 2.0, y - 1.0, r.size.x - 4.0, 2.0), Color(ORANGE_HOT, 0.6 * strength))


## Adds a scan-sweep overlay on top of a control and returns a Callable that plays it once.
## Inside a container it covers the container's content area.
static func add_glint(c: Control, strength := 1.0, time := 0.4) -> Callable:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_meta(&"t", 0.0)
	overlay.set_meta(&"glint_overlay", true)   # menus that clear a control's children keep this
	c.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(func() -> void:
		draw_glint(overlay, Rect2(Vector2.ZERO, overlay.size), overlay.get_meta(&"t"), strength))
	return func() -> void:
		if not is_instance_valid(overlay):
			return
		var tw := UIJuice.tween_of(overlay)
		tw.tween_method(func(v: float) -> void:
			overlay.set_meta(&"t", v)
			overlay.queue_redraw(), 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ======================================================================
# Menus: blocks, cards, tiles, buttons and headers in the same language
# ======================================================================

## A menu block (columns, windows, tooltips): dark, with a thick system-orange outline and
## cut corners. fill_alpha scales how see-through it is.
static func panel_style(accent := ORANGE, padding := 12.0, fill_alpha := 1.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.accent = accent
	s.edge = Color(accent, 0.85)
	s.edge_width = 2.0
	s.cut = 10.0
	s.fill_top = Color(PANEL_BOTTOM, PANEL_BOTTOM.a * fill_alpha)
	s.fill_bottom = s.fill_top
	s.marks = 4.0   # "+" registration marks in the corners, like a vector terminal
	s.set_content_margin_all(padding)
	return s


## A card block (gun store cards, Combiner slots) in a rarity color: a gradient-filled block
## (lit color at the top fading to dark), thick outline, cut corners. lit: 0 normal, about
## 0.5 hovered, 1 pressed. Empty slots use empty_card_style().
static func card_style(color: Color, lit := 0.0, padding := 10.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_card(s, color, lit)
	s.edge_width = 2.5
	s.cut = 14.0
	s.set_content_margin_all(padding)
	return s


## Recolors a card style (Mythic frames call this every frame with the rainbow color).
static func color_card(s: HudPanelStyle, color: Color, lit := 0.0) -> void:
	s.accent = color
	s.edge = color.lerp(Color.WHITE, 0.2 * lit)
	s.fill_top = Color(color.darkened(0.86 - 0.12 * lit), 0.9)   # flat fill
	s.fill_bottom = s.fill_top
	s.glow = Color(color, 0.7)
	s.glow_size = 4.0 + 6.0 * lit


## An empty card block (nothing in the slot yet): dark with a dashed dim outline.
static func empty_card_style(padding := 10.0) -> HudPanelStyle:
	var s := panel_style(ORANGE, padding)
	s.edge = Color(ORANGE, 0.35)
	s.dashed = true
	s.cut = 14.0
	return s


## A small square tile (items, weapons) in a tier / rarity color.
static func tile_style(color: Color) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_tile(s, color)
	s.cut = 6.0
	s.edge_width = 2.0
	return s


static func color_tile(s: HudPanelStyle, color: Color) -> void:
	s.accent = color
	s.edge = color
	s.fill_top = Color(color.darkened(0.85), 0.8)   # flat fill
	s.fill_bottom = s.fill_top
	s.glow = Color(color, 0.5)
	s.glow_size = 3.0


## An empty tile (an empty gun slot): dark with a dashed dim outline.
static func empty_tile_style() -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.fill_top = Color(0.05, 0.015, 0.0, 0.5)
	s.fill_bottom = s.fill_top
	s.edge = Color(ORANGE, 0.3)
	s.dashed = true
	s.cut = 6.0
	return s


## A command button: a thick orange outlined block with cut corners; the English label and,
## when there is one, its kanji (small, at the right end). Hovered, it fills with an orange
## gradient from the left and the text turns to dark ink; pressing punches it. Hover / click
## sounds included. A disabled button goes dim and dashed and ignores hovers.
## slide: nudges right when hovered (left-aligned lists).
static func make_button(text: String, min_size := Vector2(200, 44), font_size := 18, accent := ORANGE,
		slide := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	button.alignment = align
	var kanji := kanji_for(text)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 18 if align == HORIZONTAL_ALIGNMENT_LEFT else 12
		box.content_margin_right = 12 + (font_size * 0.9 * kanji.length() if align == HORIZONTAL_ALIGNMENT_LEFT else 0.0)
		button.add_theme_stylebox_override(st, box)
	button.add_theme_font_override("font", spaced(MENU_FONT, 1))
	button.add_theme_font_size_override("font_size", font_size)
	var set_ink := func(lit: float) -> void:
		var c := accent.lerp(INK, smoothstep(0.35, 0.65, lit))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(key, c)
	set_ink.call(0.0)
	button.add_theme_color_override("font_disabled_color", Color(accent, 0.3))
	button.add_theme_constant_override("outline_size", 0)
	button.set_meta(&"lit", 0.0)
	# The block is drawn by a child shown behind the button, so the text stays on top.
	var plate := Control.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	button.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := HudPanelStyle.new()
	style.cut = 8.0
	style.edge_width = 2.0
	plate.draw.connect(func() -> void:
		var lit : float = button.get_meta(&"lit")
		var r := Rect2(Vector2(lit * 6.0 if slide else 0.0, 0), button.size)
		style.accent = accent
		style.dashed = button.disabled
		style.edge = Color(accent, 0.3) if button.disabled else accent
		style.fill_top = Color(0.06, 0.02, 0.0, 0.8)
		style.fill_bottom = style.fill_top
		style.sweep = 0.0 if button.disabled else lit
		HudPanelStyle.paint(plate.get_canvas_item(), r, style)
		if not kanji.is_empty():
			var ks := roundi(font_size * 0.75)
			var kc : Color = Color(accent, 0.3) if button.disabled else accent.lerp(INK, smoothstep(0.35, 0.65, lit))
			var kw: float = KANJI_FONT.get_string_size(kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
			var y := r.get_center().y + ks * 0.38
			if align == HORIZONTAL_ALIGNMENT_LEFT:
				plate.draw_string(KANJI_FONT, Vector2(r.end.x - kw - 12.0, y), kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, kc)
			else:
				# Centered buttons: the kanji in the top-left corner, small.
				var ks2 := roundi(font_size * 0.55)
				plate.draw_string(KANJI_FONT, r.position + Vector2(8.0, ks2 + 3.0), kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, ks2, kc))
	var light := func(to: float) -> void:
		var t := UIJuice.tween_of(button)
		t.tween_method(func(v: float) -> void:
			button.set_meta(&"lit", v)
			set_ink.call(v)
			plate.queue_redraw(), button.get_meta(&"lit"), to, 0.14)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		light.call(1.0)
		UIJuice.play(UIJuice.Sfx.HOVER))
	button.mouse_exited.connect(func() -> void: light.call(0.0))
	button.button_down.connect(func() -> void:
		UIJuice.play(UIJuice.Sfx.CLICK)
		UIJuice.punch(button, -0.05))
	# Redraw when it's enabled / disabled (Godot doesn't redraw children for that).
	button.draw.connect(plate.queue_redraw)
	return button


## A section header: a filled orange tag with the English label in dark ink, its kanji
## beside it, and a thick rule running on to the right.
static func make_header(text: String, size := 13, _color := ORANGE_DIM, align := HORIZONTAL_ALIGNMENT_LEFT,
		accent := ORANGE) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.content_margin_left = 7
	fill.content_margin_right = 7
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	tag.add_theme_stylebox_override("panel", fill)
	var label := make_label(caption(text), size + 2, INK, true)
	label.remove_theme_constant_override("outline_size")
	tag.add_child(label)
	row.add_child(tag)
	var kanji := kanji_for(text.get_slice("/", 0).strip_edges())
	if not kanji.is_empty():
		row.add_child(make_kanji(kanji, size + 1, accent))
	if align != HORIZONTAL_ALIGNMENT_CENTER:
		var rule := make_rule(false, accent)
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rule)
	row.set_meta(&"label", label)
	return row


## A thick rule.
static func make_rule(_centered := false, accent := ORANGE) -> Control:
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size.y = 2
	rule.draw.connect(func() -> void: rule.draw_rect(Rect2(0, 0, rule.size.x, 2), Color(accent, 0.7)))
	return rule


## A menu title, NERV style: the kanji huge in heavy Mincho, the English in a filled tag
## beside it, and a hazard-striped tab. Returns a control; its meta "label" is the English
## Label (callers can change its text).
static func make_title(text: String, size := 30) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 12)
	var big := make_kanji("", roundi(size * 1.25), ORANGE)
	row.add_child(big)
	row.set_meta(&"kanji", big)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 3)
	row.add_child(column)
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	fill.content_margin_left = 8
	fill.content_margin_right = 8
	tag.add_theme_stylebox_override("panel", fill)
	var label := make_label(text.to_upper(), roundi(size * 0.6), INK, true)
	label.remove_theme_constant_override("outline_size")
	tag.add_child(label)
	column.add_child(tag)
	var stripes := Control.new()
	stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripes.custom_minimum_size = Vector2(0, 7)
	stripes.draw.connect(func() -> void: draw_hazard(stripes, Rect2(Vector2.ZERO, stripes.size), YELLOW, 4.0))
	column.add_child(stripes)
	row.set_meta(&"label", label)
	set_title(row, text)
	return row


## Changes a make_title() title's text (and its kanji, when there is one).
static func set_title(title: Control, text: String) -> void:
	(title.get_meta(&"label") as Label).text = text.to_upper()
	var big := title.get_meta(&"kanji") as Label
	big.text = kanji_for(text)
	big.visible = not big.text.is_empty()


## A Theme for menus, so anything without its own styling (plain Labels, Buttons, toggles,
## scrollbars, separators, sliders) still matches.
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = LABEL_FONT
	t.default_font_size = 16
	t.set_color("font_color", "Label", WHITE)

	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var s := HudPanelStyle.new()
		s.fill_top = Color(0.06, 0.02, 0.0, 0.8)
		s.fill_bottom = s.fill_top
		s.cut = 6.0
		s.edge_width = 2.0
		s.sweep = {"normal": 0.0, "hover": 1.0, "pressed": 1.0, "disabled": 0.0, "hover_pressed": 1.0}[state]
		s.accent = ORANGE
		s.edge = Color(ORANGE, 0.3) if state == "disabled" else ORANGE
		s.dashed = state == "disabled"
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		t.set_stylebox(state, "Button", s)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", MENU_FONT)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", ORANGE)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(ORANGE, 0.3))

	# Toggles: label plus a block, outlined when off and filled when on.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font("font", "CheckButton", MENU_FONT)
	t.set_font_size("font_size", "CheckButton", 16)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", ORANGE)
	t.set_icon("checked", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked", "CheckButton", _switch_texture(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_texture(false))

	# Scrollbars: a thin dark track with a solid orange grabber.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(ORANGE, 0.1)
		track.set_content_margin_all(2)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		for g in [["grabber", 0.6], ["grabber_highlight", 0.85], ["grabber_pressed", 1.0]]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(ORANGE, g[1])
			t.set_stylebox(g[0], bar, grab)

	var line := StyleBoxLine.new()
	line.color = PANEL_EDGE
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	_theme = t
	return t


# A toggle block: filled green with "ON" feel when on, an outlined orange block when off.
static func _switch_texture(on: bool) -> Texture2D:
	const W := 34
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(GREEN if on else Color(0, 0, 0, 0))
	if not on:
		for x in W:
			for y in [0, 1, H - 2, H - 1]:
				img.set_pixel(x, y, ORANGE)
		for y in H:
			for x in [0, 1, W - 2, W - 1]:
				img.set_pixel(x, y, ORANGE)
	return ImageTexture.create_from_image(img)


## Puts a menu (or one panel of it) through the same CRT pass as the HUD display: the
## overlay re-draws what's under it with bloom (bright, saturated pixels bleed light),
## red / blue fringing and scanlines. Add it last so it covers the menu's contents; it covers
## exactly its parent's rect, so pass the panel when the menu shouldn't process the whole
## screen. Unsaturated brights (sky, clouds) barely bloom, so the scene stays as it is.
static func add_menu_bloom(menu: Control, strength := 1.0) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _bloom_shader()
	mat.set_shader_parameter(&"strength", strength)
	rect.material = mat
	# Godot copies the screen only once per frame for screen-texture shaders, so force a fresh
	# copy right here; otherwise the overlay would show a stale image from before the menu drew.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.set_meta(&"glint_overlay", true)
	menu.add_child(copy)
	menu.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.set_meta(&"glint_overlay", true)   # menus that clear their children keep this
	return rect


static var _bloom : Shader

static func _bloom_shader() -> Shader:
	if _bloom == null:
		_bloom = Shader.new()
		_bloom.code = """
shader_type canvas_item;
render_mode blend_mix;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float strength = 1.0;
uniform float scan = 0.13;
uniform float fringe = 1.1;

vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(screen, uv, lod).rgb;
	float hi = max(c.r, max(c.g, c.b));
	float sat = hi - min(c.r, min(c.g, c.b));
	return c * mix(0.25, 1.0, smoothstep(0.2, 0.6, sat)) * smoothstep(0.45, 0.95, hi);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 f = (uv - 0.5) * fringe * SCREEN_PIXEL_SIZE * 2.0;
	vec3 c = vec3(textureLod(screen, uv + f, 0.0).r, textureLod(screen, uv, 0.0).g, textureLod(screen, uv - f, 0.0).b);
	vec3 glow = bright(uv, 1.0) * 0.25 + bright(uv, 2.5) * 0.35 + bright(uv, 4.0) * 0.4 + bright(uv, 5.5) * 0.3;
	float lines = 1.0 - scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	vec3 rgb = c * lines + glow * strength;
	// Over-bright areas keep their hue and only partly burn toward white (as on the HUD).
	float peak = max(rgb.r, max(rgb.g, rgb.b));
	if (peak > 1.0) {
		rgb = mix(rgb / peak, min(rgb, vec3(1.0)), 0.3);
	}
	COLOR = vec4(rgb, 1.0);
}
"""
	return _bloom
