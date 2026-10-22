# Makes the HUD feel projected onto the mech's canopy glass instead of painted on the
# screen: the display trails the view a little when you turn, leans when you strafe, and
# dips when you land, then springs back. Lives under HudDisplay (which adds it) and moves
# it; under a CanvasLayer it moves the whole layer instead.
#
# It settles back to rest whenever a menu is open (Tab, pause, a choice popup), so menus that
# share the HUD layer never drift.
class_name HudMotion
extends Node

## Pixels of trail per radian/second of turning (yaw sideways, pitch up and down).
@export var look_trail := 9.0
## Pixels of lean per m/s of sideways speed, and the roll that goes with it (radians).
@export var strafe_shift := 0.6
@export var strafe_roll := 0.0012
## Pixels the HUD dips per m/s of vertical speed.
@export var vertical_shift := 0.5
## Most the HUD can be pushed off rest, in pixels.
@export var max_offset := 18.0
## Spring stiffness and damping: higher stiffness = snappier; damping near 2*sqrt(stiffness)
## = no wobble, lower = a little overshoot.
@export var stiffness := 90.0
@export var damping := 13.0

var _layer : CanvasLayer
var _rect : Control
var _last_basis : Basis
var _has_last := false
var _offset := Vector2.ZERO
var _velocity := Vector2.ZERO
var _roll := 0.0
var _roll_velocity := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # so it can settle back while the game is paused
	_layer = get_parent() as CanvasLayer
	_rect = get_parent() as Control


func _process(delta: float) -> void:
	if (_layer == null and _rect == null) or delta <= 0.0:
		return
	var target := Vector2.ZERO
	var target_roll := 0.0
	var player := GameManager.player
	var calm := get_tree().paused or GameManager.choice_open or (player != null and player.menu_open)
	var cam := get_viewport().get_camera_3d()
	if cam != null and player != null and not calm:
		var basis := cam.global_basis
		if _has_last:
			# Turn rate from how far the view rotated since last frame.
			var turn := (_last_basis.orthonormalized().inverse() * basis.orthonormalized()).get_euler() / maxf(delta, 1.0 / 240.0)
			target += Vector2(turn.y, -turn.x) * look_trail
			var local_v := basis.inverse() * player.velocity
			target.x -= local_v.x * strafe_shift
			target.y += local_v.y * vertical_shift
			target_roll = -local_v.x * strafe_roll
		_last_basis = basis
		_has_last = true
	else:
		_has_last = false
	target = target.limit_length(max_offset)

	# Damped spring toward the target, in small fixed steps so a long frame (a hitch, a
	# loading stall) can never make it blow up.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var dt := minf(left, 1.0 / 120.0)
		left -= dt
		var accel := (target - _offset) * stiffness - _velocity * damping
		_velocity += accel * dt
		_offset += _velocity * dt
		var roll_accel := (target_roll - _roll) * stiffness - _roll_velocity * damping
		_roll_velocity += roll_accel * dt
		_roll += _roll_velocity * dt
	if not (is_finite(_offset.x) and is_finite(_offset.y) and is_finite(_roll)):
		_offset = Vector2.ZERO
		_velocity = Vector2.ZERO
		_roll = 0.0
		_roll_velocity = 0.0

	if _rect != null:
		if _rect.has_method(&"set_motion"):
			_rect.call(&"set_motion", _offset, _roll)   # HudDisplay: keeps its own overhang
		else:
			_rect.pivot_offset = _rect.size * 0.5
			_rect.rotation = _roll
			_rect.position = _offset
		return
	# Rotate about the screen center, then shift.
	var center := get_viewport().get_visible_rect().size * 0.5
	var xf := Transform2D(_roll, center) * Transform2D(0.0, -center)
	xf.origin += _offset
	_layer.transform = xf
