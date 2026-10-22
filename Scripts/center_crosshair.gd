# Fixed symbology at the middle of the screen, fighter-jet style (drawn in the aim layer,
# which gets the HUD's bloom but no curve or sway, so it stays exactly on the screen center):
#   - the boresight: a small open cross on the exact center, where the view points (the
#     lock-on pipper rings it while it's resting),
#   - the flight path marker: a small circle with wings and a tail showing where you're
#     actually moving (it drifts off the center when you strafe, jump or fall),
extends Control

@export var color := HudStyle.ORANGE:
	set(v):
		color = v
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var opacity := 0.85
## Unused now (kept so the scene still loads).
@export_range(0.5, 20.0, 0.5) var radius := 2.0

## The flight path marker hides below this speed (m/s).
const FPM_MIN_SPEED := 1.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).round()
	var col := Color(color, opacity)

	# Boresight: a small open cross on the exact center (the pipper rings it at rest).
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 2.5, c + d * 5.5, col, 1.0)

	var cam := get_tree().root.get_camera_3d()
	var player := GameManager.player
	if cam == null:
		return

	# Flight path marker: where the mech is moving.
	if player == null:
		return
	var v : Vector3 = player.velocity
	if v.length() < FPM_MIN_SPEED:
		return
	var probe := cam.global_position + v.normalized() * 10.0
	if cam.is_position_behind(probe):
		return
	var p := cam.unproject_position(probe)
	# Keep it on screen: pinned to the edge of a box around the center (and dimmed) when the
	# real direction is off to the side.
	var box := size * 0.32
	var off := p - c
	var pinned := absf(off.x) > box.x or absf(off.y) > box.y
	off = off.clamp(-box, box)
	p = c + off
	var fc := Color(HudStyle.ORANGE_HOT, opacity * (0.5 if pinned else 1.0))
	draw_arc(p, 6.0, 0.0, TAU, 24, fc, 1.0, true)
	draw_line(p + Vector2(-6, 0), p + Vector2(-15, 0), fc, 1.0)
	draw_line(p + Vector2(6, 0), p + Vector2(15, 0), fc, 1.0)
	draw_line(p + Vector2(0, -6), p + Vector2(0, -12), fc, 1.0)
