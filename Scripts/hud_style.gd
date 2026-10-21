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
static var _scratch := HudPanelStyle.new()   # reused by draw_panel
static var _spaced_fonts := {}
static var _theme : Theme


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
## lit (0-1) brightens it (hovered buttons). Same look as HudPanelStyle (it does the drawing).
static func draw_panel(ci: CanvasItem, r: Rect2, accent := CYAN, lit := 0.0) -> void:
	_scratch.accent = accent
	_scratch.lit = lit
	HudPanelStyle.paint(ci.get_canvas_item(), r, _scratch)


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



# ======================================================================
# Menus: the same look for panels, cards, tiles, buttons and headers
# ======================================================================

## A font with extra space between letters (cached, so labels can share it).
static func spaced(base: Font, spacing: int) -> Font:
	var key := [base, spacing]
	if not _spaced_fonts.has(key):
		var f := FontVariation.new()
		f.base_font = base
		f.spacing_glyph = spacing
		_spaced_fonts[key] = f
	return _spaced_fonts[key]


## A menu panel (columns, windows, tooltips). fill_alpha scales how see-through it is.
static func panel_style(accent := CYAN, padding := 12.0, fill_alpha := 1.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.accent = accent
	s.fill_top = Color(PANEL_TOP, PANEL_TOP.a * fill_alpha)
	s.fill_bottom = Color(PANEL_BOTTOM, PANEL_BOTTOM.a * fill_alpha)
	s.set_content_margin_all(padding)
	return s


## A big card frame (gun store cards, Combiner slots) in a rarity color. lit: 0 normal,
## about 0.5 hovered, 1 pressed. Empty slots use empty_card_style().
static func card_style(color: Color, lit := 0.0, padding := 10.0) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_card(s, color, lit)
	s.cut = 10.0
	s.bracket = 16.0
	s.bracket_width = 2.0
	s.edge_width = 2.0
	s.bar = false
	s.set_content_margin_all(padding)
	return s


## Recolors a card style (Mythic frames call this every frame with the rainbow color).
static func color_card(s: HudPanelStyle, color: Color, lit := 0.0) -> void:
	s.accent = color.lerp(Color.WHITE, 0.3 + 0.4 * lit)
	s.edge = Color(color.lerp(Color.WHITE, 0.15 + 0.3 * lit), 0.75 + 0.25 * lit)
	s.fill_top = Color(0.04, 0.06, 0.1, 0.92).lerp(Color(color.darkened(0.6), 0.92), 0.22 + 0.18 * lit)
	s.fill_bottom = Color(0.02, 0.03, 0.05, 0.94).lerp(Color(color.darkened(0.75), 0.94), 0.15 + 0.1 * lit)
	s.glow = Color(color, 0.9)
	s.glow_size = 12.0 + 10.0 * lit
	# Bright glow hugging the inside of the border (stronger when hovered).
	s.inner_glow = Color(color.lerp(Color.WHITE, 0.2), 0.9 + 0.1 * lit)
	s.inner_glow_size = 12.0 + 6.0 * lit


## An empty card frame (nothing in the slot yet).
static func empty_card_style(padding := 10.0) -> HudPanelStyle:
	var s := card_style(Color(0.5, 0.55, 0.6), 0.0, padding)
	s.edge = Color(0.55, 0.65, 0.75, 0.3)
	s.accent = Color(0.6, 0.7, 0.8, 0.6)
	s.fill_top = PANEL_TOP
	s.fill_bottom = PANEL_BOTTOM
	s.glow_size = 0.0
	s.inner_glow_size = 0.0
	return s


## A small square tile (items, weapons) in a tier / rarity color.
static func tile_style(color: Color) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_tile(s, color)
	s.cut = 6.0
	s.bracket = 8.0
	s.bar = false
	return s


static func color_tile(s: HudPanelStyle, color: Color) -> void:
	s.accent = color.lerp(Color.WHITE, 0.45)
	s.edge = Color(color.lerp(Color.WHITE, 0.2), 0.7)
	s.fill_top = Color(color.darkened(0.7), 0.6)
	s.fill_bottom = Color(color.darkened(0.85), 0.6)
	s.glow = Color(color, 0.8)
	s.glow_size = 8.0


## An empty tile (an empty gun slot).
static func empty_tile_style() -> HudPanelStyle:
	var s := HudPanelStyle.new()
	s.cut = 6.0
	s.bracket = 0.0
	s.bar = false
	s.fill_top = Color(0.0, 0.0, 0.0, 0.35)
	s.fill_bottom = Color(0.0, 0.0, 0.0, 0.35)
	s.edge = Color(0.55, 0.65, 0.75, 0.3)
	return s


## A command button in the HUD style: a panel drawn behind letter-spaced text. Hovered, it
## lights up in the accent color and its accent bar grows (slide: it also nudges right, for
## left-aligned menu lists; otherwise it grows a little, for centered buttons). Pressing
## punches it. Hover / click sounds included. A disabled button dims and ignores hovers.
static func make_button(text: String, min_size := Vector2(200, 44), font_size := 18, accent := CYAN,
		slide := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	button.alignment = align
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 24 if align == HORIZONTAL_ALIGNMENT_LEFT else 12
		box.content_margin_right = 12
		button.add_theme_stylebox_override(st, box)
	button.add_theme_font_override("font", spaced(MENU_FONT, 3))
	button.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(c, WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.66, 0.6))
	button.add_theme_color_override("font_outline_color", Color(SHADOW, 0.8))
	button.add_theme_constant_override("outline_size", 3)
	button.set_meta(&"lit", 0.0)
	# The panel is drawn by a child shown behind the button, so the text stays on top.
	var plate := Control.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	button.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := HudPanelStyle.new()
	plate.draw.connect(func() -> void:
		var lit : float = button.get_meta(&"lit")
		var r := Rect2(Vector2(lit * 8.0 if slide else 0.0, 0), button.size)
		style.accent = Color(0.5, 0.56, 0.62, 0.6) if button.disabled else accent
		style.lit = 0.0 if button.disabled else lit
		HudPanelStyle.paint(plate.get_canvas_item(), r, style))
	var light := func(to: float) -> void:
		var t := UIJuice.tween_of(button)
		t.tween_method(func(v: float) -> void:
			button.set_meta(&"lit", v)
			plate.queue_redraw(), button.get_meta(&"lit"), to, 0.12)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		light.call(1.0)
		UIJuice.play(UIJuice.Sfx.HOVER))
	button.mouse_exited.connect(func() -> void: light.call(0.0))
	button.button_down.connect(func() -> void:
		UIJuice.play(UIJuice.Sfx.CLICK)
		UIJuice.punch(button, -0.06))
	# Redraw when it's enabled / disabled (Godot doesn't redraw children for that).
	button.draw.connect(plate.queue_redraw)
	if not slide:
		button.mouse_entered.connect(func() -> void:
			if not button.disabled:
				UIJuice.center_pivot(button)
				UIJuice.tween_of(plate).tween_property(button, "scale", Vector2.ONE * 1.04, 0.12) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		button.mouse_exited.connect(func() -> void:
			UIJuice.tween_of(plate).tween_property(button, "scale", Vector2.ONE, 0.12))
	return button


## A section header: letter-spaced caption with a hairline rule under it and a short accent
## segment at the start of the rule (centered headers center it).
static func make_header(text: String, size := 13, color := CYAN_DIM, align := HORIZONTAL_ALIGNMENT_LEFT,
		accent := CYAN) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	var label := make_label(caption(text), size, color)
	label.add_theme_font_override("font", spaced(LABEL_FONT, maxi(roundi(size * 0.22), 2)))
	label.horizontal_alignment = align
	box.add_child(label)
	box.add_child(make_rule(align == HORIZONTAL_ALIGNMENT_CENTER, accent))
	box.set_meta(&"label", label)
	return box


## A hairline rule with a short accent segment (at the left, or the middle when centered).
static func make_rule(centered := false, accent := CYAN) -> Control:
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size.y = 3
	rule.draw.connect(func() -> void:
		var w := rule.size.x
		rule.draw_rect(Rect2(0, 1, w, 1), PANEL_EDGE)
		var seg := minf(48.0, w * 0.3)
		var x := (w - seg) * 0.5 if centered else 0.0
		rule.draw_rect(Rect2(x, 0, seg, 3), Color(accent, 0.9)))
	return rule


## A big letter-spaced title with a centered accent rule (menu titles).
static func make_title(text: String, size := 30) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var label := make_label(text.to_upper(), size, WHITE, true)
	label.add_theme_font_override("font", spaced(MENU_FONT, maxi(roundi(size * 0.2), 3)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color", Color(CYAN, 0.3))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 10)
	box.add_child(label)
	var rule := make_rule(true)
	rule.custom_minimum_size.x = size * 8.0
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	box.set_meta(&"label", label)
	return box


## A Theme for menus, so anything without its own styling (plain Labels, Buttons, toggles,
## scrollbars, separators, sliders) still matches the HUD.
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = LABEL_FONT
	t.default_font_size = 16
	t.set_color("font_color", "Label", WHITE)

	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var s := HudPanelStyle.new()
		s.lit = {"normal": 0.0, "hover": 0.6, "pressed": 1.0, "disabled": 0.0, "hover_pressed": 1.0}[state]
		if state == "disabled":
			s.accent = Color(0.5, 0.56, 0.62, 0.6)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		t.set_stylebox(state, "Button", s)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", spaced(MENU_FONT, 2))
	t.set_font_size("font_size", "Button", 15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.6, 0.66, 0.6))

	# Toggles: no panel, just the label and a pill switch.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font("font", "CheckButton", spaced(MENU_FONT, 2))
	t.set_font_size("font_size", "CheckButton", 15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", WHITE)
	t.set_icon("checked", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked", "CheckButton", _switch_texture(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_texture(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_texture(false))

	# Thin scrollbars.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.0, 0.01, 0.03, 0.5)
		track.set_content_margin_all(2)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		for g in [["grabber", 0.45], ["grabber_highlight", 0.75], ["grabber_pressed", 1.0]]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(CYAN, g[1])
			t.set_stylebox(g[0], bar, grab)

	var line := StyleBoxLine.new()
	line.color = PANEL_EDGE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	_theme = t
	return t


# A small pill switch for toggles: knob on the right and lit when on.
static func _switch_texture(on: bool) -> Texture2D:
	const W := 36
	const H := 18
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var track := Color(CYAN.darkened(0.45), 0.95) if on else Color(0.1, 0.12, 0.16, 0.95)
	var rim := Color(CYAN, 0.9) if on else Color(0.55, 0.65, 0.75, 0.5)
	var knob_x := W - H * 0.5 if on else H * 0.5
	var r := H * 0.5 - 0.5
	for y in H:
		for x in W:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distance to the pill's center line.
			var cx := clampf(p.x, H * 0.5, W - H * 0.5)
			var d := p.distance_to(Vector2(cx, H * 0.5))
			var col := Color(0, 0, 0, 0)
			if d <= r:
				col = rim if d > r - 1.2 else track
			var kd := p.distance_to(Vector2(knob_x, H * 0.5))
			if kd <= r - 3.0:
				col = WHITE if on else Color(0.7, 0.75, 0.8)
			img.set_pixelv(Vector2i(x, y), col)
	return ImageTexture.create_from_image(img)


## Adds a glint overlay on top of a control (drawn over its content) and returns a Callable
## that plays it once: a light band sweeping across. Inside a container it covers the
## container's content area.
static func add_glint(c: Control, strength := 1.2, time := 0.45) -> Callable:
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
