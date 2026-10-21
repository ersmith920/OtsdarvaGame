extends CharacterBody3D
class_name Player

const GRAVITY := 24.0              # higher than real gravity feels snappier
const GLIDE_FRICTION := 5       # slowdown when coasting with no input (lower = more slippery)
const AIR_CONTROL := 0.98          # fraction of acceleration available while airborne
const JET_RISE_SPEED_RATIO := 0.28
const OVERSPEED_DRAG := 10  #Zero is no drag, never allowing you to slow
const OVERSPEED_STEER := 3.0  # higher = sharper steering while over top speed

# Player inventory and stats
var inventory : Dictionary = {}
@onready var stats_node: PlayerStats = $PlayerStats
var health := 0.0

# Battery (a HUD can read battery_charge and the battery_capacity stat)
var battery_charge := 0.0
var recharge_delay_left := 0.0

# Battery costs
const DASH_COST := 20.0              # charge spent per dash
const JET_DRAIN_PER_SECOND := 20.0

# Gold
var gold := 0
var _gold_remainder := 0.0   # fractions left over from the multiplier, so none is lost to rounding

# Jetpack state
var can_jet := false     # true once jump has been released in the air
var is_jetting := false

#Dash
const DASH_STACK_KEEP := 0.5   # fraction of leftover overspeed carried into the next dash

var dash_hold_left := 0.0      # while > 0, drag and walking acceleration are suspended
var is_dashing: bool:
	get: return dash_hold_left > 0.0
@export_group("Audio")
## Picked at random on each dash.
@export var dash_sounds : Array[AudioStream]
@export var dash_volume_db := 0.0
## Random pitch wobble so repeated dashes don't sound identical (0.05 = ±5%).
@export var dash_pitch_variance := 0.05
## How much a stacked, faster dash raises the pitch. 0 = never, 1 = pitch follows speed 1:1.
@export_range(0.0, 1.0) var dash_stack_pitch := 0.5

@export_group("Gun Slots")
## Seconds between each gun on a side starting to fire, in fill order, so the shots don't
## all go off on the same frame. Only applies when you start holding the button; after
## that each gun keeps its own fire rate.
@export var fire_stagger := 0.04
## Most guns the player can hold. All of them exist from the start (empty), so the Tab menu
## can show every slot and guns can be dragged into any of them. 0 = no limit (slots are
## then made one at a time as guns are picked up).
@export var max_gun_slots := 8
## Spacing for a generated slot in a quadrant that has only one slot to copy the pattern
## from (x = outward, y = up, z = forward is negative).
@export var fallback_slot_step := Vector3(0.13, 0.1, 0.0)
## Until you place markers under GunMounts/Upper, each shoulder quadrant starts from its
## lower quadrant's first slot moved by this much (x = outward, y = up, z = backward is +).
@export var fallback_upper_offset := Vector3(0.05, 0.5, 0.3)

# Dash feel: dash_fx drives the screen speed blur, _shake and _fov_punch the camera jolt.
const DASH_FX_FADE_TIME := 0.35   # seconds for the blur to fade out after the dash ends
const SHAKE_DECAY := 6.0          # shake lost per second
const SHAKE_OFFSET := 0.06        # max camera offset at full shake
const FOV_PUNCH := 8.0            # extra degrees of FOV at the moment of a dash
const FOV_RECOVER := 8.0          # how fast the FOV settles back

var dash_fx := 0.0
var _shake := 0.0
var _fov_punch := 0.0
var _base_fov := 75.0

# True while the Tab menu is open: freezes camera look and interaction.
var menu_open := false

const HIT_INVULN_TIME := 0.4   # brief grace period so a swarm can't stack hits instantly
var _invuln_left := 0.0

#Shit the player be usin
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var ray_cast_3d: RayCast3D = $Head/Camera3D/RayCast3D
@onready var lower_mounts: Node3D = $Head/Camera3D/GunMounts/Lower
@onready var upper_mounts: Node3D = $Head/Camera3D/GunMounts/Upper

## The four gun areas. Right side = positive x. Guns fill 4 lower, then 4 upper, repeating.
enum Quadrant { LOWER_RIGHT, LOWER_LEFT, UPPER_RIGHT, UPPER_LEFT }

## Every gun slot made so far, in fill order.
var gun_slots: Array[Node3D] = []
# Slots per quadrant in fill order (indexed by Quadrant), and each slot's quadrant.
var _quadrant_slots: Array = [[], [], [], []]
var _slot_quadrant := {}
# Hand-placed mounts not used yet, in scene order.
var _unused_lower: Array[Node3D] = []
var _unused_upper: Array[Node3D] = []
# Time.get_ticks_msec() when each fire button started being held, -1 = not held.
var _right_held_since := -1
var _left_held_since := -1
var _auto_held_since := -1
## Per quadrant (indexed by Quadrant): true = Auto (fires by itself once the lock-on crosshair
## is on an enemy), false = Manual (fires with that side's mouse button). Set from the Tab menu.
var quadrant_auto := [false, false, false, false]
@onready var lock_on: LockOn = $Head/Camera3D/LockOn


#------- REAL SHIT -------#

#Item Pickup
func pick_up(item: ItemData) -> void:
	inventory[item] = inventory.get(item, 0) + 1
	_apply_item(item)
	GameManager.item_picked_up.emit(item)

## Adds gold, scaled by the gold_multiplier stat.
func add_gold(amount: float) -> void:
	_gold_remainder += amount * stats_node.get_value(&"gold_multiplier")
	var whole := floori(_gold_remainder)
	if whole <= 0:
		return
	_gold_remainder -= whole
	gold += whole
	GameManager.gold_changed.emit(gold)

#Item Application
func _apply_item(item: ItemData) -> void:
	var stacks: int = inventory[item]
	for mod in item.modifiers:
		var stat := stats_node.get_stat(mod.stat)
		stat.remove_source(item)  # reapply with the new stack total
		match mod.type:
			StatModifier.Type.FLAT:
				stat.add_flat(item, mod.amount_per_stack * stacks)
			StatModifier.Type.PERCENT:
				stat.add_percent(item, mod.amount_per_stack * stacks)
			StatModifier.Type.MULTIPLIER:
				stat.add_multiplier(item, pow(mod.amount_per_stack, stacks))

#-Weapon Shit-#
## True if another gun can be picked up (an empty slot, or room to make a new one).
func has_free_gun_slot() -> bool:
	return _get_free_slot() != null or max_gun_slots <= 0 or gun_slots.size() < max_gun_slots


#Gun pickup: first empty slot in fill order, or the next new slot if all are full.
## into_slot: put it in this (empty) slot instead, e.g. the Combiner's result.
func pickup_gun(gun_node : Node3D, into_slot : Node3D = null) -> void:
	var slot := into_slot if into_slot != null and into_slot.get_child_count() == 0 else _get_free_slot()
	if slot == null:
		if max_gun_slots > 0 and gun_slots.size() >= max_gun_slots:
			return
		slot = add_gun_slot()
	gun_node.reparent(slot, false)
	gun_node.global_transform = slot.global_transform


## Swaps whatever is in two gun slots (either may be empty). Used by dragging in the Tab menu.
## A gun moved to the other side then fires with that side's button.
func swap_gun_slots(a: Node3D, b: Node3D) -> void:
	if a == b:
		return
	var gun_a := a.get_child(0) if a.get_child_count() > 0 else null
	var gun_b := b.get_child(0) if b.get_child_count() > 0 else null
	for pair in [[gun_a, b], [gun_b, a]]:
		var gun : Node3D = pair[0]
		if gun == null:
			continue
		gun.reparent(pair[1], false)
		gun.transform = Transform3D.IDENTITY
		gun.reset_physics_interpolation()


## Which quadrant a gun slot is in, as a short label ("Upper L.").
static func quadrant_label(q: Quadrant) -> String:
	return ["Lower R.", "Lower L.", "Upper R.", "Upper L."][q]


func _get_free_slot() -> Node3D:
	for slot in gun_slots:
		if slot.get_child_count() == 0:
			return slot
	return null


## Which quadrant a gun slot belongs to (for per-quadrant targeting later).
func get_slot_quadrant(slot: Node3D) -> Quadrant:
	return _slot_quadrant.get(slot, Quadrant.LOWER_RIGHT)


## Every slot in one quadrant, in fill order.
func get_quadrant_slots(q: Quadrant) -> Array:
	return _quadrant_slots[q]


## Where a gun should aim. One shared lock-on target for now; this is where split
## targeting (per side, or per quadrant) will hook in later, using get_slot_quadrant().
func get_gun_aim_point(gun: Node3D) -> Vector3:
	var slot := gun.get_parent() as Node3D
	if _slot_quadrant.has(slot):
		return lock_on.get_aim_point_for(_slot_quadrant[slot])   # its quadrant's crosshair (aim modes)
	return lock_on.get_aim_point()


func _collect_gun_mounts() -> void:
	for child in lower_mounts.get_children():
		if child is Node3D:
			_unused_lower.append(child)
	for child in upper_mounts.get_children():
		if child is Node3D:
			_unused_upper.append(child)


## Adds the next slot in the fill cycle: 4 lower (right, left, right, left), then 4 upper
## in the same order, repeating. Uses the next unused hand-placed mount on that side of
## that region, or generates one by continuing the quadrant's pattern.
func add_gun_slot() -> Node3D:
	var n := gun_slots.size()
	var upper := (n / 4) % 2 == 1
	var right := (n % 4) % 2 == 0
	var q: Quadrant
	if upper:
		q = Quadrant.UPPER_RIGHT if right else Quadrant.UPPER_LEFT
	else:
		q = Quadrant.LOWER_RIGHT if right else Quadrant.LOWER_LEFT

	var slot := _take_mount(_unused_upper if upper else _unused_lower, right)
	if slot == null:
		slot = _generate_slot(q, upper, right)
	gun_slots.append(slot)
	_quadrant_slots[q].append(slot)
	_slot_quadrant[slot] = q
	return slot


# First unused mount on the wanted side (positive x = right).
func _take_mount(pool: Array[Node3D], right: bool) -> Node3D:
	for i in pool.size():
		if (pool[i].position.x >= 0.0) == right:
			var mount := pool[i]
			pool.remove_at(i)
			return mount
	return null


# A new slot one step further out than the quadrant's outermost one.
func _generate_slot(q: Quadrant, upper: bool, right: bool) -> Node3D:
	var sign_x := 1.0 if right else -1.0
	var list: Array = _quadrant_slots[q]
	var pos: Vector3
	if list.size() >= 2:
		var last: Vector3 = list[-1].position
		var prev: Vector3 = list[-2].position
		pos = last + (last - prev)
	elif list.size() == 1:
		var last: Vector3 = list[-1].position
		pos = last + Vector3(fallback_slot_step.x * sign_x, fallback_slot_step.y, fallback_slot_step.z)
	elif upper:
		# No shoulder markers on this side yet: start from the lower quadrant's first slot.
		var lower_list: Array = _quadrant_slots[Quadrant.LOWER_RIGHT if right else Quadrant.LOWER_LEFT]
		var base := Vector3(0.3 * sign_x, -0.36, -0.47)
		if not lower_list.is_empty():
			base = lower_list[0].position
		pos = base + Vector3(fallback_upper_offset.x * sign_x, fallback_upper_offset.y, fallback_upper_offset.z)
	else:
		pos = Vector3(0.3 * sign_x, -0.36, -0.47)

	var slot := Node3D.new()
	slot.name = "GeneratedSlot%d" % (gun_slots.size() + 1)
	(upper_mounts if upper else lower_mounts).add_child(slot)
	slot.position = pos
	slot.rotation.y = PI   # facing forward; it's re-aimed at the crosshair every frame anyway
	return slot


# Fires every gun on one side (lower and upper) while its button is held. When the button
# is first pressed, guns start one after another in fill order, fire_stagger apart; after
# that each keeps its own fire rate. Returns the new held-since time (-1 = released).
# Quadrants set to Auto are skipped here (they fire in _fire_auto instead).
func _fire_side(right: bool, held: bool, held_since: int) -> int:
	return _fire_slots(func(q: Quadrant) -> bool:
		var is_right := q == Quadrant.LOWER_RIGHT or q == Quadrant.UPPER_RIGHT
		return is_right == right and not quadrant_auto[q], held, held_since)


# Fires every gun in an Auto quadrant (either side) while that quadrant's lock-on crosshair
# is on an enemy, with the same staggered start as holding a mouse button.
func _fire_auto(held_since: int) -> int:
	if not quadrant_auto.has(true):
		return -1
	var any_ready := false
	for q in 4:
		if quadrant_auto[q] and lock_on.is_on_target(q):
			any_ready = true
	return _fire_slots(func(q: Quadrant) -> bool: return quadrant_auto[q] and lock_on.is_on_target(q),
			any_ready, held_since)


# Shared by manual and auto firing. want(quadrant) picks which slots fire.
func _fire_slots(want: Callable, held: bool, held_since: int) -> int:
	if not held:
		return -1
	var now := Time.get_ticks_msec()
	if held_since < 0:
		held_since = now
	var elapsed := now - held_since
	var order := 0   # counts only the chosen slots that hold a gun
	for slot in gun_slots:
		if slot.get_child_count() == 0 or not want.call(_slot_quadrant[slot]):
			continue
		if elapsed >= int(order * fire_stagger * 1000.0):
			(slot.get_child(0) as Gun).shoot()
		order += 1
	return held_since


## Switches a quadrant between Manual and Auto firing.
func set_quadrant_auto(q: Quadrant, auto: bool) -> void:
	quadrant_auto[q] = auto
			
func _ready():
	_collect_gun_mounts()
	while gun_slots.size() < max_gun_slots:
		add_gun_slot()
	_base_fov = camera.fov
	battery_charge = stats_node.get_value(&"battery_capacity")
	health = stats_node.get_value(&"max_health")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameManager.player = self
	head.top_level = true
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	head.global_position = global_position

#Mouse camera control
func _unhandled_input(event):
	if menu_open:
		return
	# Mouse wheel: aim mode (up = more crosshairs, 1-4).
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			lock_on.set_mode(lock_on.mode + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			lock_on.set_mode(lock_on.mode - 1)
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * GameManager.mouse_sensitivity)
		camera.rotate_x(-event.relative.y * GameManager.mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	if event.is_action_pressed("interact"):
		if ray_cast_3d.is_colliding():
			var box: Node3D = ray_cast_3d.get_collider()
			if box.get_parent() is Interactable:
				box.get_parent().interact(ray_cast_3d.get_collision_normal())
				

#Every physics tick
func _physics_process(delta: float) -> void:
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	var wish_dir := _get_wish_dir()
	_update_battery(delta)
	_update_health_regen(delta)
	_handle_dash_input(wish_dir)
	_apply_horizontal(delta, wish_dir)
	_apply_vertical(delta)
	move_and_slide()
	
	if menu_open:
		_left_held_since = -1
		_right_held_since = -1
		_auto_held_since = -1
		return
	#shoot
	_left_held_since = _fire_side(false, Input.is_action_pressed("shootLeft"), _left_held_since)
	_right_held_since = _fire_side(true, Input.is_action_pressed("shootRight"), _right_held_since)
	_auto_held_since = _fire_auto(_auto_held_since)
		
# ---------- Horizontal movement ----------
func _apply_horizontal(delta: float, wish_dir: Vector3) -> void:
	var max_speed := stats_node.get_value(&"move_speed")
	var accel := stats_node.get_value(&"acceleration")
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var on_floor := is_on_floor()

	var dashing := dash_hold_left > 0.0
	if dashing:
		dash_hold_left -= delta
		_mark_battery_used()   # the recharge delay only starts counting once the dash ends

	# Bleed off speed above the max, except while a dash is still holding its speed.
	if horizontal.length() > max_speed and not dashing:
		horizontal = horizontal.move_toward(horizontal.normalized() * max_speed, OVERSPEED_DRAG * delta)
	var speed := horizontal.length()
	if (speed > max_speed or dashing) and wish_dir != Vector3.ZERO:
		# Turn the velocity toward the input direction while keeping its speed.
		var steered := horizontal.normalized().move_toward(wish_dir, OVERSPEED_STEER * delta)
		horizontal = steered.normalized() * speed

	if not dashing:
		if wish_dir != Vector3.ZERO:
			var control := 1.0 if on_floor else AIR_CONTROL
			horizontal = horizontal.move_toward(wish_dir * max_speed, accel * control * delta)
		elif on_floor:
			horizontal = horizontal.move_toward(Vector3.ZERO, GLIDE_FRICTION * delta)
		# No input in the air: keep all momentum.

	velocity.x = horizontal.x
	velocity.z = horizontal.z

# ---------- Vertical movement ----------

func _apply_vertical(delta: float) -> void:
	var jump_held := Input.is_action_pressed("jump")

	if is_on_floor():
		can_jet = false
		is_jetting = false
		if Input.is_action_just_pressed("jump"):
			velocity.y = stats_node.get_value(&"jump_strength")
		return

	velocity.y -= GRAVITY * delta

	# The jetpack arms once jump has been released in the air.
	if not jump_held:
		can_jet = true

	if not (jump_held and can_jet and battery_charge > 0.0):
		is_jetting = false
		return

	is_jetting = true

	var jet := stats_node.get_value(&"jet_strength")
	var cap := maxf(velocity.y, jet * JET_RISE_SPEED_RATIO)
	velocity.y = minf(velocity.y + jet * delta, cap)

	battery_charge = maxf(battery_charge - JET_DRAIN_PER_SECOND * delta, 0.0)
	_mark_battery_used()
	
# ---------- Input ----------

# Movement direction in world space, based on where the camera is facing (yaw only).
func _get_wish_dir() -> Vector3:
	var input := Input.get_vector("left", "right", "up", "down")
	var yaw_basis := Basis(Vector3.UP, head.global_rotation.y)
	return (yaw_basis * Vector3(input.x, 0.0, input.y)).normalized()
# ---------- Battery ----------

# An action can start whenever there's enough charge.
func _can_start_action(cost: float) -> bool:
	return battery_charge >= cost


# Call whenever an action uses charge: pauses recharging until the delay is up.on.
func _mark_battery_used() -> void:
	recharge_delay_left = maxf(stats_node.get_value(&"battery_recharge_delay"), 0.0)


func _update_battery(delta: float) -> void:
	if recharge_delay_left > 0.0:
		recharge_delay_left -= delta
	else:
		battery_charge += stats_node.get_value(&"battery_recharge_rate") * delta
	battery_charge = clampf(battery_charge, 0.0, stats_node.get_value(&"battery_capacity"))


# ---------- Dash ----------

# Full blur while the dash holds, then a fade. The camera jolt decays on its own.
func _update_dash_feel(delta: float) -> void:
	if is_dashing:
		dash_fx = 1.0
	else:
		dash_fx = maxf(dash_fx - delta / DASH_FX_FADE_TIME, 0.0)

	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-FOV_RECOVER * delta))

	var s := _shake * _shake   # squared, so the jolt is sharp and dies off quickly
	camera.h_offset = randf_range(-1.0, 1.0) * SHAKE_OFFSET * s
	camera.v_offset = randf_range(-1.0, 1.0) * SHAKE_OFFSET * s
	camera.fov = _base_fov + _fov_punch


func _dash_kick(speed_ratio: float) -> void:
	dash_fx = 1.0
	_shake = 1.0
	_fov_punch = FOV_PUNCH * speed_ratio   # a stacked, faster dash punches harder

func _play_dash_sound(speed_ratio: float) -> void:
	if dash_sounds.is_empty():
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = dash_sounds.pick_random()
	audio.volume_db = dash_volume_db
	audio.pitch_scale = lerpf(1.0, speed_ratio, dash_stack_pitch) \
			* randf_range(1.0 - dash_pitch_variance, 1.0 + dash_pitch_variance)
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _handle_dash_input(wish_dir: Vector3) -> void:
	if not Input.is_action_just_pressed("dash"):
		return
	if not _can_start_action(DASH_COST):
		return

	# Dash toward the input direction, or straight ahead if there's no input.
	var dir := wish_dir
	if dir == Vector3.ZERO:
		dir = Basis(Vector3.UP, head.global_rotation.y) * Vector3.FORWARD

	var max_speed := stats_node.get_value(&"move_speed")
	var dash_speed := stats_node.get_value(&"dash_speed")
	var current := Vector2(velocity.x, velocity.z).length()
	var excess := maxf(current - max_speed, 0.0)
	var new_speed := dash_speed + excess * DASH_STACK_KEEP
	new_speed = maxf(new_speed, current)   # a dash never slows you down

	velocity.x = dir.x * new_speed
	velocity.z = dir.z * new_speed
	dash_hold_left = stats_node.get_value(&"dash_duration")
	battery_charge -= DASH_COST
	_mark_battery_used()
	var ratio := new_speed / maxf(dash_speed, 0.01)
	_play_dash_sound(ratio)
	_dash_kick(ratio)
	

# new function: tilt each gun slot toward the crosshair every frame
func _process(delta: float) -> void:
	head.global_position = get_global_transform_interpolated().origin
	_update_dash_feel(delta)
	for slot in gun_slots:
		if slot.get_child_count() > 0:
			slot.look_at(get_gun_aim_point(slot.get_child(0)), Vector3.UP, true)

#--- Damage and Hits ---#
func take_damage(amount: float) -> void:
	if _invuln_left > 0.0:
		return
	health = maxf(health - amount, 0.0)
	_invuln_left = HIT_INVULN_TIME
	if health <= 0.0:
		print("player died")   # TODO: real death handling

func apply_knockback(direction: Vector3, force: float, up: float = 0.0) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	direction = direction.normalized()
	velocity.x = direction.x * force
	velocity.z = direction.z * force
	velocity.y = maxf(velocity.y, up)

#--- Health Regen ---#
func _update_health_regen(delta: float) -> void:
	var max_hp := stats_node.get_value(&"max_health")
	if health <= 0.0 or health >= max_hp:
		return
	var regen_percent := stats_node.get_value(&"health_regen")
	health = minf(health + max_hp * (regen_percent / 100.0) * delta, max_hp)
