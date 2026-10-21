# Autoload "DamageNumbers": small floating numbers where enemies get hit.
# White with a thin dark border; crits are red with a dark red border.
# A fixed pool of Label3Ds is reused, so busy fights never create new nodes per hit.
extends Node

const MAX_ACTIVE := 80           # past this, the oldest number is reused
const MAX_PER_FRAME := 12         # extra hits in one frame skip their number (keeps big fights cheap)
const LIFETIME := 0.6            # seconds on screen
const RISE := 1.2                # meters it floats up over its life
const JITTER := 0.35             # random sideways spread so stacked hits don't overlap exactly
const FONT := preload("res://Fonts/KHMenu-Bold.otf")
const FONT_SIZE := 48
const PIXEL_SIZE := 0.0005       # on-screen size (numbers keep the same size at any distance)
const CRIT_SCALE := 1.3          # crits are a little bigger
const OUTLINE_SIZE := 10         # border thickness
const POP_TIME := 0.12           # seconds a new number takes to pop down to its size
const POP_SCALE := 1.5           # how big it starts (crits start bigger still)

const COLOR := Color(1, 1, 1)
const OUTLINE := Color(0.08, 0.08, 0.08)
const CRIT_COLOR := Color(1.0, 0.18, 0.18)
const CRIT_OUTLINE := Color(0.35, 0.0, 0.0)

var _labels: Array[Label3D] = []
var _age := PackedFloat32Array()
var _start := PackedVector3Array()
var _base_px := PackedFloat32Array()   # each number's settled pixel size
var _pop := PackedFloat32Array()       # each number's starting size multiplier
var _next := 0                   # next pool slot to use (oldest when the pool is full)
var _spawned_this_frame := 0


func spawn(at: Vector3, amount: float, crit: bool) -> void:
	if amount <= 0.0 or _spawned_this_frame >= MAX_PER_FRAME:
		return
	var i := _get_label_index()
	if i < 0:
		return
	_spawned_this_frame += 1
	var label := _labels[i]
	label.text = _format(amount)
	label.modulate = CRIT_COLOR if crit else COLOR
	label.outline_modulate = CRIT_OUTLINE if crit else OUTLINE
	_base_px[i] = PIXEL_SIZE * (CRIT_SCALE if crit else 1.0)
	_pop[i] = POP_SCALE * (1.25 if crit else 1.0)
	label.pixel_size = _base_px[i] * _pop[i]
	var offset := Vector3(randf_range(-JITTER, JITTER), randf_range(0.0, JITTER), randf_range(-JITTER, JITTER))
	_start[i] = at + offset
	label.global_position = _start[i]
	_age[i] = 0.0
	label.visible = true


func _process(delta: float) -> void:
	_spawned_this_frame = 0
	for i in _labels.size():
		var label := _labels[i]
		if not is_instance_valid(label) or not label.visible:
			continue
		_age[i] += delta
		var t := _age[i] / LIFETIME
		if t >= 1.0:
			label.visible = false
			continue
		# Rises fast then slows; fades out over the last 40% of its life.
		var rise := RISE * (1.0 - (1.0 - t) * (1.0 - t))
		label.global_position = _start[i] + Vector3(0.0, rise, 0.0)
		var alpha := clampf((1.0 - t) / 0.4, 0.0, 1.0)
		label.modulate.a = alpha
		label.outline_modulate.a = alpha
		# Pops in: starts big, snaps down to its size with a little overshoot.
		var age := _age[i]
		if age < POP_TIME * 1.6:
			var p := clampf(age / POP_TIME, 0.0, 1.0)
			var size := lerpf(_pop[i], 1.0, 1.0 - pow(1.0 - p, 3.0))
			if age > POP_TIME:   # small undershoot and back
				size = 1.0 - 0.08 * sin((age - POP_TIME) / (POP_TIME * 0.6) * PI)
			label.pixel_size = _base_px[i] * size


# Index of the pool label to use next, or -1 if there's no scene to put it in.
func _get_label_index() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return -1
	# Drop labels that went away with an old scene.
	if not _labels.is_empty() and not is_instance_valid(_labels[0]):
		_labels.clear()
		_age.clear()
		_start.clear()
		_base_px.clear()
		_pop.clear()
		_next = 0

	if _labels.size() < MAX_ACTIVE:
		var label := _make_label()
		scene.add_child(label)
		_labels.append(label)
		_age.append(0.0)
		_start.append(Vector3.ZERO)
		_base_px.append(PIXEL_SIZE)
		_pop.append(1.0)
		return _labels.size() - 1

	# Pool full: prefer a hidden label, otherwise reuse the oldest (round robin).
	for n in _labels.size():
		var idx := (_next + n) % _labels.size()
		if not _labels[idx].visible:
			_next = (idx + 1) % _labels.size()
			return idx
	var oldest := _next
	_next = (_next + 1) % _labels.size()
	return oldest


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.font = FONT
	label.font_size = FONT_SIZE
	label.outline_size = OUTLINE_SIZE
	label.pixel_size = PIXEL_SIZE
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true          # visible through enemies and walls
	label.double_sided = true
	label.shaded = false
	label.render_priority = 10
	label.outline_render_priority = 9
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	label.visible = false
	return label


func _format(amount: float) -> String:
	if amount < 10.0:
		return "%.1f" % amount if absf(amount - roundf(amount)) > 0.05 else str(int(roundf(amount)))
	return str(int(roundf(amount)))
