# Draws a circle on the HUD showing the area the lock-on can pick targets from.
extends Control

@export var lock_on: LockOn
@export var idle_color := Color(1.0, 1.0, 1.0, 0.3)
@export var locked_color := Color(1.0, 0.25, 0.25, 0.5)
@export var line_width := 2.0
@export_range(10.0, 180.0) var arc_degrees := 45.0

var _radius := 0.0
var _locked := false


func _process(_delta: float) -> void:
	if lock_on == null or GameManager.player == null:
		return

	var radius := lock_on.get_fov_screen_radius()
	var locked := lock_on.is_locked()

	# Only redraw when something changed (a stat, the camera FOV, the window size, the lock).
	if not is_equal_approx(radius, _radius) or locked != _locked:
		_radius = radius
		_locked = locked
		queue_redraw()


func _draw() -> void:
	var color := locked_color if _locked else idle_color
	var center := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5

	# Right side: centered on 0 degrees (pointing right).
	draw_arc(center, _radius, -half, half, 48, color, line_width, true)
	# Left side: centered on 180 degrees (pointing left).
	draw_arc(center, _radius, PI - half, PI + half, 48, color, line_width, true)
