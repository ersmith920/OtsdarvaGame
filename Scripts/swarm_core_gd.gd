# GDScript copy of the native SwarmCore (bin/swarm_core.gdextension), with the same functions.
# The Swarm autoload uses the native one when its library is loaded (much faster: thousands of
# enemies) and falls back to this one otherwise, so the game still runs, just with fewer
# enemies before it slows down (a few thousand at most).
#
# It's also the readable version of the C++ code: same steps, same names, same tuning.
# If you change behavior here, the C++ file (native/swarm_core/src/swarm_core.cpp) needs the
# same change to match.
class_name SwarmCoreGD
extends RefCounted

const SLOT_BITS := 20
const SLOT_MASK := (1 << SLOT_BITS) - 1

const F_ALIVE := 1
const F_SPAWNING := 2
const F_CLIMBER := 4
const F_ELITE := 8
const F_NEW := 16

# Order of the stats array passed to add_unit() (same as the C++ Stat enum).
enum { S_HEALTH, S_SPEED, S_RADIUS, S_HEIGHT, S_STEP, S_CLIMB_SPEED, S_MAX_CLIMB,
	S_KB_RESIST, S_ATTACK, S_ATTACK_CD, S_KB_FORCE, S_KB_UP, S_REACH, S_SCALE,
	S_AIM, S_EMERGE_TIME, S_EMERGE_PAUSE, S_EMERGE_DEPTH, S_FLASH_TIME, S_COUNT }

# ---------- Tuning (set_tuning) ----------
var crowd_cell := 2.0
var crowd_capacity := 2
var crowd_push := 1.1
var cell_spread := 0.8
var close_range := 14.0
var max_neighbors := 6
var max_looked := 14
var pile_layer := 0.75
var pile_capacity := 1
var climber_push_scale := 0.3
var gravity := 24.0
var step_up_speed := 10.0
var fall_kill_y := -100.0
var knock_decel := 40.0
var max_knock_speed := 40.0
var player_radius := 0.5
var player_half_height := 1.0
var max_wall_climb := 30.0
var turn_rate := 10.0
var think_interval := 3
var ground_recheck := 8

# ---------- State ----------
var _terrain := SwarmTerrain.new()
var _space : PhysicsDirectSpaceState3D
var _exclude : Array[RID] = []
var _tick := 0
var _max_radius := 1.0
var _last_ms := 0.0

var _gx0 := 0.0
var _gz0 := 0.0
var _gw := 1
var _gd := 1
var _dens := PackedInt32Array()
var _keys := PackedInt64Array()
var _obstacles := PackedFloat32Array()

# Per type (Arrays are shared references, so these can be edited in place).
var _bufs : Array = []        # PackedFloat32Array per type (16 floats per instance)
var _prevs : Array = []
var _free_inst : Array = []   # Array of free instance indices per type
var _high := PackedInt32Array()
var _capacity := PackedInt32Array()

# Per slot
var _cap := 0
var _alive := PackedInt32Array()
var _alive_at := PackedInt32Array()
var _free := PackedInt32Array()
var _type := PackedInt32Array()
var _inst := PackedInt32Array()
var _flags := PackedInt32Array()
var _gold := PackedInt32Array()
var _col := PackedInt32Array()
var _flash_until := PackedInt64Array()
var _next_attack := PackedInt64Array()
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _fx := PackedFloat32Array()
var _fz := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _kx := PackedFloat32Array()
var _kz := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _gnd := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _height := PackedFloat32Array()
var _step := PackedFloat32Array()
var _climb := PackedFloat32Array()
var _max_climb := PackedFloat32Array()
var _kb_resist := PackedFloat32Array()
var _atk := PackedFloat32Array()
var _atk_cd := PackedFloat32Array()
var _kb_force := PackedFloat32Array()
var _kb_up := PackedFloat32Array()
var _reach := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _aim := PackedFloat32Array()
var _spawn_t := PackedFloat32Array()
var _surface := PackedFloat32Array()
var _emerge_time := PackedFloat32Array()
var _emerge_pause := PackedFloat32Array()
var _emerge_depth := PackedFloat32Array()
var _flash_time := PackedFloat32Array()


# ======================================================================
# Setup
# ======================================================================

func setup(bounds: AABB) -> void:
	var b := bounds.grow(4.0)
	_gx0 = b.position.x - 8.0
	_gz0 = b.position.z - 8.0
	_gw = maxi(ceili((b.size.x + 16.0) / crowd_cell), 1)
	_gd = maxi(ceili((b.size.z + 16.0) / crowd_cell), 1)
	_dens.resize(_gw * _gd)
	_terrain = SwarmTerrain.new()
	_terrain.setup(bounds, _space, _exclude)


func set_tuning(d: Dictionary) -> void:
	for key in d:
		if key in self:
			set(key, d[key])
	think_interval = maxi(think_interval, 1)
	ground_recheck = maxi(ground_recheck, 1)
	crowd_capacity = maxi(crowd_capacity, 1)
	pile_capacity = maxi(pile_capacity, 1)
	if d.has("fill_budget"):
		_terrain.fill_budget = d["fill_budget"]
	if d.has("prefill_budget"):
		_terrain.prefill_budget = d["prefill_budget"]
	if d.has("prefill_radius"):
		_terrain.prefill_radius = d["prefill_radius"]


func set_world(space_state: Object, exclude: Array[RID]) -> void:
	_space = space_state as PhysicsDirectSpaceState3D
	_exclude = exclude
	_terrain.set_space(_space, exclude)


func add_type() -> int:
	_bufs.append(PackedFloat32Array())
	_prevs.append(PackedFloat32Array())
	_free_inst.append([])
	_high.append(0)
	_capacity.append(0)
	return _bufs.size() - 1


# ======================================================================
# Units
# ======================================================================

func add_unit(type: int, pos: Vector3, st: PackedFloat32Array, flags: int, gold: int) -> int:
	var s : int
	if not _free.is_empty():
		s = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	else:
		s = _cap
		_resize_all(maxi(_cap * 2, 1024))
		for i in range(_cap - 1, s, -1):
			_free.append(i)   # popped from the end, so low slots go out first
	_type[s] = type
	_inst[s] = _take_instance(type)
	_gold[s] = gold
	_px[s] = pos.x
	_py[s] = pos.y
	_pz[s] = pos.z
	var ang := float(s % 6283) * 0.001
	_fx[s] = sin(ang)
	_fz[s] = cos(ang)
	_vx[s] = 0.0
	_vz[s] = 0.0
	_kx[s] = 0.0
	_kz[s] = 0.0
	_vy[s] = 0.0
	_hp[s] = st[S_HEALTH]
	_speed[s] = st[S_SPEED]
	_radius[s] = st[S_RADIUS]
	_height[s] = st[S_HEIGHT]
	_step[s] = st[S_STEP]
	_climb[s] = st[S_CLIMB_SPEED]
	_max_climb[s] = st[S_MAX_CLIMB]
	_kb_resist[s] = st[S_KB_RESIST]
	_atk[s] = st[S_ATTACK]
	_atk_cd[s] = st[S_ATTACK_CD]
	_kb_force[s] = st[S_KB_FORCE]
	_kb_up[s] = st[S_KB_UP]
	_reach[s] = st[S_REACH]
	_scale[s] = st[S_SCALE]
	_aim[s] = st[S_AIM]
	_emerge_time[s] = st[S_EMERGE_TIME]
	_emerge_pause[s] = st[S_EMERGE_PAUSE]
	_emerge_depth[s] = st[S_EMERGE_DEPTH]
	_flash_time[s] = st[S_FLASH_TIME]
	_spawn_t[s] = 0.0
	_surface[s] = pos.y
	_flash_until[s] = 0
	_next_attack[s] = 0
	_flags[s] = flags | F_ALIVE | F_NEW
	_col[s] = _terrain.col_of(pos.x, pos.z)
	var g := _terrain.ground(_col[s], pos.y + 0.2, _step[s], _height[s])
	_gnd[s] = pos.y if (is_nan(g) or g == -INF) else g
	_max_radius = maxf(_max_radius, _radius[s])
	_alive_at[s] = _alive.size()
	_alive.append(s)
	return s


func remove_unit(s: int) -> void:
	if not is_alive(s):
		return
	_release_instance(_type[s], _inst[s])
	_flags[s] = 0
	var i := _alive_at[s]
	var last := _alive[_alive.size() - 1]
	_alive[i] = last
	_alive_at[last] = i
	_alive.resize(_alive.size() - 1)
	_free.append(s)


func unit_count() -> int:
	return _alive.size()

func get_alive() -> PackedInt32Array:
	return _alive.duplicate()

func is_alive(s: int) -> bool:
	return s >= 0 and s < _cap and (_flags[s] & F_ALIVE) != 0

func is_spawning(s: int) -> bool:
	return is_alive(s) and (_flags[s] & F_SPAWNING) != 0

func is_elite(s: int) -> bool:
	return is_alive(s) and (_flags[s] & F_ELITE) != 0

func get_pos(s: int) -> Vector3:
	return Vector3(_px[s], _py[s], _pz[s]) if s >= 0 and s < _cap else Vector3.ZERO

func get_aim_position(s: int) -> Vector3:
	return Vector3(_px[s], _py[s] + _aim[s], _pz[s]) if s >= 0 and s < _cap else Vector3.ZERO

func get_height(s: int) -> float:
	return _height[s] if s >= 0 and s < _cap else 0.0

func get_kb_resist(s: int) -> float:
	return _kb_resist[s] if s >= 0 and s < _cap else 1.0

func get_health(s: int) -> float:
	return _hp[s] if s >= 0 and s < _cap else 0.0

func get_ground(s: int) -> float:
	return _gnd[s] if s >= 0 and s < _cap else 0.0

func get_gold(s: int) -> int:
	return _gold[s] if s >= 0 and s < _cap else 0

func get_type(s: int) -> int:
	return _type[s] if s >= 0 and s < _cap else -1

func get_attack(s: int) -> PackedFloat32Array:
	return PackedFloat32Array([_atk[s], _kb_force[s], _kb_up[s]])


## -1 = ignored (dead or still spawning), 0 = hurt, 1 = killed.
func damage(s: int, amount: float, now_ms: int) -> int:
	if not is_alive(s) or (_flags[s] & F_SPAWNING) != 0:
		return -1
	_hp[s] -= amount
	if _hp[s] <= 0.0:
		return 1
	if _flash_time[s] > 0.0:
		_flash_until[s] = now_ms + int(_flash_time[s] * 1000.0)
	return 0


func knock_back(s: int, push: Vector3, up: float) -> void:
	if not is_alive(s) or (_flags[s] & F_SPAWNING) != 0:
		return
	var keep := 1.0 - _kb_resist[s]
	if keep <= 0.0:
		return
	var v := Vector2(_kx[s] + push.x * keep, _kz[s] + push.z * keep).limit_length(max_knock_speed)
	_kx[s] = v.x
	_kz[s] = v.y
	if up > 0.0:
		_vy[s] = maxf(_vy[s], up * keep)


func set_obstacles(xzr: PackedFloat32Array) -> void:
	_obstacles = xzr


# ======================================================================
# Simulation
# ======================================================================

## Moves every enemy one physics tick. Returns events as pairs: [1, slot] = that enemy hit the
## player (read its get_attack()), [2, slot] = it fell out of the world (remove it).
func step(delta: float, ppos: Vector3, now_ms: int) -> PackedInt32Array:
	var t0 := Time.get_ticks_usec()
	var events := PackedInt32Array()
	_tick += 1
	_terrain.begin_tick(ppos)
	if _alive.is_empty():
		_render(now_ms)
		_last_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return events
	_build_grid()

	var feet := ppos.y - player_half_height
	var head := ppos.y + player_half_height
	var turn := 1.0 - exp(-turn_rate * delta * think_interval)
	var close2 := close_range * close_range
	var terrain := _terrain
	var prev_cell := -1
	var rank := 0
	var gw := _gw
	var gd := _gd
	var tick := _tick
	var knock_drop := knock_decel * delta
	var cap := crowd_capacity

	for k in _keys.size():
		var key := _keys[k]
		var s := key & SLOT_MASK
		var c := key >> SLOT_BITS
		if c == prev_cell:
			rank += 1
		else:
			prev_cell = c
			rank = 0
		var f := _flags[s]
		if (f & F_ALIVE) == 0:
			continue
		if (f & F_SPAWNING) != 0:
			_step_spawn(s, delta)
			continue

		var x := _px[s]
		var y := _py[s]
		var z := _pz[s]
		var h := _height[s]
		var here := _dens[c]
		var nx := 0.0
		var nz := 0.0

		# --- Think (staggered): pick a velocity, collide near the player, attack ---
		if (s + tick) % think_interval == 0:
			var r := _radius[s]
			var spd := _speed[s]
			var dx := ppos.x - x
			var dz := ppos.z - z
			var d2 := dx * dx + dz * dz
			var d := sqrt(d2)
			var vx := 0.0
			var vz := 0.0
			if d > 0.01:
				var wx := dx / d
				var wz := dz / d
				vx = wx * spd
				vz = wz * spd
				var fx := _fx[s] + (wx - _fx[s]) * turn
				var fz := _fz[s] + (wz - _fz[s]) * turn
				var fl := sqrt(fx * fx + fz * fz)
				if fl > 0.0001:
					_fx[s] = fx / fl
					_fz[s] = fz / fl
			# Climbers spread out less: they deal with a crowd by climbing it instead.
			var push_k := climber_push_scale if (f & F_CLIMBER) != 0 else 1.0
			var cx := c % gw
			var cz := c / gw
			if cx > 0 and cz > 0 and cx < gw - 1 and cz < gd - 1:
				vx += float(_dens[c - 1] - _dens[c + 1]) * crowd_push * push_k
				vz += float(_dens[c - gw] - _dens[c + gw]) * crowd_push * push_k
			if here > cap:
				var a := float(s) * 2.39996   # golden angle: each enemy its own direction
				var spread := float(here - cap) * cell_spread * push_k
				vx += cos(a) * spread
				vz += sin(a) * spread
			_vx[s] = vx
			_vz[s] = vz
			if d2 < close2:
				var push := _separate(s, x, y, z, r, h, c)
				nx = push.x
				nz = push.y
				if y < head and y + h > feet:
					var min_d := r + player_radius
					if d2 < min_d * min_d:
						var dd := maxf(d, 0.001)
						nx -= dx / dd * (min_d - d)
						nz -= dz / dd * (min_d - d)
					var reach := r + player_radius + _reach[s]
					if d2 <= reach * reach and now_ms >= _next_attack[s]:
						_next_attack[s] = now_ms + int(_atk_cd[s] * 1000.0)
						events.append(1)
						events.append(s)

		# --- Move every tick with the last chosen velocity plus knockback ---
		var mvx := _vx[s]
		var mvz := _vz[s]
		var kx := _kx[s]
		var kz := _kz[s]
		if kx != 0.0 or kz != 0.0:
			mvx += kx
			mvz += kz
			var kl := sqrt(kx * kx + kz * kz)
			if kl <= knock_drop:
				_kx[s] = 0.0
				_kz[s] = 0.0
			else:
				_kx[s] = kx * (1.0 - knock_drop / kl)
				_kz[s] = kz * (1.0 - knock_drop / kl)
		nx += x + mvx * delta
		nz += z + mvz * delta

		# --- Terrain, one axis at a time (slides along walls) ---
		var col := _col[s]
		var colx := terrain.col_of(nx, z)
		var colz := terrain.col_of(nx, nz)
		var climbing := false
		var climber := (f & F_CLIMBER) != 0
		if colx == col and colz == col:
			x = nx
			z = nz
		else:
			var gnd := _gnd[s]
			var stp := _step[s]
			if colx == col:
				x = nx
			else:
				var g := terrain.ground(colx, y, stp, h)
				if is_nan(g):
					x = nx
				elif g == -INF:
					climbing = climber and _can_climb(colx, y, stp, gnd)
				else:
					x = nx
					col = colx
					gnd = g
			var colz2 := terrain.col_of(x, nz)
			if colz2 == col:
				z = nz
			else:
				var g2 := terrain.ground(colz2, y, stp, h)
				if is_nan(g2):
					z = nz
				elif g2 == -INF:
					climbing = climbing or (climber and _can_climb(colz2, y, stp, gnd))
				else:
					z = nz
					col = colz2
					gnd = g2
			_col[s] = col
			_gnd[s] = gnd
		if (s + tick) % ground_recheck == 0:
			var g3 := terrain.ground(col, y + 0.05, _step[s], h)
			if not is_nan(g3) and g3 != -INF:
				_gnd[s] = g3

		# --- Vertical: gravity, stepping up, climbing walls, piling on the crowd ---
		var floor_y := _gnd[s]
		# Piling: in a crowded cell, each climber stands on the ones before it, pile_capacity
		# enemies per layer, up to its max climb height.
		if climber and rank >= pile_capacity:
			floor_y += minf(float(rank / pile_capacity) * h * pile_layer, _max_climb[s])
		var vy := _vy[s]
		if climbing:
			y += _climb[s] * delta
			vy = 0.0
		elif y < floor_y - 0.001:
			y = minf(y + (_climb[s] if climber else step_up_speed) * delta, floor_y)
			vy = 0.0
		elif y > floor_y or vy > 0.0:
			vy -= gravity * delta
			y = maxf(y + vy * delta, floor_y)
			if y <= floor_y:
				vy = 0.0
		_vy[s] = vy
		_px[s] = x
		_py[s] = y
		_pz[s] = z
		if y < fall_kill_y:
			events.append(2)
			events.append(s)

	_render(now_ms)
	_last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return events


func _build_grid() -> void:
	var n := _alive.size()
	_keys.resize(n)
	_dens.fill(0)
	var inv := 1.0 / crowd_cell
	for k in n:
		var s := _alive[k]
		var cx := clampi(int((_px[s] - _gx0) * inv), 0, _gw - 1)
		var cz := clampi(int((_pz[s] - _gz0) * inv), 0, _gd - 1)
		var c := cx + cz * _gw
		_keys[k] = (c << SLOT_BITS) | s
		_dens[c] += 1
	# Node enemies (tanks, bosses) make their cells look crowded so the swarm flows around them.
	var i := 0
	while i + 2 < _obstacles.size():
		var r := ceili(_obstacles[i + 2] / crowd_cell)
		var cc := _cell_coords(_obstacles[i], _obstacles[i + 1])
		for gz in range(maxi(cc.y - r, 0), mini(cc.y + r, _gd - 1) + 1):
			for gx in range(maxi(cc.x - r, 0), mini(cc.x + r, _gw - 1) + 1):
				_dens[gx + gz * _gw] += crowd_capacity * 2
		i += 3
	_keys.sort()


func _can_climb(col: int, y: float, stp: float, gnd: float) -> bool:
	var top := _terrain.wall_top(col, y, stp)
	return top != -INF and top - gnd <= max_wall_climb


func _step_spawn(s: int, delta: float) -> void:
	_spawn_t[s] += delta
	if _spawn_t[s] < _emerge_time[s]:
		var k := _spawn_t[s] / _emerge_time[s]
		k = 1.0 - (1.0 - k) * (1.0 - k)   # ease out
		_py[s] = _surface[s] - _emerge_depth[s] * (1.0 - k)
	else:
		_py[s] = _surface[s]
	if _spawn_t[s] >= _emerge_time[s] + _emerge_pause[s]:
		_flags[s] &= ~F_SPAWNING


# One-on-one push apart from the nearest few neighbors (only used near the player).
# The 3 cells of each grid row are next to each other in the sorted keys.
func _separate(s: int, x: float, y: float, z: float, r: float, h: float, cell: int) -> Vector2:
	var px := 0.0
	var pz := 0.0
	var overlaps := 0
	var looked := 0
	var cx := cell % _gw
	var cz := cell / _gw
	var x0 := maxi(cx - 1, 0)
	var x1 := mini(cx + 1, _gw - 1)
	var n := _keys.size()
	for gz in range(maxi(cz - 1, 0), mini(cz + 1, _gd - 1) + 1):
		var last := x1 + gz * _gw
		var k := _keys.bsearch((x0 + gz * _gw) << SLOT_BITS, true)
		while k < n:
			var key := _keys[k]
			k += 1
			if (key >> SLOT_BITS) > last:
				break
			var o := key & SLOT_MASK
			if o == s:
				continue
			looked += 1
			if looked > max_looked:
				break
			var oy := _py[o]
			if oy >= y + h - 0.05 or oy + _height[o] <= y + 0.05:
				continue
			var dx := x - _px[o]
			var dz := z - _pz[o]
			var md := r + _radius[o]
			var dsq := dx * dx + dz * dz
			if dsq >= md * md:
				continue
			if dsq < 0.000001:
				var a := float(s) * 2.39996
				px += cos(a) * md * 0.5
				pz += sin(a) * md * 0.5
			else:
				var dist := sqrt(dsq)
				var f := (md - dist) * 0.5 / dist
				px += dx * f
				pz += dz * f
			overlaps += 1
			if overlaps >= max_neighbors:
				break
		if overlaps >= max_neighbors or looked > max_looked:
			break
	var k2 := 0.6 if (_flags[s] & F_CLIMBER) != 0 else 1.0
	return Vector2(px * k2, pz * k2)


# ======================================================================
# Drawing buffers
# ======================================================================

func _take_instance(type: int) -> int:
	var free_list : Array = _free_inst[type]
	if not free_list.is_empty():
		return free_list.pop_back()
	if _high[type] >= _capacity[type]:
		var cap := maxi(_capacity[type] * 2, 256)
		_capacity[type] = cap
		var b : PackedFloat32Array = _bufs[type]
		_bufs[type] = PackedFloat32Array()
		b.resize(cap * 16)
		_bufs[type] = b
		var p : PackedFloat32Array = _prevs[type]
		_prevs[type] = PackedFloat32Array()
		p.resize(cap * 16)
		_prevs[type] = p
	_high[type] += 1
	return _high[type] - 1


func _release_instance(type: int, i: int) -> void:
	var b : PackedFloat32Array = _bufs[type]
	var p : PackedFloat32Array = _prevs[type]
	_bufs[type] = PackedFloat32Array()
	_prevs[type] = PackedFloat32Array()
	for k in 16:
		b[i * 16 + k] = 0.0
		p[i * 16 + k] = 0.0
	_bufs[type] = b
	_prevs[type] = p
	(_free_inst[type] as Array).append(i)


# Last tick's transforms become the "previous" ones, then this tick's are written.
# Only the 9 numbers that change are written; the rest are set when an enemy appears.
func _render(now_ms: int) -> void:
	var single := _bufs.size() == 1
	for ti in _bufs.size():
		var buf : PackedFloat32Array = _prevs[ti]   # swapped: the old "previous" gets overwritten
		var prev : PackedFloat32Array = _bufs[ti]
		_bufs[ti] = PackedFloat32Array()
		_prevs[ti] = PackedFloat32Array()
		for s in _alive:
			if not single and _type[s] != ti:
				continue
			var b := _inst[s] * 16
			var sc := _scale[s]
			var cs := -_fz[s] * sc
			var sn := -_fx[s] * sc
			buf[b] = cs
			buf[b + 2] = sn
			buf[b + 3] = _px[s]
			buf[b + 7] = _py[s]
			buf[b + 8] = -sn
			buf[b + 10] = cs
			buf[b + 11] = _pz[s]
			buf[b + 12] = 1.0 if now_ms < _flash_until[s] else 0.0
			if (_flags[s] & F_NEW) != 0:
				_flags[s] &= ~F_NEW
				buf[b + 1] = 0.0
				buf[b + 4] = 0.0
				buf[b + 5] = sc
				buf[b + 6] = 0.0
				buf[b + 9] = 0.0
				buf[b + 13] = 0.0
				buf[b + 14] = 0.0
				buf[b + 15] = 0.0
				for i in 16:
					prev[b + i] = buf[b + i]
		_bufs[ti] = buf
		_prevs[ti] = prev


func get_buffer(type: int) -> PackedFloat32Array:
	return _bufs[type]

func get_prev_buffer(type: int) -> PackedFloat32Array:
	return _prevs[type]

func get_instance_capacity(type: int) -> int:
	return _capacity[type]

func get_visible_count(type: int) -> int:
	return _high[type]


# ======================================================================
# Queries
# ======================================================================

func raycast(from: Vector3, to: Vector3, skip: PackedInt32Array) -> Dictionary:
	if _alive.is_empty() or _keys.is_empty():
		return {}
	var pad := _max_radius
	var c0 := _cell_coords(minf(from.x, to.x) - pad, minf(from.z, to.z) - pad)
	var c1 := _cell_coords(maxf(from.x, to.x) + pad, maxf(from.z, to.z) + pad)
	var dx := to.x - from.x
	var dy := to.y - from.y
	var dz := to.z - from.z
	var a := dx * dx + dz * dz
	var best_t := INF
	var best_s := -1
	var n := _keys.size()
	for cz in range(c0.y, c1.y + 1):
		var last := c1.x + cz * _gw
		var k := _keys.bsearch((c0.x + cz * _gw) << SLOT_BITS, true)
		while k < n and (_keys[k] >> SLOT_BITS) <= last:
			var s := _keys[k] & SLOT_MASK
			k += 1
			if (_flags[s] & (F_ALIVE | F_SPAWNING)) != F_ALIVE:
				continue
			if not skip.is_empty() and skip.has(s):
				continue
			var ox := from.x - _px[s]
			var oz := from.z - _pz[s]
			var r := _radius[s]
			var cc := ox * ox + oz * oz - r * r
			var t_in := 0.0
			var t_out := 1.0
			if a > 0.000001:
				var b := 2.0 * (dx * ox + dz * oz)
				var disc := b * b - 4.0 * a * cc
				if disc < 0.0:
					continue
				var sq := sqrt(disc)
				t_in = (-b - sq) / (2.0 * a)
				t_out = (-b + sq) / (2.0 * a)
			elif cc > 0.0:
				continue
			var lo := _py[s]
			var hi := lo + _height[s]
			var ty0 := 0.0
			var ty1 := 1.0
			if absf(dy) > 0.000001:
				var ta := (lo - from.y) / dy
				var tb := (hi - from.y) / dy
				ty0 = minf(ta, tb)
				ty1 = maxf(ta, tb)
			elif from.y < lo or from.y > hi:
				continue
			var enter := maxf(maxf(t_in, ty0), 0.0)
			var leave := minf(minf(t_out, ty1), 1.0)
			if enter <= leave and enter < best_t:
				best_t = enter
				best_s = s
	if best_s < 0:
		return {}
	var p := from + (to - from) * best_t
	var nrm := Vector3(p.x - _px[best_s], 0.0, p.z - _pz[best_s])
	nrm = nrm.normalized() if nrm.length_squared() > 0.0001 else -(to - from).normalized()
	return {"slot": best_s, "position": p, "normal": nrm, "fraction": best_t}


func query_sphere(center: Vector3, radius: float, max_results: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _alive.is_empty() or _keys.is_empty():
		return out
	var reach := radius + _max_radius
	var c0 := _cell_coords(center.x - reach, center.z - reach)
	var c1 := _cell_coords(center.x + reach, center.z + reach)
	var n := _keys.size()
	for cz in range(c0.y, c1.y + 1):
		var last := c1.x + cz * _gw
		var k := _keys.bsearch((c0.x + cz * _gw) << SLOT_BITS, true)
		while k < n and (_keys[k] >> SLOT_BITS) <= last:
			var s := _keys[k] & SLOT_MASK
			k += 1
			if (_flags[s] & (F_ALIVE | F_SPAWNING)) != F_ALIVE:
				continue
			var dx := center.x - _px[s]
			var dz := center.z - _pz[s]
			var dy := center.y - clampf(center.y, _py[s], _py[s] + _height[s])
			var r := radius + _radius[s]
			if dx * dx + dz * dz + dy * dy <= r * r:
				out.append(s)
				if out.size() >= max_results:
					return out
	return out


## [slot, distance_squared] of the closest live enemy within max_range, or [] if none.
func find_nearest(from: Vector3, max_range: float, skip: PackedInt32Array) -> PackedFloat32Array:
	if _alive.is_empty() or _keys.is_empty():
		return PackedFloat32Array()
	var best_s := -1
	var best_d := max_range * max_range
	var c := _cell_coords(from.x, from.z)
	var max_ring := ceili(max_range / crowd_cell) + 1
	var n := _keys.size()
	for ring in max_ring + 1:
		var ring_min := maxf(float(ring - 1) * crowd_cell, 0.0)
		if best_s >= 0 and ring_min * ring_min > best_d:
			break
		for gz in range(c.y - ring, c.y + ring + 1):
			if gz < 0 or gz >= _gd:
				continue
			for gx in range(c.x - ring, c.x + ring + 1):
				if gx < 0 or gx >= _gw:
					continue
				if absi(gx - c.x) != ring and absi(gz - c.y) != ring:
					continue
				var cell := gx + gz * _gw
				var k := _keys.bsearch(cell << SLOT_BITS, true)
				while k < n and (_keys[k] >> SLOT_BITS) == cell:
					var s := _keys[k] & SLOT_MASK
					k += 1
					if (_flags[s] & (F_ALIVE | F_SPAWNING)) != F_ALIVE:
						continue
					if not skip.is_empty() and skip.has(s):
						continue
					var dx := from.x - _px[s]
					var dy := from.y - (_py[s] + _height[s] * 0.5)
					var dz := from.z - _pz[s]
					var d := dx * dx + dy * dy + dz * dz
					if d < best_d:
						best_d = d
						best_s = s
	if best_s < 0:
		return PackedFloat32Array()
	return PackedFloat32Array([best_s, best_d])


## The `limit` most centered enemies inside the cone, as [angle, slot, angle, slot, ...].
func lock_candidates(origin: Vector3, forward: Vector3, max_angle: float, max_range: float, limit: int) -> PackedFloat32Array:
	var best : Array = []   # [cos, slot], biggest cos first
	var cos_max := cos(max_angle)
	var r2 := max_range * max_range
	var worst := cos_max
	for s in _alive:
		if (_flags[s] & F_SPAWNING) != 0:
			continue
		var dx := _px[s] - origin.x
		var dz := _pz[s] - origin.z
		var hh := dx * dx + dz * dz
		if hh > r2:
			continue
		var dy := _py[s] + _aim[s] - origin.y
		var d2 := hh + dy * dy
		if d2 < 0.0001:
			continue
		var dot := dx * forward.x + dy * forward.y + dz * forward.z
		if dot <= 0.0:
			continue
		var c := dot / sqrt(d2)
		if c < worst:
			continue
		var i := best.size()
		while i > 0 and best[i - 1][0] < c:
			i -= 1
		best.insert(i, [c, s])
		if best.size() > limit:
			best.resize(limit)
			worst = best[limit - 1][0]
	var out := PackedFloat32Array()
	for e in best:
		out.append(acos(clampf(e[0], -1.0, 1.0)))
		out.append(e[1])
	return out


func get_last_step_ms() -> float:
	return _last_ms

func get_terrain_size() -> Vector2i:
	return Vector2i(_terrain.width, _terrain.depth)

func get_grid_size() -> Vector2i:
	return Vector2i(_gw, _gd)


# ======================================================================
# Storage
# ======================================================================

func _cell_coords(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floorf((x - _gx0) / crowd_cell)), 0, _gw - 1),
			clampi(int(floorf((z - _gz0) / crowd_cell)), 0, _gd - 1))


func _resize_all(n: int) -> void:
	_cap = n
	for arr_name in ["_alive_at", "_type", "_inst", "_flags", "_gold", "_col", "_flash_until",
			"_next_attack", "_px", "_py", "_pz", "_fx", "_fz", "_vx", "_vz", "_kx", "_kz", "_vy",
			"_gnd", "_hp", "_speed", "_radius", "_height", "_step", "_climb", "_max_climb",
			"_kb_resist", "_atk", "_atk_cd", "_kb_force", "_kb_up", "_reach", "_scale", "_aim",
			"_spawn_t", "_surface", "_emerge_time", "_emerge_pause", "_emerge_depth", "_flash_time"]:
		var arr = get(arr_name)
		arr.resize(n)   # only happens when the swarm grows, so the copy doesn't matter
		set(arr_name, arr)
