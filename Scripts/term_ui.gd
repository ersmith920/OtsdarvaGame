# Terminal-screen behaviour shared by the menus (the look itself lives in HudStyle):
#   - type_in / type_tree: text prints in character by character with keystroke ticks, like
#     an old terminal writing to the screen,
#   - power_on / power_off: a CRT switching on (a bright line opening out to the full picture)
#     and off (the picture collapsing to a line, then a dot),
#   - leader_row: "DAMAGE ........... 200" rows with dotted leaders,
#   - label: a monospace label.
# Everything works while the game is paused (tweens follow their node's process mode, and
# the menus run in PROCESS_MODE_ALWAYS).
class_name TermUI
extends RefCounted

## How fast text prints, in characters per second.
const TYPE_SPEED := 140.0
## Labels with this meta are left alone by type_tree (numbers that update live, etc.).
const NO_TYPE := &"no_type"


## A monospace label (bold for titles and values).
static func label(text: String, size: int, color := HudStyle.ORANGE, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", HudStyle.TERM_BOLD if bold else HudStyle.TERM_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Prints a label's text in, one character at a time, ticking as it goes.
static func type_in(l: Label, delay := 0.0, speed := TYPE_SPEED, sound := true) -> Tween:
	var count := l.get_total_character_count()
	if count == 0:
		count = l.text.length()
	l.visible_characters = 0
	var t := l.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_method(func(v: float) -> void:
		var n := int(v)
		if n != l.visible_characters:
			l.visible_characters = n
			if sound and n < count and l.text.substr(n - 1, 1) != " ":
				UIJuice.play(UIJuice.Sfx.TYPE, randf_range(0.9, 1.15)),
		0.0, float(count), count / speed)
	t.tween_callback(func() -> void: l.visible_characters = -1)
	return t


## Prints every Label under root in, top to bottom (in tree order), each starting a little
## after the one before. Returns roughly how long it takes.
static func type_tree(root: Node, delay := 0.0, speed := TYPE_SPEED, stagger := 0.025) -> float:
	var labels : Array[Label] = []
	_collect(root, labels)
	var at := delay
	var first := true
	for l in labels:
		if l.text.is_empty() or not l.is_visible_in_tree():
			continue
		type_in(l, at, speed, first or l.text.length() > 6)
		first = false
		at += stagger
	return at


static func _collect(node: Node, out: Array[Label]) -> void:
	if node is Label and not node.has_meta(NO_TYPE):
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


## A CRT switching on: the control opens out from a bright horizontal line to its full
## height, flashing bright as it does.
static func power_on(c: Control, delay := 0.0, time := 0.2) -> Tween:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.0, 0.006)
	c.modulate = Color(3.0, 3.0, 3.0, 0.0)
	var t := c.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func() -> void:
		c.pivot_offset = c.size * 0.5
		UIJuice.play(UIJuice.Sfx.BOOT))
	t.tween_property(c, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.04)
	t.tween_property(c, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(c, "modulate", Color.WHITE, time * 1.6).set_trans(Tween.TRANS_SINE)
	return t


## A CRT switching off: the picture collapses to a bright line, the line to a dot, then done
## is called.
static func power_off(c: Control, done := Callable(), time := 0.16) -> Tween:
	c.pivot_offset = c.size * 0.5
	UIJuice.play(UIJuice.Sfx.SHUTDOWN)
	var t := c.create_tween()
	t.tween_property(c, "modulate", Color(3.0, 3.0, 3.0, 1.0), time * 0.5)
	t.parallel().tween_property(c, "scale", Vector2(1.0, 0.006), time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(c, "scale", Vector2(0.0, 0.006), time * 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(c, "modulate:a", 0.0, time * 0.6)
	if done.is_valid():
		t.tween_callback(done)
	return t


## A row "NAME ........ VALUE": the name on the left, the value right-aligned, dots between.
## Returns the row; its metas "name" and "value" are the two Labels.
static func leader_row(name: String, value: String, size := 14, name_color := HudStyle.ORANGE,
		value_color := HudStyle.WHITE, dots_color := Color(HudStyle.ORANGE, 0.35)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var left := label(name, size, name_color)
	row.add_child(left)
	var dots := Control.new()
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.draw.connect(func() -> void:
		var y := dots.size.y * 0.5 + size * 0.28
		var x := 2.0
		while x < dots.size.x - 2.0:
			dots.draw_rect(Rect2(x, y, 2, 2), dots_color)
			x += 6.0)
	row.add_child(dots)
	var right := label(value, size, value_color, true)
	right.add_theme_font_override("font", HudStyle.READOUT_FONT)
	right.add_theme_font_size_override("font_size", size + 2)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	row.set_meta(&"name", left)
	row.set_meta(&"value", right)
	return row


## An oscilloscope: a few traces scrolling across a faint grid (like the bio-monitors on the
## Sulaco). Purely for life; it animates by itself, also while the game is paused.
static func make_scope(height := 90.0, colors: Array = [HudStyle.GREEN, HudStyle.INFO, HudStyle.ORANGE]) -> Control:
	var scope := Control.new()
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.custom_minimum_size = Vector2(0, height)
	scope.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, scope.size)
		var grid := Color(HudStyle.ORANGE, 0.12)
		var gx := 0.0
		while gx <= r.size.x:
			scope.draw_line(Vector2(gx, 0), Vector2(gx, r.size.y), grid, 1.0)
			gx += 24.0
		var gy := 0.0
		while gy <= r.size.y:
			scope.draw_line(Vector2(0, gy), Vector2(r.size.x, gy), grid, 1.0)
			gy += 18.0
		scope.draw_rect(r, Color(HudStyle.ORANGE, 0.5), false, 1.0)
		var t := Time.get_ticks_msec() / 1000.0
		var lanes := colors.size()
		for k in lanes:
			var mid := r.size.y * (k + 0.5) / lanes
			var amp := r.size.y / lanes * 0.38
			var pts := PackedVector2Array()
			var x := 0.0
			while x <= r.size.x:
				var u := x * 0.045 - t * (2.2 + k * 0.7)
				var v := sin(u) * 0.35 + sin(u * 2.7 + k) * 0.25 + sin(u * 7.1 + k * 2.0) * 0.12
				if k == 0:
					# A heartbeat spike every so often.
					var beat := fposmod(u, 6.2) - 3.0
					v += exp(-beat * beat * 30.0) * 1.6 - exp(-(beat - 0.18) * (beat - 0.18) * 40.0) * 0.8
				pts.append(Vector2(x, mid - v * amp))
				x += 3.0
			scope.draw_polyline(pts, colors[k], 1.5, true))
	scope.ready.connect(func() -> void:
		var loop := scope.create_tween().set_loops()
		loop.tween_interval(1.0 / 30.0)
		loop.tween_callback(scope.queue_redraw))
	return scope


## A segmented level bar ("SYNC [|||||||||....]"): call the returned Control's
## set_meta("value", 0..1) and queue_redraw() to change it.
static func make_meter(segments := 24, color := HudStyle.ORANGE, height := 12.0) -> Control:
	var meter := Control.new()
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.custom_minimum_size = Vector2(0, height)
	meter.set_meta(&"value", 0.0)
	meter.draw.connect(func() -> void:
		var v : float = meter.get_meta(&"value")
		var w := meter.size.x / segments
		for i in segments:
			var on := (i + 0.5) / segments <= v
			meter.draw_rect(Rect2(i * w + 1.0, 0, w - 3.0, meter.size.y), color if on else Color(color, 0.12)))
	return meter

