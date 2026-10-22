# The lock-on area, drawn like a fighter's missile seeker circle (in the aim layer: the HUD's
# bloom, no curve or sway, so it matches where targets can really be locked):
#   - a dashed ring at the lock-on radius, always showing exactly how far out a target can be
#     locked (it grows and shrinks with the lock_fov stat and the camera's FOV),
#   - heavy arcs on the left and right with tick marks, and carets on the four sides pointing in,
#   - a radar sweep: a bright arc orbiting the ring while searching,
#   - a status readout under the ring: SRCH (searching) or LOCK, the lock angle and aim mode,
#   - in the split aim modes, dashed lines showing how the circle is divided.
# Orange while searching, red while anything is locked.
extends Control

@export var lock_on: LockOn
@export var idle_color := Color(1.0, 0.45, 0.1, 0.7)
@export var locked_color := Color(1.0, 0.15, 0.1, 0.9)
@export var line_width := 1.25
## Width of the heavy arcs on the left and right, in degrees.
@export_range(10.0, 180.0) var arc_degrees := 50.0
## Opacity of the split lines, relative to the circle's color.
@export_range(0.0, 1.0) var divider_alpha := 0.45
## Length of the tick marks, in pixels.
@export var tick_length := 7.0
## Radar sweep speed, in turns per second.
@export var sweep_speed := 0.45

var _radius := 0.0
var _locked := false
var _mode := 1
var _time := 0.0
var _lock_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	if lock_on == null or GameManager.player == null:
		return
	var locked := lock_on.is_locked()
	if locked and not _locked:
		_lock_flash = 1.0
	_lock_flash = maxf(_lock_flash - delta * 3.0, 0.0)
	_radius = lock_on.get_fov_screen_radius()
	_locked = locked
	_mode = lock_on.mode
	queue_redraw()


func _draw() -> void:
	if _radius <= 1.0:
		return
	var color := locked_color if _locked else idle_color
	color = color.lerp(Color.WHITE, _lock_flash * 0.6)
	var dim := Color(color, color.a * 0.45)
	var center := (size * 0.5).round()
	var r := _radius
	var k := clampf(r / 110.0, 0.5, 1.0)   # decorations shrink with a small circle
	# Dashed ring all the way round: the lock-on radius.
	var dashes := 72
	for i in dashes:
		var a0 := TAU * i / dashes
		draw_arc(center, r, a0, a0 + TAU / dashes * 0.5, 4, dim, 1.0, true)

	# Heavy arcs left and right, with ticks every 10 degrees across them.
	var half := deg_to_rad(arc_degrees) * 0.5
	for side: float in [0.0, PI]:
		draw_arc(center, r, side - half, side + half, 32, color, line_width, true)
		var steps := int(arc_degrees / 10.0)
		@warning_ignore("integer_division")
		for j in range(-steps / 2, steps / 2 + 1):
			var a: float = side + deg_to_rad(j * 10.0)
			var d := Vector2.from_angle(a)
			var tick := tick_length * k * (1.6 if j == 0 else 1.0)
			draw_line(center + d * r, center + d * (r + tick), color, 1.0, true)

	# Carets on the four sides, pointing in.
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2.from_angle(a)
		var tip := center + d * (r + 3.0)
		var back := center + d * (r + 3.0 + 9.0 * k)
		var w := d.orthogonal() * 4.5 * k
		draw_colored_polygon(PackedVector2Array([tip, back + w, back - w]), color)

	# Radar sweep (searching only): a bright arc with a fading tail, orbiting the ring.
	if not _locked:
		var head := fmod(_time * sweep_speed, 1.0) * TAU - PI * 0.5
		for i in 8:
			var a1 := head - i * 0.05
			draw_arc(center, r + 3.0, a1 - 0.05, a1, 4, Color(color, color.a * (1.0 - i / 8.0)), 2.0, true)

	# Split lines (dashed), kept short of the center so they don't cover the middle.
	var faint := Color(color, color.a * divider_alpha)
	var gap := r * 0.3
	if _mode == LockOn.Mode.LEFT_RIGHT or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			_dashed_line(center + Vector2(0, s * gap), center + Vector2(0, s * (r - 4.0)), faint)
	if _mode == LockOn.Mode.TOP_BOTTOM or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			_dashed_line(center + Vector2(s * gap, 0), center + Vector2(s * (r - 4.0), 0), faint)

	# Status readout under the ring: mode, lock angle, aim mode.
	var font := HudStyle.READOUT_FONT
	var fs := 13
	var status := "LOCK" if _locked else "SRCH"
	var fov := GameManager.player.stats_node.get_value(&"lock_fov") if GameManager.player != null else 0.0
	var text := "%s %03d° AIM%d" % [status, roundi(fov), _mode]
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Well below the ring, so a small circle (early in a run) isn't crowded by text; a big
	# circle pushes it further down.
	var base := center + Vector2(-tw * 0.5, readout_offset(size, r))
	if _locked:
		# Inverted while locked: dark text on a filled red block, blinking slowly.
		if fmod(_time, 0.8) < 0.6:
			draw_rect(Rect2(base + Vector2(-6, -fs + 1), Vector2(tw + 12, fs + 5)), color)
			draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.INK)
	else:
		draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, 1.0))


## How far below the screen center the status readout sits (LockOn puts the aim-mode
## message under it).
static func readout_offset(view: Vector2, radius: float) -> float:
	return maxf(view.y * 0.3, radius + 30.0)


func _dashed_line(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	var d := 0.0
	while d < length:
		draw_line(a.lerp(b, d / length), a.lerp(b, minf(d + 6.0, length) / length), color, 1.0)
		d += 11.0
