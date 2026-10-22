# The HUD's look in one place: old sci-fi military computer panels. Green phosphor on near
# black (amber and red for warnings and danger), like aircraft / naval consoles and the
# terminals of Alien: monospace terminal text with a soft phosphor glow, square panels with
# a double-rule border, corner ticks and faint scanlines, segmented bar-graph gauges and an
# analog speed dial. Rarity colors stay as they are, so tiers read at a glance.
# HUD scripts use these colors, fonts and drawing helpers so everything matches.
class_name HudStyle
extends RefCounted

# ---- Colors ----
## Main accent: phosphor green. (Named CYAN for older callers: it's the accent color.)
const PHOSPHOR := Color(0.42, 1.0, 0.55)
const CYAN := PHOSPHOR
const CYAN_DIM := Color(0.36, 0.82, 0.46, 0.75)
const CYAN_FAINT := Color(0.42, 1.0, 0.55, 0.15)
## Caution and danger.
const AMBER := Color(1.0, 0.7, 0.15)
const RED := Color(1.0, 0.27, 0.2)
## Bright text: phosphor white (a touch of green).
const WHITE := Color(0.86, 1.0, 0.89)
const GOLD := Color(1.0, 0.84, 0.35)
## Health and energy gauges.
const HP_COLOR := Color(0.45, 1.0, 0.5)
const EN_COLOR := Color(0.45, 0.95, 0.92)
## Older names, kept so nothing breaks.
const HP_RED := HP_COLOR
const EN_BLUE := EN_COLOR
## The pale trail left behind on a gauge when it drops.
const TRAIL := Color(1.0, 0.85, 0.5, 0.75)
## Panels: fill (top, bottom), hairline border.
const PANEL_TOP := Color(0.01, 0.06, 0.03, 0.82)
const PANEL_BOTTOM := Color(0.0, 0.035, 0.015, 0.82)
const PANEL_EDGE := Color(0.42, 1.0, 0.55, 0.3)
const SHADOW := Color(0.0, 0.02, 0.01, 0.9)

# ---- Fonts (open-license terminal fonts, see Fonts/*-OFL.txt) ----
## Big numbers and titles: VT323, a CRT terminal face.
const NUMBER_FONT := preload("res://Fonts/VT323-Regular.ttf")
## Everything else: Share Tech Mono, a technical monospace.
const MENU_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
const LABEL_FONT := preload("res://Fonts/ShareTechMono-Regular.ttf")
## VT323 draws small for its size: number labels are made this much bigger to match.
const NUMBER_SCALE := 1.35

## How far a panel's top-left and bottom-right corners are cut.
const CUT := 4.0
## Extra space between letters in captions.
const CAPTION_SPACING := 1

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


## A label in the HUD style: terminal text with a soft phosphor glow around it (and a thin
## dark outline so it reads over anything). number: the big CRT number font.
static func make_label(text: String, size: int, color := WHITE, number := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if number:
		size = roundi(size * NUMBER_SCALE)
	l.add_theme_font_override("font", NUMBER_FONT if number else LABEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	add_phosphor(l, color)
	return l


## Gives a label the phosphor look in this color: the text, a soft glow behind it in the same
## color, and a thin dark outline. Safe to call again to recolor it.
static func add_phosphor(l: Control, color: Color, glow := 0.3) -> void:
	var size := l.get_theme_font_size("font_size")
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(color, color.a * glow))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", maxi(roundi(size * 0.3), 3))
	# A faint dark edge keeps small text readable over bright scenery without looking outlined.
	l.add_theme_color_override("font_outline_color", Color(SHADOW, 0.45))
	l.add_theme_constant_override("outline_size", 1)


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
	cut = clampf(cut, 0.5, minf(r.size.x, r.size.y) * 0.45)   # never 0: repeated points break drawing
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


## A segmented bar-graph gauge (old LED / CRT style). fill and ghost are 0-1; segments
## between them show in the trail color. from_right: drains from the left end toward the right.
## segment: length of one block including its gap, in pixels.
static func draw_gauge(ci: CanvasItem, r: Rect2, fill: float, ghost: float, color: Color,
		trail := TRAIL, from_right := true, segment := 7.0) -> void:
	# Frame: a dark trough with a dim hairline around it.
	ci.draw_rect(r.grow(2.0), Color(0.0, 0.02, 0.01, 0.8))
	ci.draw_rect(r.grow(2.0), Color(color, 0.25), false, 1.0)
	var count := maxi(roundi(r.size.x / segment), 1)
	var seg_w := r.size.x / count
	var gap := minf(2.0, seg_w * 0.3)
	for i in count:
		# Position along the gauge, measured from the end that stays full.
		var k := (count - 1 - i) if from_right else i
		var at := (k + 0.5) / count
		var x := r.position.x + i * seg_w
		var block := Rect2(x + gap * 0.5, r.position.y, seg_w - gap, r.size.y)
		var c := Color(color, 0.1)
		if at <= fill:
			c = color
		elif at <= ghost:
			c = trail
		ci.draw_rect(block, c)
		if at <= fill and r.size.y >= 5.0:
			ci.draw_rect(Rect2(block.position, Vector2(block.size.x, 1.0)), Color(1, 1, 1, 0.25))


## A gauge fill: flat color with a hairline highlight on top (used by older callers).
static func _gloss_fill(ci: CanvasItem, r: Rect2, color: Color, radius: float) -> void:
	ci.draw_colored_polygon(rounded_points(r, minf(radius, 1.5)), color)
	if r.size.y >= 6.0:
		ci.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 1, 1, 0.25), 1.0)


## A thick arc in the gauge style (the part of the HP gauge wrapping over the core).
static func draw_gauge_arc(ci: CanvasItem, center: Vector2, radius: float, from_angle: float,
		to_angle: float, width: float, color: Color) -> void:
	if absf(to_angle - from_angle) < 0.001:
		return
	ci.draw_arc(center, radius, from_angle, to_angle, 40, color.darkened(0.15), width, true)
	ci.draw_arc(center, radius + width * 0.3, from_angle, to_angle, 40, Color(color.lerp(Color.WHITE, 0.3), 0.9), width * 0.35, true)


## A scan sweep across a panel: a bright phosphor line passing top to bottom with a fading
## trail above it, like a CRT redrawing. t: progress 0-1 (tween it to play it).
static func draw_glint(ci: CanvasItem, r: Rect2, t: float, strength := 1.0) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	var y := lerpf(r.position.y - 4.0, r.end.y + 4.0, t)
	var x0 := r.position.x + 1.0
	var w := r.size.x - 2.0
	for band in [[28.0, 0.05], [12.0, 0.08], [4.0, 0.14]]:
		var h : float = band[0]
		var top := maxf(y - h, r.position.y)
		var bottom := minf(y, r.end.y)
		if bottom > top:
			ci.draw_rect(Rect2(x0, top, w, bottom - top), Color(0.7, 1.0, 0.75, band[1] * strength))
	if y > r.position.y and y < r.end.y:
		ci.draw_rect(Rect2(x0, y - 1.0, w, 1.5), Color(0.85, 1.0, 0.88, 0.5 * strength))


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
	s.cut = 6.0
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
	s.fill_top = Color(0.01, 0.05, 0.025, 0.93).lerp(Color(color.darkened(0.6), 0.93), 0.18 + 0.18 * lit)
	s.fill_bottom = Color(0.0, 0.03, 0.015, 0.95).lerp(Color(color.darkened(0.75), 0.95), 0.12 + 0.1 * lit)
	s.glow = Color(color, 0.9)
	s.glow_size = 12.0 + 10.0 * lit
	# Bright glow hugging the inside of the border (stronger when hovered).
	s.inner_glow = Color(color.lerp(Color.WHITE, 0.2), 0.9 + 0.1 * lit)
	s.inner_glow_size = 12.0 + 6.0 * lit


## An empty card frame (nothing in the slot yet).
static func empty_card_style(padding := 10.0) -> HudPanelStyle:
	var s := card_style(CYAN_DIM, 0.0, padding)
	s.edge = Color(PHOSPHOR, 0.22)
	s.accent = Color(PHOSPHOR, 0.5)
	s.fill_top = PANEL_TOP
	s.fill_bottom = PANEL_BOTTOM
	s.glow_size = 0.0
	s.inner_glow_size = 0.0
	return s


## A small square tile (items, weapons) in a tier / rarity color.
static func tile_style(color: Color) -> HudPanelStyle:
	var s := HudPanelStyle.new()
	color_tile(s, color)
	s.cut = 4.0
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
	s.fill_top = Color(0.0, 0.03, 0.01, 0.4)
	s.fill_bottom = Color(0.0, 0.03, 0.01, 0.4)
	s.edge = Color(PHOSPHOR, 0.2)
	return s


## A command button in the HUD style: a panel drawn behind terminal text. Hovered, it lights
## up in the accent color, its accent bar grows and a cursor marks it ("> RESUME", or
## "> REROLL <" when centered); slide also nudges it right (left-aligned menu lists),
## otherwise it grows a little. Pressing punches it. Hover / click sounds included. A disabled
## button dims and ignores hovers.
static func make_button(text: String, min_size := Vector2(200, 44), font_size := 18, accent := CYAN,
		slide := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> Button:
	var button := Button.new()
	var label := text.to_upper()
	var centered := align == HORIZONTAL_ALIGNMENT_CENTER
	# Monospace text, so swapping the cursor in and out never changes its width.
	var plain := ("  %s  " if centered else "  %s") % label
	var cursor := ("> %s <" if centered else "> %s") % label
	button.text = plain
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	button.alignment = align
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 24 if align == HORIZONTAL_ALIGNMENT_LEFT else 12
		box.content_margin_right = 12
		button.add_theme_stylebox_override(st, box)
	button.add_theme_font_override("font", spaced(MENU_FONT, 2))
	button.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(c, WHITE)
	button.add_theme_color_override("font_disabled_color", Color(CYAN_DIM, 0.4))
	button.add_theme_color_override("font_outline_color", Color(SHADOW, 0.8))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_shadow_color", Color(PHOSPHOR, 0.3))
	button.add_theme_constant_override("shadow_offset_x", 0)
	button.add_theme_constant_override("shadow_offset_y", 0)
	button.add_theme_constant_override("shadow_outline_size", 6)
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
		style.accent = Color(CYAN_DIM, 0.4) if button.disabled else accent
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
		button.text = cursor
		UIJuice.play(UIJuice.Sfx.HOVER))
	button.mouse_exited.connect(func() -> void:
		light.call(0.0)
		button.text = plain)
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
	label.add_theme_font_override("font", spaced(LABEL_FONT, maxi(roundi(size * 0.15), 1)))
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
		# A dashed hairline (like a printed form) with a solid accent block.
		var w := rule.size.x
		var x := 0.0
		while x < w:
			rule.draw_rect(Rect2(x, 1, minf(4.0, w - x), 1), PANEL_EDGE)
			x += 7.0
		var seg := minf(48.0, w * 0.3)
		var sx := (w - seg) * 0.5 if centered else 0.0
		rule.draw_rect(Rect2(sx, 0, seg, 3), Color(accent, 0.9)))
	return rule


## A big letter-spaced title with a centered accent rule (menu titles).
static func make_title(text: String, size := 30) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var label := make_label(text.to_upper(), size, PHOSPHOR, true)
	label.add_theme_font_override("font", spaced(NUMBER_FONT, maxi(roundi(size * 0.15), 2)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_phosphor(label, PHOSPHOR, 0.35)
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
			s.accent = Color(CYAN_DIM, 0.4)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		t.set_stylebox(state, "Button", s)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", spaced(MENU_FONT, 1))
	t.set_font_size("font_size", "Button", 15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(CYAN_DIM, 0.4))

	# Toggles: no panel, just the label and a pill switch.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font("font", "CheckButton", spaced(MENU_FONT, 1))
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
		track.bg_color = Color(0.0, 0.03, 0.01, 0.5)
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


# A small hardware-style toggle: a framed slot with a block that sits right and glows when
# on, and sits left, dark, when off.
static func _switch_texture(on: bool) -> Texture2D:
	const W := 36
	const H := 18
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.03, 0.01, 0.9))
	var rim := Color(PHOSPHOR, 0.9) if on else Color(PHOSPHOR, 0.35)
	for x in W:
		img.set_pixel(x, 0, rim)
		img.set_pixel(x, H - 1, rim)
	for y in H:
		img.set_pixel(0, y, rim)
		img.set_pixel(W - 1, y, rim)
	var block := Rect2i(W - 17, 3, 14, H - 6) if on else Rect2i(3, 3, 14, H - 6)
	img.fill_rect(block, PHOSPHOR if on else Color(PHOSPHOR, 0.25))
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
