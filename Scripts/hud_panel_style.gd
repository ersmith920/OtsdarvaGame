# The HUD block look (see HudStyle) as a StyleBox, so any Panel, PanelContainer or Button can
# wear it: a block with its top-right and bottom-left corners cut at 45 degrees, a vertical
# gradient fill (fill_top to fill_bottom), a thick outline (solid, or dashed for empty /
# disabled), and optionally a glow around it and a fill sweeping in from the left (hover).
#
#   panel.add_theme_stylebox_override("panel", HudStyle.panel_style(color))
#
# Changing a property redraws whatever uses the style (Mythic frames recolor it every frame).
# HudStyle.draw_panel() draws the same thing straight onto a CanvasItem.
class_name HudPanelStyle
extends StyleBox

## Accent: the sweep / lit fill and the marks.
var accent := HudStyle.ORANGE:
	set(v): accent = v; emit_changed()
## Gradient fill, top and bottom.
var fill_top := HudStyle.PANEL_BOTTOM:
	set(v): fill_top = v; emit_changed()
var fill_bottom := HudStyle.PANEL_BOTTOM:
	set(v): fill_bottom = v; emit_changed()
## The outline.
var edge := HudStyle.PANEL_EDGE:
	set(v): edge = v; emit_changed()
var edge_width := 2.0:
	set(v): edge_width = v; emit_changed()
## How far the top-right and bottom-left corners are cut (0 = square).
var cut := HudStyle.CUT:
	set(v): cut = v; emit_changed()
## Dashed outline (empty slots, disabled controls).
var dashed := false:
	set(v): dashed = v; emit_changed()
## Size of "+" marks inside the corners (0 = none).
var marks := 0.0:
	set(v): marks = v; emit_changed()
## Glow around the outside (size 0 = none).
var glow := Color(0, 0, 0, 0):
	set(v): glow = v; emit_changed()
var glow_size := 0.0:
	set(v): glow_size = v; emit_changed()
## 0-1: an accent gradient fill sweeping in from the left (hover).
var sweep := 0.0:
	set(v): sweep = v; emit_changed()
## 0-1: fills the whole block with the accent.
var lit := 0.0:
	set(v): lit = v; emit_changed()
## Kept for older callers (unused by this look).
var inner_glow := Color(0, 0, 0, 0)
var inner_glow_size := 0.0
var bracket := 0.0
var bracket_width := 1.0
var bar := false
var scanlines := false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	paint(to_canvas_item, rect, self)


## Draws a block with the look of `s` (any HudPanelStyle) onto a canvas item.
static func paint(rid: RID, r: Rect2, s: HudPanelStyle) -> void:
	var rs := RenderingServer
	var pts := HudStyle.chamfer_points(r, s.cut)
	# Glow: rings fading outward.
	if s.glow_size > 0.0 and s.glow.a > 0.0:
		var rings := 4
		for i in range(rings, 0, -1):
			var grow := s.glow_size * i / rings
			var c := Color(s.glow, s.glow.a * 0.25 * (1.0 - float(i - 1) / rings))
			rs.canvas_item_add_polyline(rid, _closed(HudStyle.chamfer_points(r.grow(grow), s.cut + grow * 0.4)),
					PackedColorArray([c]), s.glow_size / rings + 1.0, true)
	# Gradient fill.
	var cols := PackedColorArray()
	for p in pts:
		cols.append(s.fill_top.lerp(s.fill_bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	rs.canvas_item_add_polygon(rid, pts, cols)
	# Accent fills: the whole block (lit), or a sweep from the left (hover).
	var amount := maxf(s.lit, s.sweep)
	if amount > 0.0:
		var w := r.size.x * (1.0 if s.lit >= s.sweep else smoothstep(0.0, 1.0, s.sweep))
		var clip := Rect2(r.position, Vector2(w, r.size.y))
		var area := Geometry2D.intersect_polygons(pts, PackedVector2Array([clip.position,
				Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)]))
		var top := s.accent   # flat accent fill
		var bottom := s.accent
		for raw in area:
			var piece := HudStyle._clean_polygon(raw)   # skip slivers the renderer can't triangulate
			if piece.is_empty():
				continue
			var pc := PackedColorArray()
			for p in piece:
				var t := clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)
				pc.append(Color(top.lerp(bottom, t), 0.95 * minf(amount * 1.5, 1.0)))
			rs.canvas_item_add_polygon(rid, piece, pc)
	# Outline.
	if s.dashed:
		_dashed(rid, pts, s.edge, s.edge_width)
	else:
		rs.canvas_item_add_polyline(rid, _closed(pts), PackedColorArray([s.edge]), s.edge_width, true)
	# "+" marks inside the corners.
	if s.marks > 0.0 and r.size.x > s.marks * 6.0 and r.size.y > s.marks * 6.0:
		var m := s.marks
		var inset := m * 2.0
		var mc := Color(s.accent, 0.8)
		for p in [r.position + Vector2(inset, inset), Vector2(r.end.x - inset, r.position.y + inset),
				r.end - Vector2(inset, inset), Vector2(r.position.x + inset, r.end.y - inset)]:
			rs.canvas_item_add_line(rid, p - Vector2(m, 0), p + Vector2(m, 0), mc, 1.5)
			rs.canvas_item_add_line(rid, p - Vector2(0, m), p + Vector2(0, m), mc, 1.5)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


static func _dashed(rid: RID, pts: PackedVector2Array, color: Color, width: float, dash := 5.0, gap := 4.0) -> void:
	var lines := PackedVector2Array()
	var loop := _closed(pts)
	for i in loop.size() - 1:
		var a := loop[i]
		var b := loop[i + 1]
		var len := a.distance_to(b)
		var d := 0.0
		while d < len:
			lines.append(a.lerp(b, d / len))
			lines.append(a.lerp(b, minf(d + dash, len) / len))
			d += dash + gap
	RenderingServer.canvas_item_add_multiline(rid, lines, PackedColorArray([color]), width)
