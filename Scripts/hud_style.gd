# The HUD's look in one place: the KH2 layout (vitals cluster, command list, item banner)
# brought forward into a clean, modern sci-fi style. Dark translucent panels with a hairline
# border, corner brackets and two cut corners; slim, crisp gauges; letter-spaced captions.
# HUD scripts use these colors, fonts and drawing helpers so everything matches.
class_name HudStyle
extends RefCounted

# ---- Colors ----
## Main accent.
const CYAN := Color(0.45, 0.85, 1.0)
const CYAN_DIM := Color(0.6, 0.8, 0.95, 0.7)
const CYAN_FAINT := Color(0.45, 0.85, 1.0, 0.15)
## Caution and danger.
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.24, 0.27)
const WHITE := Color(0.94, 0.97, 1.0)
const GOLD := Color(1.0, 0.84, 0.35)
## Health red and energy blue.
const HP_RED := Color(1.0, 0.2, 0.26)
const EN_BLUE := Color(0.3, 0.7, 1.0)
## The pale trail left behind on a gauge when it drops.
const TRAIL := Color(1.0, 0.9, 0.85, 0.75)
## Panels: fill (top, bottom), hairline border.
const PANEL_TOP := Color(0.05, 0.08, 0.13, 0.78)
const PANEL_BOTTOM := Color(0.02, 0.04, 0.07, 0.72)
const PANEL_EDGE := Color(0.55, 0.8, 1.0, 0.25)
const SHADOW := Color(0.0, 0.01, 0.03, 0.85)

# ---- Fonts (the project's KH fonts, in their cleaner cuts) ----
## Numbers and titles.
const NUMBER_FONT := preload("res://Fonts/KHMenu-Bold.otf")
const MENU_FONT := preload("res://Fonts/KHMenu-Bold.otf")
## Captions and body text.
const LABEL_FONT := preload("res://Fonts/KHMenu.otf")

## How far a panel's top-left and bottom-right corners are cut.
const CUT := 7.0
## Extra space between letters in captions.
const CAPTION_SPACING := 2

# ---- Layout (base UI pixels, 1152 x 648) ----
## Hostile and scrap panel, top left (hud_timer.gd draws it; the enemy count and scrap
## counter sit inside it).
const MISSION_POS := Vector2(14, 14)
const MISSION_SIZE := Vector2(200, 62)
const MISSION_ROW_HOSTILE := 2.0
const MISSION_ROW_SCRAP := 32.0
const MISSION_ROW_HEIGHT := 28.0
## The timer panel, top center.
const TIME_SIZE := Vector2(150, 48)
const TIME_TOP := 12.0

static var _caption_font : FontVariation


## Caption text: upper case (the letter spacing comes from caption_font()).
static func caption(text: String) -> String:
	return text.to_upper()


## The caption font: the label font with a little extra letter spacing.
static func caption_font() -> Font:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = LABEL_FONT
		_caption_font.spacing_glyph = CAPTION_SPACING
	return _caption_font


## A label in the HUD style, with a thin dark outline so it reads over anything.
static func make_label(text: String, size: int, color := WHITE, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(SHADOW, 0.8))
	l.add_theme_constant_override("outline_size", maxi(roundi(size * 0.14), 2))
	return l


## A small letter-spaced caption ("MISSION TIME", "HOSTILE").
static func make_caption(text: String, size := 10, color := CYAN_DIM) -> Label:
	var l := make_label(caption(text), size, color)
	l.add_theme_font_override("font", caption_font())
	return l


# ======================================================================
# Shapes
# ======================================================================

## Points around a rounded rectangle (clockwise from the top-left).
static func rounded_points(r: Rect2, radius: float, steps := 6) -> PackedVector2Array:
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
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


## The corners of a rect with two opposite corners cut off (top-left and bottom-right).
static func chamfer_points(r: Rect2, cut := CUT) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), r.end - Vector2(cut, 0),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut),
	])


## The standard HUD panel: dark translucent glass with two cut corners, a hairline border,
## bright corner brackets in the accent color and a short accent bar on the left edge.
## lit (0-1) brightens it (hovered buttons).
static func draw_panel(ci: CanvasItem, r: Rect2, accent := CYAN, lit := 0.0) -> void:
	var pts := chamfer_points(r)
	var cols := PackedColorArray()
	var top := PANEL_TOP.lerp(Color(accent.darkened(0.55), 0.85), lit * 0.6)
	var bottom := PANEL_BOTTOM.lerp(Color(accent.darkened(0.7), 0.8), lit * 0.4)
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, PANEL_EDGE.lerp(Color(accent, 0.7), lit), 1.0, true)
	# Corner brackets: top right and bottom left (the uncut corners).
	var b := minf(10.0, minf(r.size.x, r.size.y) * 0.4)
	var bc := Color(accent, 0.85)
	ci.draw_polyline(PackedVector2Array([Vector2(r.end.x - b, r.position.y), Vector2(r.end.x, r.position.y),
			Vector2(r.end.x, r.position.y + b)]), bc, 1.5)
	ci.draw_polyline(PackedVector2Array([Vector2(r.position.x, r.end.y - b), Vector2(r.position.x, r.end.y),
			Vector2(r.position.x + b, r.end.y)]), bc, 1.5)
	# Accent bar on the left edge.
	var h := r.size.y * (0.4 + 0.6 * lit)
	ci.draw_rect(Rect2(r.position.x + 1.0, r.get_center().y - h * 0.5, 2.0 + lit, h), Color(accent, 0.9))


## A thin horizontal divider (inside panels).
static func draw_divider(ci: CanvasItem, from: Vector2, length: float, color := PANEL_EDGE) -> void:
	ci.draw_line(from, from + Vector2(length, 0), color, 1.0)


## A slim gauge. fill and ghost are 0-1; the part between them shows as the pale trail.
## from_right: drains from the left end toward the right.
static func draw_gauge(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		trail := TRAIL, from_right := true) -> void:
	var radius := r.size.y * 0.5
	# Trough.
	ci.draw_colored_polygon(rounded_points(r.grow(1.5), radius + 1.5), Color(0.0, 0.01, 0.03, 0.75))
	ci.draw_colored_polygon(rounded_points(r, radius), Color(color, 0.1))
	for part in [[ghost, trail], [fill, color]]:
		var f : float = part[0]
		if f <= 0.002:
			continue
		var w := maxf(r.size.x * f, r.size.y)
		var pr := Rect2(Vector2(r.end.x - w, r.position.y) if from_right else r.position, Vector2(w, r.size.y))
		_gloss_fill(ci, pr, part[1], radius)


## A gauge fill: flat color, slightly brighter at the top, with a hairline highlight.
static func _gloss_fill(ci: CanvasItem, r: Rect2, color: Color, radius: float) -> void:
	var pts := rounded_points(r, radius)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
		cols.append(color.lerp(Color.WHITE, 0.25 * (1.0 - t)).lerp(color.darkened(0.2), t * t))
	ci.draw_polygon(pts, cols)
	if r.size.y >= 6.0:
		ci.draw_line(r.position + Vector2(radius, 1.5), Vector2(r.end.x - radius, r.position.y + 1.5),
				Color(1, 1, 1, 0.35), 1.0)


## A thick arc in the gauge style (the part of the HP gauge wrapping over the core).
static func draw_gauge_arc(ci: CanvasItem, center: Vector2, radius: float, from_angle: float,
		to_angle: float, width: float, color: Color) -> void:
	if absf(to_angle - from_angle) < 0.001:
		return
	ci.draw_arc(center, radius, from_angle, to_angle, 40, color.darkened(0.15), width, true)
	ci.draw_arc(center, radius + width * 0.3, from_angle, to_angle, 40, Color(color.lerp(Color.WHITE, 0.3), 0.9), width * 0.35, true)


## A light glint sweeping across a panel: a slanted white band at progress t (0-1, left to
## right), clipped to the panel's shape. Tween t to play it.
static func draw_glint(ci: CanvasItem, r: Rect2, t: float, strength := 1.0) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	var slant := r.size.y * 0.6
	var x := lerpf(r.position.x - slant - 30.0, r.end.x + 10.0, t)
	var shape := chamfer_points(r)
	for band in [[30.0, 0.06], [14.0, 0.1], [5.0, 0.16]]:
		var w : float = band[0]
		var poly := PackedVector2Array([Vector2(x + slant, r.position.y), Vector2(x + slant + w, r.position.y),
				Vector2(x + w, r.end.y), Vector2(x, r.end.y)])
		for piece in Geometry2D.intersect_polygons(poly, shape):
			ci.draw_colored_polygon(piece, Color(1, 1, 1, band[1] * strength))
