# Draws a circle on the HUD showing the area the lock-on can pick targets from.
# In the split aim modes it also draws faint lines showing how the circle is divided.
extends Control

@export var lock_on: LockOn
@export var idle_color := Color(1.0, 1.0, 1.0, 0.3)
@export var locked_color := Color(1.0, 0.25, 0.25, 0.5)
@export var line_width := 2.0
@export_range(10.0, 180.0) var arc_degrees := 45.0
## Opacity of the split lines, relative to the circle's color.
@export_range(0.0, 1.0) var divider_alpha := 0.5

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

	# Right side: centered on 0 degrees (pointing right).
	draw_arc(center, _radius, -half, half, 48, color, line_width, true)
	# Left side: centered on 180 degrees (pointing left).
	draw_arc(center, _radius, PI - half, PI + half, 48, color, line_width, true)

	# Split lines, kept short of the center so they don't cover the middle of the screen.
	var faint := Color(color, color.a * divider_alpha)
	var gap := _radius * 0.25
	if _mode == LockOn.Mode.LEFT_RIGHT or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			draw_line(center + Vector2(0, s * gap), center + Vector2(0, s * _radius), faint, line_width, true)
	if _mode == LockOn.Mode.TOP_BOTTOM or _mode == LockOn.Mode.QUADRANTS:
		for s in [-1.0, 1.0]:
			draw_line(center + Vector2(s * gap, 0), center + Vector2(s * _radius, 0), faint, line_width, true)
