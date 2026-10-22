# The HUD frame look (see HudStyle) as a StyleBox, so any Panel, PanelContainer or Button can
# wear it: a dark screen area with a thin frame (solid, or dashed for empty / disabled),
# optional "+" registration marks inside the corners, and optional glows in the frame color.
#
#   panel.add_theme_stylebox_override("panel", HudStyle.panel_style(color))
#
# Changing a property redraws whatever uses the style (Mythic frames recolor it every frame).
# HudStyle.draw_panel() draws the same thing straight onto a CanvasItem.
class_name HudPanelStyle
extends StyleBox

## Accent: the marks, the selection fill (lit) and the glows' default color.
var accent := HudStyle.FRAME:
	set(v): accent = v; emit_changed()
## Screen fill (fill_bottom is kept for older callers; the fill is flat).
var fill_top := HudStyle.PANEL_TOP:
	set(v): fill_top = v; emit_changed()
var fill_bottom := HudStyle.PANEL_BOTTOM:
	set(v): fill_bottom = v; emit_changed()
## The frame line.
var edge := HudStyle.PANEL_EDGE:
	set(v): edge = v; emit_changed()
var edge_width := 1.0:
	set(v): edge_width = v; emit_changed()
## Dashed frame (empty slots, disabled controls).
var dashed := false:
	set(v): dashed = v; emit_changed()
## Size of the "+" marks inside the corners (0 = none).
var marks := 0.0:
	set(v): marks = v; emit_changed()
## Soft glow around the outside (size 0 = none).
var glow := Color(0, 0, 0, 0):
	set(v): glow = v; emit_changed()
var glow_size := 0.0:
	set(v): glow_size = v; emit_changed()
## Soft glow just inside the frame, fading toward the middle (size 0 = none).
var inner_glow := Color(0, 0, 0, 0):
	set(v): inner_glow = v; emit_changed()
var inner_glow_size := 0.0:
	set(v): inner_glow_size = v; emit_changed()
## 0-1: fills the panel with the accent (a selected, inverted field).
var lit := 0.0:
	set(v): lit = v; emit_changed()
## Kept for older callers (the frame look no longer uses them).
var cut := 0.0
var bracket := 0.0
var bracket_width := 1.0
var bar := false
var scanlines := false


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	paint(to_canvas_item, rect, self)


## Draws a panel with the look of `s` (any HudPanelStyle) onto a canvas item.
static func paint(rid: RID, r: Rect2, s: HudPanelStyle) -> void:
	var rs := RenderingServer
	# Outer glow: rings fading outward.
	if s.glow_size > 0.0 and s.glow.a > 0.0:
		var rings := 4
		for i in range(rings, 0, -1):
			var grow := s.glow_size * i / rings
			var c := Color(s.glow, s.glow.a * 0.22 * (1.0 - float(i - 1) / rings))
			rs.canvas_item_add_polyline(rid, _rect_loop(r.grow(grow)), PackedColorArray([c]), s.glow_size / rings + 1.0, true)
	# Screen fill, and the selection fill on top of it.
	rs.canvas_item_add_rect(rid, r, s.fill_top)
	if s.lit > 0.0:
		rs.canvas_item_add_rect(rid, r, Color(s.accent, 0.9 * s.lit))
	# Inner glow.
	if s.inner_glow_size > 0.0 and s.inner_glow.a > 0.0:
		var rings := 5
		var step := s.inner_glow_size / rings
		for i in rings:
			var inner := r.grow(-step * (i + 0.5))
			if inner.size.x <= 2.0 or inner.size.y <= 2.0:
				break
			var fade := 1.0 - float(i) / rings
			rs.canvas_item_add_polyline(rid, _rect_loop(inner),
					PackedColorArray([Color(s.inner_glow, s.inner_glow.a * 0.35 * fade * fade)]), step + 0.5, true)
	# Frame.
	if s.dashed:
		_dashed(rid, r, s.edge, s.edge_width)
	else:
		rs.canvas_item_add_polyline(rid, _rect_loop(r), PackedColorArray([s.edge]), s.edge_width, true)
	# "+" marks inside the corners.
	if s.marks > 0.0 and r.size.x > s.marks * 6.0 and r.size.y > s.marks * 6.0:
		var m := s.marks
		var inset := m * 2.0
		var mc := Color(s.accent, 0.7)
		for p in [r.position + Vector2(inset, inset), Vector2(r.end.x - inset, r.position.y + inset),
				r.end - Vector2(inset, inset), Vector2(r.position.x + inset, r.end.y - inset)]:
			rs.canvas_item_add_line(rid, p - Vector2(m, 0), p + Vector2(m, 0), mc, 1.0)
			rs.canvas_item_add_line(rid, p - Vector2(0, m), p + Vector2(0, m), mc, 1.0)


static func _rect_loop(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])


static func _dashed(rid: RID, r: Rect2, color: Color, width: float, dash := 4.0, gap := 3.0) -> void:
	var pts := PackedVector2Array()
	var loop := _rect_loop(r)
	for i in 4:
		var a := loop[i]
		var b := loop[i + 1]
		var len := a.distance_to(b)
		var d := 0.0
		while d < len:
			pts.append(a.lerp(b, d / len))
			pts.append(a.lerp(b, minf(d + dash, len) / len))
			d += dash + gap
	RenderingServer.canvas_item_add_multiline(rid, pts, PackedColorArray([color]), width)


## Older helper (kept for callers): a closed copy of a point list.
static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
