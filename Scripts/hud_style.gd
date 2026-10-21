# The HUD's look in one place: Kingdom Hearts 2 menus and gauges crossed with gritty sci-fi
# mech hardware. Glossy, rounded "command plate" readouts (blue gradient, white rim, a shine
# across the top) mounted on dark, bolted metal backings; a KH-style vitals cluster (a round
# core with the HP gauge wrapping over it); KH fonts. HUD scripts use these colors, fonts and
# drawing helpers so everything matches.
class_name HudStyle
extends RefCounted

# ---- Colors ----
## Main accent: KH menu blue.
const CYAN := Color(0.42, 0.78, 1.0)
const CYAN_DIM := Color(0.62, 0.84, 1.0, 0.75)
const CYAN_FAINT := Color(0.42, 0.78, 1.0, 0.15)
## Caution and danger.
const AMBER := Color(1.0, 0.7, 0.2)
const RED := Color(1.0, 0.25, 0.22)
const WHITE := Color(0.97, 0.98, 1.0)
const GOLD := Color(1.0, 0.84, 0.3)
## HP green and EN (energy) blue, like KH's HP and MP gauges.
const HP_GREEN := Color(0.35, 1.0, 0.35)
const EN_BLUE := Color(0.35, 0.6, 1.0)
## Command plate gradient (top, bottom) and rim.
const PLATE_TOP := Color(0.24, 0.5, 0.92, 0.92)
const PLATE_BOTTOM := Color(0.06, 0.16, 0.42, 0.92)
const PLATE_RIM := Color(0.95, 0.97, 1.0, 0.95)
## Metal backing.
const METAL := Color(0.09, 0.1, 0.12, 0.85)
const METAL_EDGE := Color(0.45, 0.48, 0.52, 0.6)
const PANEL_BG := METAL

# ---- Fonts (the project's KH-style fonts) ----
## Numbers and titles: chunky italic, like KH's.
const NUMBER_FONT := preload("res://Fonts/KHGummi.otf")
## Small tags and captions.
const LABEL_FONT := preload("res://Fonts/KHMenu-Italic.otf")
const MENU_FONT := preload("res://Fonts/KHMenu-Bold.otf")

const CHAMFER := 10.0

# ---- Layout (base UI pixels, 1152 x 648) ----
## Hostile and scrap plates, top left (hud_timer.gd draws them; the enemy count and scrap
## counter sit inside them).
const MISSION_POS := Vector2(14, 14)
const MISSION_SIZE := Vector2(200, 66)
const MISSION_ROW_HOSTILE := 0.0
const MISSION_ROW_SCRAP := 36.0
const MISSION_ROW_HEIGHT := 30.0
## The timer plate, top center.
const TIME_SIZE := Vector2(176, 50)
const TIME_TOP := 12.0


## Caption text: just upper case (KH tags aren't letter-spaced).
static func caption(text: String) -> String:
	return text.to_upper()


## A label in the HUD style: white with a dark outline (KH text is outlined, never shadowed).
static func make_label(text: String, size: int, color := WHITE, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.1, 0.95))
	l.add_theme_constant_override("outline_size", maxi(roundi(size * 0.22), 3))
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
			pts.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	return pts


## The corners of a rect with two opposite corners cut off (top-left and bottom-right).
static func chamfer_points(r: Rect2, cut := CHAMFER) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), r.end - Vector2(cut, 0),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut),
	])


## A glossy KH command plate: vertical gradient, a shine across the top half, white rim.
static func draw_plate(ci: CanvasItem, r: Rect2, top := PLATE_TOP, bottom := PLATE_BOTTOM,
		rim := PLATE_RIM, radius := 10.0) -> void:
	var pts := rounded_points(r, radius)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)
	# Shine: a soft white band over the top half.
	var shine := Rect2(r.position + Vector2(3, 2), Vector2(r.size.x - 6, r.size.y * 0.45))
	var spts := rounded_points(shine, radius - 2.0)
	var scols := PackedColorArray()
	for p in spts:
		var t := clampf((p.y - shine.position.y) / shine.size.y, 0.0, 1.0)
		scols.append(Color(1, 1, 1, 0.22 * (1.0 - t)))
	ci.draw_polygon(spts, scols)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, rim, 2.0, true)


## Dark mech metal behind a plate: angled corners, a lighter edge, bolts in the corners and
## a few hazard ticks. Gives the KH plates something heavy to sit on.
static func draw_backing(ci: CanvasItem, r: Rect2, cut := 8.0) -> void:
	var pts := chamfer_points(r, cut)
	ci.draw_colored_polygon(pts, METAL)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, METAL_EDGE, 1.0, true)
	for b in [r.position + Vector2(cut + 4, 4), Vector2(r.end.x - 5, r.position.y + 5),
			Vector2(r.position.x + 5, r.end.y - 5), r.end - Vector2(cut + 4, 4)]:
		ci.draw_circle(b, 2.0, Color(0.55, 0.58, 0.62, 0.9))
		ci.draw_circle(b + Vector2(-0.5, -0.5), 0.8, Color(0.85, 0.88, 0.9, 0.9))
	# Hazard ticks along the bottom edge.
	var x := r.end.x - cut - 40.0
	for i in 4:
		ci.draw_line(Vector2(x + i * 7, r.end.y - 2), Vector2(x + i * 7 + 4, r.end.y - 6), Color(AMBER, 0.55), 2.0)


## A rounded glossy gauge (KH HP / MP style). fill and ghost are 0-1; the part between them
## shows as the red damage trail. from_right: drains from the left end toward the right.
static func draw_gauge(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		trail := RED, from_right := true) -> void:
	var radius := r.size.y * 0.5
	# Trough.
	ci.draw_colored_polygon(rounded_points(r.grow(2.0), radius + 2.0), Color(0.02, 0.03, 0.06, 0.9))
	ci.draw_colored_polygon(rounded_points(r, radius), Color(color, 0.12))
	for part in [[ghost, trail], [fill, color]]:
		var f : float = part[0]
		if f <= 0.002:
			continue
		var w := maxf(r.size.x * f, r.size.y)
		var pr := Rect2(Vector2(r.end.x - w, r.position.y) if from_right else r.position, Vector2(w, r.size.y))
		_gloss_fill(ci, pr, part[1], radius)


static func _gloss_fill(ci: CanvasItem, r: Rect2, color: Color, radius: float) -> void:
	var pts := rounded_points(r, radius)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
		# Bright top, rich middle, darker bottom: the KH gauge gloss.
		var c := color.lerp(Color.WHITE, 0.45 * (1.0 - t) * (1.0 - t)).lerp(color.darkened(0.35), t * t)
		cols.append(c)
	ci.draw_polygon(pts, cols)
	ci.draw_line(r.position + Vector2(radius, 2), Vector2(r.end.x - radius, r.position.y + 2), Color(1, 1, 1, 0.45), 1.0)


## A thick glossy arc (the part of the HP gauge wrapping over the core).
static func draw_gauge_arc(ci: CanvasItem, center: Vector2, radius: float, from_angle: float,
		to_angle: float, width: float, color: Color) -> void:
	if absf(to_angle - from_angle) < 0.001:
		return
	ci.draw_arc(center, radius, from_angle, to_angle, 32, color.darkened(0.25), width, true)
	ci.draw_arc(center, radius + width * 0.18, from_angle, to_angle, 32, color, width * 0.55, true)
	ci.draw_arc(center, radius + width * 0.32, from_angle, to_angle, 32, Color(color.lerp(Color.WHITE, 0.6), 0.8), width * 0.15, true)


# ---- Kept for older callers ----

## A dark angled panel (metal backing).
static func draw_panel(ci: CanvasItem, r: Rect2, _accent := CYAN, _bg := METAL, cut := CHAMFER) -> void:
	draw_backing(ci, r, cut)


## A bar (now drawn as a glossy KH gauge).
static func draw_segment_bar(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		_segments := 40, _gap := 2.0, _slant := 4.0) -> void:
	draw_gauge(ci, r, fill, ghost, color)
