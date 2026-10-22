# One lock-on crosshair (LockOn moves it, tints it and copies it for the split aim modes),
# drawn like a fighter's targeting symbology:
#   - searching: a gun pipper (a ring with a dot and four ticks),
#   - locked: a target designator box with a turning diamond inside, the range to the
#     target under it, and corner brackets that snap in from wide when the lock lands.
# In split modes each crosshair carries its number (1-4) at its top right.
# It draws in white; LockOn's modulate supplies the color (orange searching, red locked).
# LockOn tells it what's going on through metas: "locked" (bool), "snap" (1 -> 0 as a new lock
# settles), "index" and "count" (which crosshair of how many), "range" (meters, -1 = none).
extends TextureRect

const SIZE := Vector2(72, 72)

var _time := 0.0


func _ready() -> void:
	texture = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).round()
	var locked : bool = get_meta(&"locked", false)
	var snap : float = get_meta(&"snap", 0.0)
	var index : int = get_meta(&"index", 0)
	var count : int = get_meta(&"count", 1)
	var k : float = get_meta(&"scale", 1.0)   # shrinks with a small lock circle
	draw_set_transform(c, 0.0, Vector2(k, k))
	c = Vector2.ZERO
	var col := Color.WHITE
	var w := 1.0 / k     # strokes stay the same width on screen whatever the scale
	var w2 := 1.25 / k

	if not locked:
		# Gun pipper.
		draw_arc(c, 8.0, 0.0, TAU, 28, col, w, true)
		draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), col)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 11.0, c + d * 17.0, col, w)
	else:
		# Target designator box, with a diamond turning inside it.
		var h := 15.0
		draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), col, false, w2)
		var spin := _time * 1.6
		var pts := PackedVector2Array()
		for q in 5:
			pts.append(c + Vector2.from_angle(spin + q * PI * 0.5) * 7.0)
		draw_polyline(pts, col, w, true)
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)
		# Corner brackets: start wide when the lock lands and snap in onto the box.
		var g := h + 5.0 + 16.0 * snap * snap
		var arm := 7.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := c + Vector2(sx * g, sy * g)
				draw_line(corner, corner - Vector2(sx * arm, 0), col, w2)
				draw_line(corner, corner - Vector2(0, sy * arm), col, w2)
		# Range to the target.
		var rng : float = get_meta(&"range", -1.0)
		if rng >= 0.0:
			var text := "R%03d" % mini(roundi(rng), 999)
			var font := HudStyle.READOUT_FONT
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, c + Vector2(-tw * 0.5, h + 15.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

	# Split modes: this crosshair's number.
	if count > 1:
		draw_string(HudStyle.READOUT_FONT, c + Vector2(13.0, -11.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_set_transform(Vector2.ZERO)
