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
@onready var slot_1: Node3D = $Head/Camera3D/slot1
@onready var slot_2: Node3D = $Head/Camera3D/slot2
@onready var slot_3: Node3D = $Head/Camera3D/slot3
@onready var slot_4: Node3D = $Head/Camera3D/slot4
@onready var ray_cast_3d: RayCast3D = $Head/Camera3D/RayCast3D
@onready var gun_slots: Array[Node3D] = [slot_1, slot_2, slot_3, slot_4]
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
func has_free_gun_slot() -> bool:
	for slot in gun_slots:
		if slot.get_child_count() == 0:
			return true
	return false
#Gun pickup
func pickup_gun(gun_node : Node3D) -> void:
	for slot in gun_slots:
		if slot.get_child_count() == 0:
			gun_node.reparent(slot, false)
			gun_node.global_transform = slot.global_transform
			return

#Fires weapon slots
func _fire_slots(slots: Array) -> void:
	for slot in slots:
		if slot.get_child_count() > 0:
			(slot.get_child(0) as Gun).shoot()
			
func _ready():
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
		return
	#shoot
	if Input.is_action_pressed("shootLeft"):
		_fire_slots([slot_2, slot_4])
	if Input.is_action_pressed("shootRight"):
		_fire_slots([slot_1, slot_3])
		
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
	var aim_point := lock_on.get_aim_point()
	for slot in gun_slots:
		if slot.get_child_count() > 0:
			slot.look_at(aim_point, Vector3.UP, true)

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
