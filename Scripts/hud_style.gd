# The HUD's look in one place: a clean, slightly retro cyber-mecha style (think PS2-era mech
# games). Cyan readouts on dark, angled panels with faint scanlines; amber for warnings,
# red for danger. HUD scripts use these colors, fonts and drawing helpers so it all matches.
class_name HudStyle
extends RefCounted

## Readout / accent color.
const CYAN := Color(0.45, 0.92, 1.0)
const CYAN_DIM := Color(0.45, 0.92, 1.0, 0.35)
const CYAN_FAINT := Color(0.45, 0.92, 1.0, 0.12)
## Caution (low energy, low armor).
const AMBER := Color(1.0, 0.68, 0.18)
## Danger (critical armor, locked target).
const RED := Color(1.0, 0.28, 0.25)
const WHITE := Color(0.92, 0.97, 1.0)
const PANEL_BG := Color(0.02, 0.045, 0.06, 0.62)
const GOLD := Color(1.0, 0.82, 0.32)

## Digits and headings (squared-off techno). It has no "/" or "%": use LABEL_FONT for those.
const NUMBER_FONT := preload("res://Fonts/techno_hideo.ttf")
## Small captions ("HEALTH", "HOSTILE").
const LABEL_FONT := preload("res://Fonts/KHMenu-Bold.otf")

## Size of the cut-off corners on panels.
const CHAMFER := 10.0

## The mission panel, top left: hostiles and scrap (hud_timer.gd draws it; the enemy count
## and gold counter sit inside it).
const MISSION_POS := Vector2(16, 16)
const MISSION_SIZE := Vector2(216, 64)
const MISSION_ROW_HOSTILE := 12.0
const MISSION_ROW_SCRAP := 36.0
## The timer panel, top center.
const TIME_SIZE := Vector2(168, 56)
const TIME_TOP := 12.0


## Caption text spaced out a little, the way HUD captions usually are.
static func caption(text: String) -> String:
	return " ".join(text.to_upper().split(""))


## A label in the HUD style.
static func make_label(text: String, size: int, color := CYAN, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## The corners of a rect with two opposite corners cut off (top-left and bottom-right).
static func chamfer_points(r: Rect2, cut := CHAMFER) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), r.end - Vector2(cut, 0),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut),
	])


## A dark angled panel with faint scanlines and a thin accent outline.
static func draw_panel(ci: CanvasItem, r: Rect2, accent := CYAN, bg := PANEL_BG, cut := CHAMFER) -> void:
	var pts := chamfer_points(r, cut)
	ci.draw_colored_polygon(pts, bg)
	# Scanlines: every 3 px, very faint.
	var y := r.position.y + 1.0
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), Color(accent, 0.035), 1.0)
		y += 3.0
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(accent, 0.28), 1.0, true)
	# Brighter accent ticks on the two square corners.
	ci.draw_line(Vector2(r.end.x - 14, r.position.y), Vector2(r.end.x, r.position.y), accent, 2.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + 8), accent, 2.0)
	ci.draw_line(Vector2(r.position.x, r.end.y - 8), Vector2(r.position.x, r.end.y), accent, 2.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + 14, r.end.y), accent, 2.0)


## A segmented bar (like a mech's armor gauge) slanted to the right.
## fill and ghost are 0-1. Segments past `fill` up to `ghost` draw as a pale trail.
static func draw_segment_bar(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		segments := 40, gap := 2.0, slant := 4.0) -> void:
	var seg_w := (r.size.x - gap * (segments - 1) - slant) / segments
	for i in segments:
		var x := r.position.x + i * (seg_w + gap)
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var c : Color
		if fill >= t1:
			c = color
		elif fill > t0:
			c = color   # partly full segment: drawn narrower below
		elif ghost > t0:
			c = Color(WHITE, 0.55)
		else:
			c = Color(color, 0.12)
		var w := seg_w
		if fill > t0 and fill < t1:
			w = seg_w * (fill - t0) * segments
		var pts := PackedVector2Array([
			Vector2(x + slant, r.position.y), Vector2(x + slant + w, r.position.y),
			Vector2(x + w, r.end.y), Vector2(x, r.end.y),
		])
		ci.draw_colored_polygon(pts, c)
		if fill > t0 and fill < t1:   # the empty rest of a partly full segment
			var rest := PackedVector2Array([
				Vector2(x + slant + w, r.position.y), Vector2(x + slant + seg_w, r.position.y),
				Vector2(x + seg_w, r.end.y), Vector2(x + w, r.end.y),
			])
			ci.draw_colored_polygon(rest, Color(WHITE, 0.55) if ghost > t0 + w / seg_w / segments else Color(color, 0.12))
