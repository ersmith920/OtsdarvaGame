# The HUD panel look (see HudStyle) as a StyleBox, so any Panel, PanelContainer or Button can
# wear it: a dark phosphor-screen panel with faint scanlines, two slightly cut corners, a
# double-rule border, accent corner ticks, a short accent bar on the left edge and optional
# glows around and inside it.
#
#   panel.add_theme_stylebox_override("panel", HudStyle.panel_style(color))
#
# Changing a property redraws whatever uses the style (Mythic frames recolor it every frame).
# HudStyle.draw_panel() draws the same thing straight onto a CanvasItem (the HUD readouts).
class_name HudPanelStyle
extends StyleBox

## Accent: corner brackets and the left bar.
var accent := HudStyle.CYAN:
	set(v): accent = v; emit_changed()
## Glass fill, top and bottom of the gradient.
var fill_top := HudStyle.PANEL_TOP:
	set(v): fill_top = v; emit_changed()
var fill_bottom := HudStyle.PANEL_BOTTOM:
	set(v): fill_bottom = v; emit_changed()
## Hairline border.
var edge := HudStyle.PANEL_EDGE:
	set(v): edge = v; emit_changed()
var edge_width := 1.0:
	set(v): edge_width = v; emit_changed()
## How far the top-left and bottom-right corners are cut.
var cut := HudStyle.CUT:
	set(v): cut = v; emit_changed()
## Corner bracket length (0 = none) and thickness.
var bracket := 10.0:
	set(v): bracket = v; emit_changed()
var bracket_width := 1.5:
	set(v): bracket_width = v; emit_changed()
## The accent bar on the left edge.
var bar := true:
	set(v): bar = v; emit_changed()
## Soft glow around the outside (size 0 = none).
var glow := Color(0, 0, 0, 0):
	set(v): glow = v; emit_changed()
var glow_size := 0.0:
	set(v): glow_size = v; emit_changed()
## Soft glow along the inside of the border, fading in toward the middle (size 0 = none).
var inner_glow := Color(0, 0, 0, 0):
	set(v): inner_glow = v; emit_changed()
var inner_glow_size := 0.0:
	set(v): inner_glow_size = v; emit_changed()
## Faint horizontal scanlines across the panel (the CRT look).
var scanlines := true:
	set(v): scanlines = v; emit_changed()
## 0-1: lights the panel up in the accent color (hover / pressed).
var lit := 0.0:
	set(v): lit = v; emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	paint(to_canvas_item, rect, self)


## Draws a panel with the look of `s` (any HudPanelStyle) onto a canvas item.
static func paint(rid: RID, r: Rect2, s: HudPanelStyle) -> void:
	var rs := RenderingServer
	var a := s.accent
	var lit := s.lit
	# Glow: rings of fading accent around the outside.
	if s.glow_size > 0.0 and s.glow.a > 0.0:
		var rings := 5
		for i in range(rings, 0, -1):
			var grow := s.glow_size * i / rings
			var ring := _closed(HudStyle.chamfer_points(r.grow(grow), s.cut + grow * 0.4))
			var c := Color(s.glow, s.glow.a * 0.4 * (1.0 - float(i - 1) / rings) * (1.0 - float(i) / (rings + 1)))
			rs.canvas_item_add_polyline(rid, ring, PackedColorArray([c]), s.glow_size / rings + 1.0, true)
	# Glass fill.
	var pts := HudStyle.chamfer_points(r, s.cut)
	var top := s.fill_top.lerp(Color(a.darkened(0.55), maxf(s.fill_top.a, 0.85)), lit * 0.6)
	var bottom := s.fill_bottom.lerp(Color(a.darkened(0.7), maxf(s.fill_bottom.a, 0.8)), lit * 0.4)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	rs.canvas_item_add_polygon(rid, pts, cols)
	# Scanlines: a faint line every few pixels, kept inside the cut corners.
	if s.scanlines and r.size.y > 6.0:
		var lines := PackedVector2Array()
		var y := r.position.y + 2.0
		while y < r.end.y - 1.0:
			var inset_l := maxf(s.cut - (y - r.position.y), 0.0) + 1.0
			var inset_r := maxf(s.cut - (r.end.y - y), 0.0) + 1.0
			lines.append(Vector2(r.position.x + inset_l, y))
			lines.append(Vector2(r.end.x - inset_r, y))
			y += 3.0
		rs.canvas_item_add_multiline(rid, lines, PackedColorArray([Color(a, 0.045 + 0.04 * lit)]), 1.0)
	# Inner glow: rings just inside the border, brightest at the border.
	if s.inner_glow_size > 0.0 and s.inner_glow.a > 0.0:
		var rings := 6
		var step := s.inner_glow_size / rings
		for i in rings:
			var inset := step * (i + 0.5)
			var inner := r.grow(-inset)
			if inner.size.x <= 2.0 or inner.size.y <= 2.0:
				break
			var fade := 1.0 - float(i) / rings
			var c := Color(s.inner_glow, s.inner_glow.a * 0.5 * fade * fade)
			rs.canvas_item_add_polyline(rid, _closed(HudStyle.chamfer_points(inner, maxf(s.cut - inset * 0.4, 0.0))),
					PackedColorArray([c]), step + 0.5, true)
	# Border.
	var edge := s.edge.lerp(Color(a, maxf(s.edge.a, 0.7)), lit)
	rs.canvas_item_add_polyline(rid, _closed(pts), PackedColorArray([edge]), s.edge_width, true)
	# A second, fainter rule just inside the first (the double border of a console panel).
	if r.size.x > 12.0 and r.size.y > 12.0:
		var inner_pts := HudStyle.chamfer_points(r.grow(-3.0), maxf(s.cut - 1.2, 0.0))
		rs.canvas_item_add_polyline(rid, _closed(inner_pts), PackedColorArray([Color(edge, edge.a * 0.35)]), 1.0, true)
	# Corner brackets on the two uncut corners.
	var b := minf(s.bracket, minf(r.size.x, r.size.y) * 0.4)
	if b > 0.0:
		var bc := PackedColorArray([Color(a, 0.85 + 0.15 * lit)])
		rs.canvas_item_add_polyline(rid, PackedVector2Array([Vector2(r.end.x - b, r.position.y),
				Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + b)]), bc, s.bracket_width)
		rs.canvas_item_add_polyline(rid, PackedVector2Array([Vector2(r.position.x, r.end.y - b),
				Vector2(r.position.x, r.end.y), Vector2(r.position.x + b, r.end.y)]), bc, s.bracket_width)
	# Accent bar on the left edge (grows when lit).
	if s.bar:
		var h := r.size.y * (0.4 + 0.6 * lit)
		rs.canvas_item_add_rect(rid, Rect2(r.position.x + 1.0, r.get_center().y - h * 0.5, 2.0 + lit, h), Color(a, 0.9))
	# A small status lamp in the top-left corner, lit with the accent.
	if s.bar and r.size.y > 18.0 and r.size.x > 30.0:
		rs.canvas_item_add_rect(rid, Rect2(r.position.x + s.cut + 4.0, r.position.y + 4.0, 5.0, 2.0), Color(a, 0.6 + 0.4 * lit))


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
