# Fixed dot at the exact center of the screen, as a reference point.
# Separate from the lock-on crosshair, which moves.
extends Control

@export var color := Color(1.0, 1.0, 1.0):
	set(v):
		color = v
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var opacity := 0.6:
	set(v):
		opacity = v
		queue_redraw()
## Radius of the dot in pixels.
@export_range(0.5, 20.0, 0.5) var radius := 2.0:
	set(v):
		radius = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)   # stays centered if the window size changes


func _draw() -> void:
	draw_circle(size * 0.5, radius, Color(color, opacity))
