# Draws the lock-on area on the HUD: two arcs (left and right) showing how far from the center
# a target can be locked, with small tick marks, in the HUD's cyan (red while locked).
# In the split aim modes it also draws faint lines showing how the circle is divided.
extends Control

@export var lock_on: LockOn
@export var idle_color := Color(0.42, 1.0, 0.55, 0.32)
@export var locked_color := Color(1.0, 0.7, 0.15, 0.55)
@export var line_width := 2.0
@export_range(10.0, 180.0) var arc_degrees := 45.0
## Opacity of the split lines, relative to the circle's color.
@export_range(0.0, 1.0) var divider_alpha := 0.5
## Length of the tick marks at the ends and middle of each arc, in pixels.
@export var tick_length := 5.0

var _radius := 0.0
var _locked := false
var _mode := 1


func _process(_delta: float) -> void:
	if lock_on == null or GameManager.player == null:
		return

	var radius := lock_on.get_fov_screen_radius()
	var locked := lock_on.is_locked()

	# Only redraw when something changed (a stat, the camera FOV, the window size, the lock, the mode).
	if not is_equal_approx(radius, _radius) or locked != _locked or lock_on.mode != _mode:
		_radius = radius
		_locked = locked
		_mode = lock_on.mode
		queue_redraw()


func _draw() -> void:
	var color := locked_color if _locked else idle_color
	var center := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5

	for side in [0.0, PI]:   # right arc (around 0 degrees), left arc (around 180)
		draw_arc(center, _radius, side - half, side + half, 48, color, line_width, true)
		# Ticks: inward at both ends, outward in the middle.
		for a in [side - half, side + half]:
			var dir := Vector2.from_angle(a)
			draw_line(center + dir * _radius, center + dir * (_radius - tick_length), color, line_width, true)
		var mid := Vector2.from_angle(side)
		draw_line(center + mid * _radius, center + mid * (_radius + tick_length * 1.4), color, line_width, true)

	# Split lines, kept short of the center so they don't cover the middle of the screen.
	var faint := Color(color, color.a * divider_alpha)
	var gap := _radius * 0.25
	if _mode == LockOn.Mode.LEFT_RIGHT or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			draw_line(center + Vector2(0, s * gap), center + Vector2(0, s * _radius), faint, line_width, true)
	if _mode == LockOn.Mode.TOP_BOTTOM or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			draw_line(center + Vector2(s * gap, 0), center + Vector2(s * _radius, 0), faint, line_width, true)
