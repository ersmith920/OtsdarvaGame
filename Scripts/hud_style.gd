# The HUD's look in one place, modeled on the ship computers in Alien (1979): plain vector
# displays, not decorated ones. Rules:
#   - Lines and text only. Thin single-weight frames, no gradients, bevels or fake depth.
#   - Two tones, like the Nostromo screens: cool blue-cyan for frames and structure, phosphor
#     green for data. Amber means caution, red means danger. Rarity colors are left alone.
#   - Boxed data fields ("SCRAP  1234"), inverted title bars (a solid strip with dark text),
#     "+" registration marks, plain uppercase monospace text, real abbreviations.
#   - Glow only where it carries meaning: live readouts, needles, warnings, selections.
#   - Motion: frames draw themselves on, readouts tick, the whole HUD trails the view a little
#     like symbology projected on a combiner glass (HudMotion).
# HUD scripts use these colors, fonts and drawing helpers so everything matches.
class_name HudStyle
extends RefCounted

# ---- Colors ----
## Data: phosphor green.
const PHOSPHOR := Color(0.55, 1.0, 0.6)
## Structure: frames, rules, marks.
const FRAME := Color(0.4, 0.78, 0.95, 0.8)
## Older name for the main accent (frames, rules, selections).
const CYAN := PHOSPHOR
const CYAN_DIM := Color(0.55, 1.0, 0.6, 0.6)
const CYAN_FAINT := Color(0.55, 1.0, 0.6, 0.15)
## Caution and danger.
const AMBER := Color(1.0, 0.7, 0.2)
const RED := Color(1.0, 0.3, 0.22)
## Bright text.
const WHITE := Color(0.88, 1.0, 0.9)
const GOLD := Color(1.0, 0.84, 0.35)
## Gauges.
const HP_COLOR := Color(0.55, 1.0, 0.6)
const EN_COLOR := Color(0.4, 0.85, 1.0)
const HP_RED := HP_COLOR
const EN_BLUE := EN_COLOR
## The pale trail left on a gauge when it drops.
const TRAIL := Color(1.0, 0.85, 0.55, 0.7)
## Screen backing (menus) and the faint backing behind HUD readouts.
const PANEL_TOP := Color(0.0, 0.025, 0.03, 0.9)
const PANEL_BOTTOM := Color(0.0, 0.025, 0.03, 0.9)
const HUD_BACKING := Color(0.0, 0.02, 0.02, 0.35)
const PANEL_EDGE := Color(0.4, 0.78, 0.95, 0.45)
## Dark ink: text on inverted (filled) bars, and the thin edge that keeps text readable.
const INK := Color(0.0, 0.05, 0.03)
const SHADOW := Color(0.0, 0.02, 0.02, 0.9)

# ---- Fonts (Share Tech Mono, open license: Fonts/ShareTechMono-OFL.txt) ----
const NUMBER_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
const MENU_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
const LABEL_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
## Number labels are drawn this much bigger than the size asked for.
const NUMBER_SCALE := 1.0

## Corner cut on panels: none, these are plain rectangles (kept for older callers).
const CUT := 0.0
const CAPTION_SPACING := 0

# ---- Layout (base UI pixels, 1152 x 648) ----
## Hostile and scrap block, top left (hud_timer.gd draws it; the enemy count and scrap
## counter sit inside it).
const MISSION_POS := Vector2(16, 16)
const MISSION_SIZE := Vector2(196, 56)
const MISSION_ROW_HOSTILE := 2.0
const MISSION_ROW_SCRAP := 30.0
const MISSION_ROW_HEIGHT := 24.0
## The mission clock, top center.
const TIME_SIZE := Vector2(132, 44)
const TIME_TOP := 10.0

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


## A label in the HUD style: plain monospace text with a thin dark edge for readability.
## number: a live readout (it gets the phosphor glow).
static func make_label(text: String, size: int, color := WHITE, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", roundi(size * (NUMBER_SCALE if number else 1.0)))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(SHADOW, 0.5))
	l.add_theme_constant_override("outline_size", 1)
	if number:
		add_phosphor(l, color)
	return l


## The phosphor glow: the text in this color with a soft halo of the same color behind it.
## Use it on live readouts and warnings, not on everything. Safe to call again to recolor.
static func add_phosphor(l: Control, color: Color, glow := 0.22) -> void:
	var size := l.get_theme_font_size("font_size")
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(color, color.a * glow))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", maxi(roundi(size * 0.6), 5))   # wide and soft: bloom, not an outline
	l.add_theme_color_override("font_outline_color", Color(SHADOW, 0.45))
	l.add_theme_constant_override("outline_size", 1)


## A small label ("HOSTILE", "MISSION TIME"): plain, dimmer than data.
static func make_caption(text: String, size := 10, color := CYAN_DIM) -> Label:
	return make_label(caption(text), size, color)


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


## The corners of a rect, with the top-left and bottom-right corners cut when cut > 0.
static func chamfer_points(r: Rect2, cut := CUT) -> PackedVector2Array:
	if cut <= 0.5:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	cut = minf(cut, minf(r.size.x, r.size.y) * 0.45)
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), r.end - Vector2(cut, 0),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut),
	])


## A HUD frame (HudPanelStyle drawn straight onto a CanvasItem). lit: 0-1 fills it with the
## accent (an inverted, selected field).
static func draw_panel(ci: CanvasItem, r: Rect2, accent := FRAME, lit := 0.0) -> void:
	_scratch.accent = accent
	_scratch.edge = accent
	_scratch.lit = lit
	_scratch.fill_top = HUD_BACKING
	_scratch.fill_bottom = HUD_BACKING
	HudPanelStyle.paint(ci.get_canvas_item(), r, _scratch)


## A frame drawn on: the outline traced clockwise from the top-left up to `progress` (0-1).
## Boot-up animations tween progress from 0 to 1.
static func draw_frame(ci: CanvasItem, r: Rect2, color: Color, progress := 1.0, width := 1.0, glow := 0.0) -> void:
	if progress <= 0.0:
		return
	# Bloom: wider, faint copies of the line underneath.
	if glow > 0.0:
		for g in [[7.0, 0.05], [3.5, 0.1]]:
			_frame_pass(ci, r, Color(color, color.a * g[1] * glow), progress, width + g[0])
	_frame_pass(ci, r, color, progress, width)


static func _frame_pass(ci: CanvasItem, r: Rect2, color: Color, progress: float, width: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	var total := 2.0 * (r.size.x + r.size.y)
	var left := total * clampf(progress, 0.0, 1.0)
	for i in 4:
		var a : Vector2 = pts[i]
		var b : Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		if left <= 0.0:
			break
		var t := minf(left / len, 1.0)
		ci.draw_line(a, a.lerp(b, t), color, width)
		left -= len


## A "+" registration mark.
static func draw_mark(ci: CanvasItem, at: Vector2, color := FRAME, size := 5.0) -> void:
	ci.draw_line(at - Vector2(size, 0), at + Vector2(size, 0), color, 1.0)
	ci.draw_line(at - Vector2(0, size), at + Vector2(0, size), color, 1.0)


## A line with a soft glow around it (needles, active markers).
static func draw_glow_line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width := 1.5, glow := 1.0) -> void:
	for i in [[10.0, 0.05], [5.0, 0.1], [2.5, 0.18]]:
		ci.draw_line(a, b, Color(color, color.a * i[1] * glow), width + i[0], true)
	ci.draw_line(a, b, color, width, true)


## A thin horizontal rule.
static func draw_divider(ci: CanvasItem, from: Vector2, length: float, color := PANEL_EDGE) -> void:
	ci.draw_line(from, from + Vector2(length, 0), color, 1.0)


## A bar-graph gauge: a thin frame with narrow segments inside. fill and ghost are 0-1;
## segments between them show in the trail color. from_right: drains from the left end.
## segment: length of one segment including its gap, in pixels.
static func draw_gauge(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		trail := TRAIL, from_right := true, segment := 5.0) -> void:
	ci.draw_rect(r.grow(2.0), Color(color, 0.35), false, 1.0)
	var count := maxi(roundi(r.size.x / segment), 1)
	var seg_w := r.size.x / count
	var gap := minf(1.5, seg_w * 0.35)
	for i in count:
		var k := (count - 1 - i) if from_right else i
		var at := (k + 0.5) / count
		var c := Color(color, 0.08)
		if at <= fill:
			c = color
		elif at <= ghost:
			c = trail
		ci.draw_rect(Rect2(r.position.x + i * seg_w + gap * 0.5, r.position.y, seg_w - gap, r.size.y), c)


## A flat fill (kept for older callers).
static func _gloss_fill(ci: CanvasItem, r: Rect2, color: Color, _radius: float) -> void:
	ci.draw_rect(r, color)


## A thick arc (kept for older callers).
static func draw_gauge_arc(ci: CanvasItem, center: Vector2, radius: float, from_angle: float,
		to_angle: float, width: float, color: Color) -> void:
	if absf(to_angle - from_angle) > 0.001:
		ci.draw_arc(center, radius, from_angle, to_angle, 40, color, width, true)


## A scan sweep: a bright line passing down a panel with a short fading trail, like a CRT
## redrawing. t: progress 0-1 (tween it to play it).
static func draw_glint(ci: CanvasItem, r: Rect2, t: float, strength := 1.0) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	var y := lerpf(r.position.y, r.end.y, t)
	var top := maxf(y - 16.0, r.position.y)
	if y > top:
		ci.draw_rect(Rect2(r.position.x + 1.0, top, r.size.x - 2.0, y - top), Color(PHOSPHOR, 0.06 * strength))
	ci.draw_rect(Rect2(r.position.x + 1.0, y - 1.0, r.size.x - 2.0, 1.0), Color(PHOSPHOR, 0.45 * strength))


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
# Menus: panels, cards, tiles, buttons and headers in the same language
# ======================================================================

## A menu panel (columns, windows, tooltips): dark screen with a thin frame.
## fill_alpha scales how see-through it is.
static func panel_style(accent := FRAME, padding := 12.0, fill_alpha := 1.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.accent = accent
	s.edge = Color(accent, 0.6)
	s.fill_top = Color(PANEL_TOP, PANEL_TOP.a * fill_alpha)
	s.fill_bottom = s.fill_top
	s.set_content_margin_all(padding)
	return s


## A card frame (gun store cards, Combiner slots) in a rarity color. lit: 0 normal, about
## 0.5 hovered, 1 pressed. Empty slots use empty_card_style().
static func card_style(color: Color, lit := 0.0, padding := 10.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_card(s, color, lit)
	s.marks = 5.0
	s.edge_width = 1.5
	s.set_content_margin_all(padding)
	return s


## Recolors a card style (Mythic frames call this every frame with the rainbow color).
static func color_card(s: HudPanelStyle, color: Color, lit := 0.0) -> void:
	s.accent = color
	s.edge = Color(color, 0.85 + 0.15 * lit)
	s.fill_top = Color(0.0, 0.025, 0.03, 0.92).lerp(Color(color.darkened(0.75), 0.92), 0.12 + 0.15 * lit)
	s.fill_bottom = s.fill_top
	s.glow = Color(color, 0.8)
	s.glow_size = 6.0 + 8.0 * lit
	s.inner_glow = Color(color, 0.6)
	s.inner_glow_size = 6.0 + 4.0 * lit


## An empty card frame (nothing in the slot yet): dim, dashed.
static func empty_card_style(padding := 10.0) -> HudPanelStyle:
	var s := panel_style(FRAME, padding)
	s.edge = Color(FRAME, 0.3)
	s.dashed = true
	s.marks = 5.0
	return s


## A small square tile (items, weapons) in a tier / rarity color.
static func tile_style(color: Color) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_tile(s, color)
	return s


static func color_tile(s: HudPanelStyle, color: Color) -> void:
	s.accent = color
	s.edge = Color(color, 0.85)
	s.fill_top = Color(color.darkened(0.8), 0.55)
	s.fill_bottom = s.fill_top
	s.glow = Color(color, 0.6)
	s.glow_size = 4.0


## An empty tile (an empty gun slot): dim dashed outline.
static func empty_tile_style() -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.fill_top = Color(0.0, 0.02, 0.02, 0.35)
	s.fill_bottom = s.fill_top
	s.edge = Color(FRAME, 0.3)
	s.dashed = true
	return s


## A command button: a thin outlined box with plain text. Hovered, the box fills with the
## accent from left to right and the text inverts to dark ink, like a selected field on a
## ship terminal. Pressing punches it. Hover / click sounds included. A disabled button goes
## dim and dashed and ignores hovers. slide: nudges right when hovered (left-aligned lists).
static func make_button(text: String, min_size := Vector2(200, 44), font_size := 18, accent := PHOSPHOR,
		slide := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	button.alignment = align
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 16 if align == HORIZONTAL_ALIGNMENT_LEFT else 12
		box.content_margin_right = 12
		button.add_theme_stylebox_override(st, box)
	button.add_theme_font_override("font", spaced(MENU_FONT, 2))
	button.add_theme_font_size_override("font_size", font_size)
	var set_ink := func(lit: float) -> void:
		var c := accent.lerp(INK, smoothstep(0.35, 0.65, lit))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(key, c)
	set_ink.call(0.0)
	button.add_theme_color_override("font_disabled_color", Color(accent, 0.3))
	button.add_theme_constant_override("outline_size", 0)
	button.set_meta(&"lit", 0.0)
	# The box is drawn by a child shown behind the button, so the text stays on top.
	var plate := Control.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	button.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.draw.connect(func() -> void:
		var lit : float = button.get_meta(&"lit")
		var r := Rect2(Vector2(lit * 6.0 if slide else 0.0, 0), button.size)
		if button.disabled:
			_dashed_rect(plate, r, Color(accent, 0.25))
			return
		plate.draw_rect(r, Color(0.0, 0.025, 0.03, 0.75))
		if lit > 0.0:
			# The fill sweeps in from the left, with a soft glow once it's full.
			var w := r.size.x * smoothstep(0.0, 1.0, lit)
			plate.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), Color(accent, 0.92))
			if lit > 0.9:
				plate.draw_rect(r.grow(2.0), Color(accent, 0.18), false, 3.0)
		plate.draw_rect(r, accent, false, 1.0))
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


static func _dashed_rect(ci: CanvasItem, r: Rect2, color: Color, dash := 4.0, gap := 3.0) -> void:
	for side in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		var a : Vector2 = side[0]
		var b : Vector2 = side[1]
		var len := a.distance_to(b)
		var d := 0.0
		while d < len:
			ci.draw_line(a.lerp(b, d / len), a.lerp(b, minf(d + dash, len) / len), color, 1.0)
			d += dash + gap


## A section header: plain caption with a thin full-width rule under it.
static func make_header(text: String, size := 13, color := CYAN_DIM, align := HORIZONTAL_ALIGNMENT_LEFT,
		accent := FRAME) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	var label := make_label(caption(text), size, color)
	label.horizontal_alignment = align
	box.add_child(label)
	box.add_child(make_rule(align == HORIZONTAL_ALIGNMENT_CENTER, accent))
	box.set_meta(&"label", label)
	return box


## A thin rule.
static func make_rule(_centered := false, accent := FRAME) -> Control:
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size.y = 1
	rule.draw.connect(func() -> void: rule.draw_rect(Rect2(0, 0, rule.size.x, 1), Color(accent, 0.5)))
	return rule


## A menu title as an inverted bar: a solid green strip with dark text (Alien's "ENV:
## EUROPA" header). Returns a box; its meta "label" is the Label.
static func make_title(text: String, size := 30) -> Control:
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = PHOSPHOR
	fill.content_margin_left = 18
	fill.content_margin_right = 18
	fill.content_margin_top = 2
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("panel", fill)
	var label := Label.new()
	label.text = text.to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", spaced(MENU_FONT, maxi(roundi(size * 0.12), 1)))
	label.add_theme_font_size_override("font_size", roundi(size * 0.8))
	label.add_theme_color_override("font_color", INK)
	bar.add_child(label)
	# Bloom around the strip, and two thin scan gaps cutting through it (like CRT type).
	bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, bar.size)
		for g in [[14.0, 0.05], [8.0, 0.08], [3.0, 0.14]]:
			bar.draw_rect(r.grow(g[0] * 0.5), Color(PHOSPHOR, g[1]), false, g[0]))
	var gaps := Control.new()
	gaps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gaps.draw.connect(func() -> void:
		for f in [0.62, 0.76]:
			gaps.draw_rect(Rect2(-18, gaps.size.y * f, gaps.size.x + 36, 1.5), Color(INK, 0.85)))
	bar.add_child(gaps)
	bar.set_meta(&"label", label)
	return bar


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
		s.fill_top = Color(0.0, 0.025, 0.03, 0.75)
		s.fill_bottom = s.fill_top
		s.lit = {"normal": 0.0, "hover": 1.0, "pressed": 1.0, "disabled": 0.0, "hover_pressed": 1.0}[state]
		s.accent = PHOSPHOR
		s.edge = Color(PHOSPHOR, 0.3) if state == "disabled" else PHOSPHOR
		s.dashed = state == "disabled"
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		t.set_stylebox(state, "Button", s)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", spaced(MENU_FONT, 1))
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Button", PHOSPHOR)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(PHOSPHOR, 0.3))

	# Toggles: label plus a box, outlined when off and filled when on (Manual / Auto).
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font("font", "CheckButton", spaced(MENU_FONT, 1))
	t.set_font_size("font_size", "CheckButton", 15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", PHOSPHOR)
	t.set_icon("checked", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked", "CheckButton", _switch_texture(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_texture(false))

	# Thin scrollbars.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(FRAME, 0.08)
		track.set_content_margin_all(2)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		for g in [["grabber", 0.5], ["grabber_highlight", 0.8], ["grabber_pressed", 1.0]]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(FRAME, g[1])
			t.set_stylebox(g[0], bar, grab)

	var line := StyleBoxLine.new()
	line.color = PANEL_EDGE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	_theme = t
	return t


# A toggle box: [ON ] filled when on, an empty outlined box when off.
static func _switch_texture(on: bool) -> Texture2D:
	const W := 30
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(PHOSPHOR if on else Color(0, 0, 0, 0))
	if not on:
		for x in W:
			img.set_pixel(x, 0, PHOSPHOR)
			img.set_pixel(x, H - 1, PHOSPHOR)
		for y in H:
			img.set_pixel(0, y, PHOSPHOR)
			img.set_pixel(W - 1, y, PHOSPHOR)
	return ImageTexture.create_from_image(img)
