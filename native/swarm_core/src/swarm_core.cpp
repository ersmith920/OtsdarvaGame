#include "swarm_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

static constexpr int SLOT_BITS = 20;
static constexpr uint64_t SLOT_MASK = (1ull << SLOT_BITS) - 1;
static constexpr float CLEARANCE_CHECK = 30.0f;
static const float NEG_INF = -std::numeric_limits<float>::infinity();
static const float NAN_F = std::numeric_limits<float>::quiet_NaN();

SwarmCore::SwarmCore() {
	q_down.instantiate();
	q_up.instantiate();
	q_down->set_collision_mask(1);
	q_up->set_collision_mask(1);
	q_down->set_collide_with_areas(false);
	q_up->set_collide_with_areas(false);
	q_down->set_hit_from_inside(false);
	q_up->set_hit_from_inside(true);   // starting inside a solid = no open space at all
}

// ============================================================ setup

void SwarmCore::setup(const AABB &p_bounds) {
	AABB b = p_bounds.grow(4.0f);
	// Terrain cache
	t_ox = b.position.x;
	t_oz = b.position.z;
	t_w = std::max(1, (int)std::ceil(b.size.x / t_cell));
	t_d = std::max(1, (int)std::ceil(b.size.z / t_cell));
	t_top = b.position.y + b.size.y + 5.0f;
	t_bottom = b.position.y - 5.0f;
	t_count.assign((size_t)t_w * t_d, UNKNOWN);
	t_tops.assign((size_t)t_w * t_d * MAX_LAYERS, 0.0f);
	t_clear.assign((size_t)t_w * t_d * MAX_LAYERS, 0.0f);
	// Crowd grid
	gx0 = b.position.x - 8.0f;
	gz0 = b.position.z - 8.0f;
	gw = std::max(1, (int)std::ceil((b.size.x + 16.0f) / crowd_cell));
	gd = std::max(1, (int)std::ceil((b.size.z + 16.0f) / crowd_cell));
	dens.assign((size_t)gw * gd, 0);
	pf_cx = pf_cz = -99999;
}

void SwarmCore::set_tuning(const Dictionary &d) {
#define TUNE_F(name) if (d.has(#name)) name = (float)d[#name];
#define TUNE_I(name) if (d.has(#name)) name = (int)d[#name];
	TUNE_F(crowd_cell)
	TUNE_I(crowd_capacity)
	TUNE_F(crowd_push)
	TUNE_F(cell_spread)
	TUNE_F(close_range)
	TUNE_I(max_neighbors)
	TUNE_I(max_looked)
	TUNE_F(pile_layer)
	TUNE_F(gravity)
	TUNE_F(step_up_speed)
	TUNE_F(fall_kill_y)
	TUNE_F(knock_decel)
	TUNE_F(max_knock_speed)
	TUNE_F(player_radius)
	TUNE_F(player_half_height)
	TUNE_F(max_wall_climb)
	TUNE_F(turn_rate)
	TUNE_I(think_interval)
	TUNE_I(ground_recheck)
	TUNE_I(fill_budget)
	TUNE_I(prefill_budget)
	TUNE_I(prefill_radius)
#undef TUNE_F
#undef TUNE_I
	think_interval = std::max(think_interval, 1);
	ground_recheck = std::max(ground_recheck, 1);
	crowd_capacity = std::max(crowd_capacity, 1);
}

void SwarmCore::set_world(Object *space_state, const TypedArray<RID> &exclude) {
	space = Object::cast_to<PhysicsDirectSpaceState3D>(space_state);
	q_down->set_exclude(exclude);
	q_up->set_exclude(exclude);
}

int SwarmCore::add_type() {
	types.emplace_back();
	return (int)types.size() - 1;
}

// ============================================================ units

int SwarmCore::take_instance(int type) {
	Type &t = types[type];
	if (!t.free_inst.empty()) {
		int i = t.free_inst.back();
		t.free_inst.pop_back();
		return i;
	}
	if (t.high >= t.capacity) {
		t.capacity = std::max(t.capacity * 2, 256);
		t.buf.resize((size_t)t.capacity * 16, 0.0f);
		t.prev.resize((size_t)t.capacity * 16, 0.0f);
	}
	return t.high++;
}

void SwarmCore::release_instance(int type, int inst) {
	Type &t = types[type];
	std::fill(t.buf.begin() + (size_t)inst * 16, t.buf.begin() + (size_t)inst * 16 + 16, 0.0f);
	std::fill(t.prev.begin() + (size_t)inst * 16, t.prev.begin() + (size_t)inst * 16 + 16, 0.0f);
	t.free_inst.push_back(inst);
}

int SwarmCore::add_unit(int type, const Vector3 &pos, const PackedFloat32Array &st, int flags, int gold) {
	ERR_FAIL_INDEX_V(type, (int)types.size(), -1);
	ERR_FAIL_COND_V(st.size() < S_COUNT, -1);
	int s;
	if (!free_slots.empty()) {
		s = free_slots.back();
		free_slots.pop_back();
	} else {
		s = (int)units.size();
		ERR_FAIL_COND_V(s >= (1 << SLOT_BITS), -1);
		units.emplace_back();
		alive_at.push_back(0);
	}
	Unit u;
	u.px = pos.x;
	u.py = pos.y;
	u.pz = pos.z;
	float ang = (float)(s % 6283) * 0.001f;
	u.fx = std::sin(ang);
	u.fz = std::cos(ang);
	u.hp = st[S_HEALTH];
	u.speed = st[S_SPEED];
	u.radius = st[S_RADIUS];
	u.height = st[S_HEIGHT];
	u.step = st[S_STEP];
	u.climb = st[S_CLIMB_SPEED];
	u.max_climb = st[S_MAX_CLIMB];
	u.kb_resist = st[S_KB_RESIST];
	u.atk = st[S_ATTACK];
	u.atk_cd = st[S_ATTACK_CD];
	u.kb_force = st[S_KB_FORCE];
	u.kb_up = st[S_KB_UP];
	u.reach = st[S_REACH];
	u.scale = st[S_SCALE];
	u.aim = st[S_AIM];
	u.emerge_time = st[S_EMERGE_TIME];
	u.emerge_pause = st[S_EMERGE_PAUSE];
	u.emerge_depth = st[S_EMERGE_DEPTH];
	u.flash_time = st[S_FLASH_TIME];
	u.surface = pos.y;
	u.type = type;
	u.inst = take_instance(type);
	u.gold = gold;
	u.flags = flags | F_ALIVE | F_NEW;
	u.col = col_of(pos.x, pos.z);
	float g = ground(u.col, pos.y + 0.2f, u.step, u.height);
	u.gnd = (std::isnan(g) || g == NEG_INF) ? pos.y : g;
	units[s] = u;
	max_radius = std::max(max_radius, u.radius);
	alive_at[s] = (int)alive.size();
	alive.push_back(s);
	return s;
}

void SwarmCore::remove_unit(int s) {
	if (!alive_ok(s)) {
		return;
	}
	Unit &u = units[s];
	release_instance(u.type, u.inst);
	u.flags = 0;
	int i = alive_at[s];
	int last = alive.back();
	alive[i] = last;
	alive_at[last] = i;
	alive.pop_back();
	free_slots.push_back(s);
}

PackedInt32Array SwarmCore::get_alive() const {
	PackedInt32Array out;
	out.resize((int64_t)alive.size());
	if (!alive.empty()) {
		memcpy(out.ptrw(), alive.data(), alive.size() * sizeof(int32_t));
	}
	return out;
}

Vector3 SwarmCore::get_pos(int s) const {
	if (s < 0 || s >= (int)units.size()) return Vector3();
	const Unit &u = units[s];
	return Vector3(u.px, u.py, u.pz);
}

Vector3 SwarmCore::get_aim_position(int s) const {
	if (s < 0 || s >= (int)units.size()) return Vector3();
	const Unit &u = units[s];
	return Vector3(u.px, u.py + u.aim, u.pz);
}

float SwarmCore::get_height(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].height : 0.0f; }
float SwarmCore::get_kb_resist(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].kb_resist : 1.0f; }
float SwarmCore::get_health(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].hp : 0.0f; }
float SwarmCore::get_ground(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].gnd : 0.0f; }
int SwarmCore::get_gold(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].gold : 0; }
int SwarmCore::get_type(int s) const { return (s >= 0 && s < (int)units.size()) ? units[s].type : -1; }

PackedFloat32Array SwarmCore::get_attack(int s) const {
	PackedFloat32Array out;
	if (s >= 0 && s < (int)units.size()) {
		out.push_back(units[s].atk);
		out.push_back(units[s].kb_force);
		out.push_back(units[s].kb_up);
	}
	return out;
}

int SwarmCore::damage(int s, float amount, int64_t now_ms) {
	if (!alive_ok(s) || (units[s].flags & F_SPAWNING)) {
		return -1;
	}
	Unit &u = units[s];
	u.hp -= amount;
	if (u.hp <= 0.0f) {
		return 1;
	}
	if (u.flash_time > 0.0f) {
		u.flash_until = now_ms + (int64_t)(u.flash_time * 1000.0f);
	}
	return 0;
}

void SwarmCore::knock_back(int s, const Vector3 &push, float up) {
	if (!alive_ok(s) || (units[s].flags & F_SPAWNING)) {
		return;
	}
	Unit &u = units[s];
	float keep = 1.0f - u.kb_resist;
	if (keep <= 0.0f) {
		return;
	}
	float vx = u.kx + push.x * keep;
	float vz = u.kz + push.z * keep;
	float l = std::sqrt(vx * vx + vz * vz);
	if (l > max_knock_speed) {
		vx *= max_knock_speed / l;
		vz *= max_knock_speed / l;
	}
	u.kx = vx;
	u.kz = vz;
	if (up > 0.0f) {
		u.vy = std::max(u.vy, up * keep);
	}
}

void SwarmCore::set_obstacles(const PackedFloat32Array &xzr) {
	obstacles.resize((size_t)xzr.size());
	if (xzr.size() > 0) {
		memcpy(obstacles.data(), xzr.ptr(), (size_t)xzr.size() * sizeof(float));
	}
}

// ============================================================ grid helpers

int SwarmCore::cell_x(float x) const { return std::clamp((int)std::floor((x - gx0) / crowd_cell), 0, gw - 1); }
int SwarmCore::cell_z(float z) const { return std::clamp((int)std::floor((z - gz0) / crowd_cell), 0, gd - 1); }
int SwarmCore::cell_of(float x, float z) const { return cell_x(x) + cell_z(z) * gw; }

void SwarmCore::build_grid() {
	keys.resize(alive.size());
	std::fill(dens.begin(), dens.end(), 0);
	for (size_t k = 0; k < alive.size(); k++) {
		int s = alive[k];
		const Unit &u = units[s];
		int c = cell_of(u.px, u.pz);
		keys[k] = ((uint64_t)c << SLOT_BITS) | (uint64_t)s;
		dens[c]++;
	}
	// Node enemies (tanks, bosses) make their cells look crowded so the swarm flows around them.
	for (size_t i = 0; i + 2 < obstacles.size(); i += 3) {
		int r = (int)std::ceil(obstacles[i + 2] / crowd_cell);
		int cx = cell_x(obstacles[i]);
		int cz = cell_z(obstacles[i + 1]);
		for (int z = std::max(cz - r, 0); z <= std::min(cz + r, gd - 1); z++) {
			for (int x = std::max(cx - r, 0); x <= std::min(cx + r, gw - 1); x++) {
				dens[x + z * gw] += crowd_capacity * 2;
			}
		}
	}
	std::sort(keys.begin(), keys.end());
}

// ============================================================ terrain

int SwarmCore::col_of(float x, float z) const {
	int cx = (int)std::floor((x - t_ox) / t_cell);
	int cz = (int)std::floor((z - t_oz) / t_cell);
	if (cx < 0 || cz < 0 || cx >= t_w || cz >= t_d) {
		return -1;
	}
	return cx + cz * t_w;
}

void SwarmCore::measure(int col) {
	if (space == nullptr) {
		return;
	}
	int cx = col % t_w;
	int cz = col / t_w;
	float x = t_ox + (cx + 0.5f) * t_cell;
	float z = t_oz + (cz + 0.5f) * t_cell;
	float from_y = t_top;
	int layers = 0;
	size_t base = (size_t)col * MAX_LAYERS;
	while (layers < MAX_LAYERS && from_y > t_bottom) {
		q_down->set_from(Vector3(x, from_y, z));
		q_down->set_to(Vector3(x, t_bottom, z));
		Dictionary hit = space->intersect_ray(q_down);
		if (hit.is_empty()) {
			break;
		}
		float t = ((Vector3)hit["position"]).y;
		q_up->set_from(Vector3(x, t + 0.05f, z));
		q_up->set_to(Vector3(x, t + 0.05f + CLEARANCE_CHECK, z));
		Dictionary up = space->intersect_ray(q_up);
		float clearance = up.is_empty() ? CLEARANCE_CHECK : (((Vector3)up["position"]).y - (t + 0.05f));
		t_tops[base + layers] = t;
		t_clear[base + layers] = clearance;
		layers++;
		from_y = t - 0.05f;
	}
	t_count[col] = (uint8_t)layers;
}

float SwarmCore::ground(int col, float y, float step, float height) {
	if (col < 0) {
		return NEG_INF;
	}
	uint8_t n = t_count[col];
	if (n == UNKNOWN) {
		if (fills_left <= 0 || space == nullptr) {
			return NAN_F;
		}
		fills_left--;
		measure(col);
		n = t_count[col];
	}
	float best = NEG_INF;
	size_t base = (size_t)col * MAX_LAYERS;
	for (int i = 0; i < n; i++) {
		float t = t_tops[base + i];
		if (t <= y + step && t_clear[base + i] >= height && t > best) {
			best = t;
		}
	}
	return best;
}

float SwarmCore::wall_top(int col, float y, float step) const {
	if (col < 0 || t_count[col] == UNKNOWN) {
		return NEG_INF;
	}
	float lowest = std::numeric_limits<float>::infinity();
	size_t base = (size_t)col * MAX_LAYERS;
	for (int i = 0; i < t_count[col]; i++) {
		float t = t_tops[base + i];
		if (t > y + step && t < lowest) {
			lowest = t;
		}
	}
	return std::isinf(lowest) ? NEG_INF : lowest;
}

bool SwarmCore::can_climb(int col, float y, float step, float gnd) const {
	float top = wall_top(col, y, step);
	return top != NEG_INF && top - gnd <= max_wall_climb;
}

static Vector2i ring_cell(int r, int step) {
	if (r == 0) return Vector2i(0, 0);
	int side = r * 2;
	int edge = step / side;
	int along = step % side;
	switch (edge) {
		case 0: return Vector2i(-r + along, -r);
		case 1: return Vector2i(r, -r + along);
		case 2: return Vector2i(r - along, r);
		default: return Vector2i(-r, r - along);
	}
}

void SwarmCore::prefill(const Vector3 &p) {
	if (space == nullptr) {
		return;
	}
	int cx = (int)std::floor((p.x - t_ox) / t_cell);
	int cz = (int)std::floor((p.z - t_oz) / t_cell);
	if ((cx - pf_cx) * (cx - pf_cx) + (cz - pf_cz) * (cz - pf_cz) > 100) {
		pf_cx = cx;
		pf_cz = cz;
		pf_ring = 0;
		pf_step = 0;
	}
	int budget = prefill_budget;
	int tries = 0;
	while (budget > 0 && pf_ring <= prefill_radius && tries < 4000) {
		tries++;
		Vector2i c = ring_cell(pf_ring, pf_step);
		pf_step++;
		if (pf_step >= std::max(pf_ring * 8, 1)) {
			pf_step = 0;
			pf_ring++;
		}
		int x = pf_cx + c.x;
		int z = pf_cz + c.y;
		if (x < 0 || z < 0 || x >= t_w || z >= t_d) {
			continue;
		}
		int col = x + z * t_w;
		if (t_count[col] == UNKNOWN) {
			measure(col);
			budget--;
		}
	}
}

// ============================================================ simulation

void SwarmCore::step_spawn(Unit &u, float delta) {
	u.spawn_t += delta;
	if (u.spawn_t < u.emerge_time) {
		float k = u.spawn_t / u.emerge_time;
		k = 1.0f - (1.0f - k) * (1.0f - k);   // ease out
		u.py = u.surface - u.emerge_depth * (1.0f - k);
	} else {
		u.py = u.surface;
	}
	if (u.spawn_t >= u.emerge_time + u.emerge_pause) {
		u.flags &= ~F_SPAWNING;
	}
}

Vector2 SwarmCore::separate(int s, float x, float y, float z, float r, float h, int cell) const {
	float px = 0, pz = 0;
	int overlaps = 0, looked = 0;
	int cx = cell % gw;
	int cz = cell / gw;
	int x0 = std::max(cx - 1, 0);
	int x1 = std::min(cx + 1, gw - 1);
	for (int gz = std::max(cz - 1, 0); gz <= std::min(cz + 1, gd - 1); gz++) {
		uint64_t first = (uint64_t)(x0 + gz * gw) << SLOT_BITS;
		uint64_t last = (uint64_t)(x1 + gz * gw);
		auto it = std::lower_bound(keys.begin(), keys.end(), first);
		for (; it != keys.end(); ++it) {
			uint64_t key = *it;
			if ((key >> SLOT_BITS) > last) break;
			int o = (int)(key & SLOT_MASK);
			if (o == s) continue;
			if (++looked > max_looked) break;
			const Unit &n = units[o];
			if (n.py >= y + h - 0.05f || n.py + n.height <= y + 0.05f) continue;
			float dx = x - n.px;
			float dz = z - n.pz;
			float md = r + n.radius;
			float dsq = dx * dx + dz * dz;
			if (dsq >= md * md) continue;
			if (dsq < 1e-6f) {
				float a = (float)s * 2.39996f;
				px += std::cos(a) * md * 0.5f;
				pz += std::sin(a) * md * 0.5f;
			} else {
				float dist = std::sqrt(dsq);
				float f = (md - dist) * 0.5f / dist;
				px += dx * f;
				pz += dz * f;
			}
			if (++overlaps >= max_neighbors) break;
		}
		if (overlaps >= max_neighbors || looked > max_looked) break;
	}
	float k = (units[s].flags & F_CLIMBER) ? 0.6f : 1.0f;
	return Vector2(px * k, pz * k);
}

PackedInt32Array SwarmCore::step(float delta, const Vector3 &ppos, int64_t now_ms) {
	uint64_t t0 = Time::get_singleton()->get_ticks_usec();
	PackedInt32Array events;
	tick++;
	fills_left = fill_budget;
	prefill(ppos);
	if (alive.empty()) {
		render(now_ms);
		last_step_ms = (Time::get_singleton()->get_ticks_usec() - t0) / 1000.0;
		return events;
	}
	build_grid();

	const float feet = ppos.y - player_half_height;
	const float head = ppos.y + player_half_height;
	const float turn = 1.0f - std::exp(-turn_rate * delta * think_interval);
	const float close2 = close_range * close_range;
	const float knock_drop = knock_decel * delta;
	int prev_cell = -1;
	int rank = 0;

	for (size_t k = 0; k < keys.size(); k++) {
		uint64_t key = keys[k];
		int s = (int)(key & SLOT_MASK);
		int c = (int)(key >> SLOT_BITS);
		if (c == prev_cell) {
			rank++;
		} else {
			prev_cell = c;
			rank = 0;
		}
		Unit &u = units[s];
		if (!(u.flags & F_ALIVE)) continue;
		if (u.flags & F_SPAWNING) {
			step_spawn(u, delta);
			continue;
		}
		float x = u.px, y = u.py, z = u.pz;
		const float h = u.height;
		const int here = dens[c];
		float nx = 0.0f, nz = 0.0f;

		// --- Think (staggered): pick a velocity, collide near the player, attack ---
		if (((s + tick) % think_interval) == 0) {
			const float r = u.radius;
			float dx = ppos.x - x;
			float dz = ppos.z - z;
			float d2 = dx * dx + dz * dz;
			float d = std::sqrt(d2);
			float vx = 0, vz = 0;
			if (d > 0.01f) {
				float wx = dx / d, wz = dz / d;
				vx = wx * u.speed;
				vz = wz * u.speed;
				float fx = u.fx + (wx - u.fx) * turn;
				float fz = u.fz + (wz - u.fz) * turn;
				float fl = std::sqrt(fx * fx + fz * fz);
				if (fl > 1e-4f) {
					u.fx = fx / fl;
					u.fz = fz / fl;
				}
			}
			int cx = c % gw, cz = c / gw;
			if (cx > 0 && cz > 0 && cx < gw - 1 && cz < gd - 1) {
				vx += (float)(dens[c - 1] - dens[c + 1]) * crowd_push;
				vz += (float)(dens[c - gw] - dens[c + gw]) * crowd_push;
			}
			if (here > crowd_capacity) {
				float a = (float)s * 2.39996f;   // golden angle: each enemy its own direction
				float spread = (float)(here - crowd_capacity) * cell_spread;
				vx += std::cos(a) * spread;
				vz += std::sin(a) * spread;
			}
			u.vx = vx;
			u.vz = vz;
			if (d2 < close2) {
				Vector2 push = separate(s, x, y, z, r, h, c);
				nx = push.x;
				nz = push.y;
				if (y < head && y + h > feet) {
					float min_d = r + player_radius;
					if (d2 < min_d * min_d) {
						float dd = std::max(d, 0.001f);
						nx -= dx / dd * (min_d - d);
						nz -= dz / dd * (min_d - d);
					}
					float reach = r + player_radius + u.reach;
					if (d2 <= reach * reach && now_ms >= u.next_attack) {
						u.next_attack = now_ms + (int64_t)(u.atk_cd * 1000.0f);
						events.push_back(1);
						events.push_back(s);
					}
				}
			}
		}

		// --- Move every tick with the last chosen velocity plus knockback ---
		float mvx = u.vx, mvz = u.vz;
		if (u.kx != 0.0f || u.kz != 0.0f) {
			mvx += u.kx;
			mvz += u.kz;
			float kl = std::sqrt(u.kx * u.kx + u.kz * u.kz);
			if (kl <= knock_drop) {
				u.kx = u.kz = 0.0f;
			} else {
				float m = 1.0f - knock_drop / kl;
				u.kx *= m;
				u.kz *= m;
			}
		}
		nx += x + mvx * delta;
		nz += z + mvz * delta;

		// --- Terrain, one axis at a time (slides along walls) ---
		int col = u.col;
		int colx = col_of(nx, z);
		int colz = col_of(nx, nz);
		bool climbing = false;
		const bool climber = (u.flags & F_CLIMBER) != 0;
		if (colx == col && colz == col) {
			x = nx;
			z = nz;
		} else {
			float gnd = u.gnd;
			if (colx == col) {
				x = nx;
			} else {
				float g = ground(colx, y, u.step, h);
				if (std::isnan(g)) {
					x = nx;
				} else if (g == NEG_INF) {
					climbing = climber && can_climb(colx, y, u.step, gnd);
				} else {
					x = nx;
					col = colx;
					gnd = g;
				}
			}
			int colz2 = col_of(x, nz);
			if (colz2 == col) {
				z = nz;
			} else {
				float g2 = ground(colz2, y, u.step, h);
				if (std::isnan(g2)) {
					z = nz;
				} else if (g2 == NEG_INF) {
					climbing = climbing || (climber && can_climb(colz2, y, u.step, gnd));
				} else {
					z = nz;
					col = colz2;
					gnd = g2;
				}
			}
			u.col = col;
			u.gnd = gnd;
		}
		if (((s + tick) % ground_recheck) == 0) {
			float g3 = ground(col, y + 0.05f, u.step, h);
			if (!std::isnan(g3) && g3 != NEG_INF) {
				u.gnd = g3;
			}
		}

		// --- Vertical: gravity, stepping up, climbing walls, piling on the crowd ---
		float floor_y = u.gnd;
		if (climber && rank >= crowd_capacity && here > crowd_capacity) {
			floor_y += std::min((float)(rank / crowd_capacity) * h * pile_layer, u.max_climb);
		}
		if (climbing) {
			y += u.climb * delta;
			u.vy = 0.0f;
		} else if (y < floor_y - 0.001f) {
			y = std::min(y + (climber ? u.climb : step_up_speed) * delta, floor_y);
			u.vy = 0.0f;
		} else if (y > floor_y || u.vy > 0.0f) {
			u.vy -= gravity * delta;
			y = std::max(y + u.vy * delta, floor_y);
			if (y <= floor_y) u.vy = 0.0f;
		}
		u.px = x;
		u.py = y;
		u.pz = z;
		if (y < fall_kill_y) {
			events.push_back(2);
			events.push_back(s);
		}
	}
	render(now_ms);
	last_step_ms = (Time::get_singleton()->get_ticks_usec() - t0) / 1000.0;
	return events;
}

// ============================================================ drawing

void SwarmCore::render(int64_t now_ms) {
	for (Type &t : types) {
		std::swap(t.buf, t.prev);   // last tick's transforms become the "previous" ones
	}
	for (int s : alive) {
		Unit &u = units[s];
		Type &t = types[u.type];
		float *b = t.buf.data() + (size_t)u.inst * 16;
		const float sc = u.scale;
		const float cs = -u.fz * sc;   // rotation about Y facing (fx, fz), model front on -Z
		const float sn = -u.fx * sc;
		b[0] = cs;   b[1] = 0;  b[2] = sn;   b[3] = u.px;
		b[4] = 0;    b[5] = sc; b[6] = 0;    b[7] = u.py;
		b[8] = -sn;  b[9] = 0;  b[10] = cs;  b[11] = u.pz;
		b[12] = now_ms < u.flash_until ? 1.0f : 0.0f;
		b[13] = 0;   b[14] = 0; b[15] = 0;
		if (u.flags & F_NEW) {
			u.flags &= ~F_NEW;
			memcpy(t.prev.data() + (size_t)u.inst * 16, b, 16 * sizeof(float));
		}
	}
}

static PackedFloat32Array to_packed(const std::vector<float> &v, int count) {
	PackedFloat32Array out;
	out.resize(count);
	if (count > 0) {
		memcpy(out.ptrw(), v.data(), (size_t)count * sizeof(float));
	}
	return out;
}

PackedFloat32Array SwarmCore::get_buffer(int type) const {
	ERR_FAIL_INDEX_V(type, (int)types.size(), PackedFloat32Array());
	return to_packed(types[type].buf, types[type].capacity * 16);
}

PackedFloat32Array SwarmCore::get_prev_buffer(int type) const {
	ERR_FAIL_INDEX_V(type, (int)types.size(), PackedFloat32Array());
	return to_packed(types[type].prev, types[type].capacity * 16);
}

int SwarmCore::get_instance_capacity(int type) const {
	return (type >= 0 && type < (int)types.size()) ? types[type].capacity : 0;
}

int SwarmCore::get_visible_count(int type) const {
	return (type >= 0 && type < (int)types.size()) ? types[type].high : 0;
}

// ============================================================ queries

static bool in_skip(const PackedInt32Array &skip, int s) {
	const int32_t *p = skip.ptr();
	for (int64_t i = 0; i < skip.size(); i++) {
		if (p[i] == s) return true;
	}
	return false;
}

Dictionary SwarmCore::raycast(const Vector3 &from, const Vector3 &to, const PackedInt32Array &skip) const {
	Dictionary out;
	if (alive.empty() || keys.empty()) return out;
	const float pad = max_radius;
	int cx0 = cell_x(std::min(from.x, to.x) - pad), cx1 = cell_x(std::max(from.x, to.x) + pad);
	int cz0 = cell_z(std::min(from.z, to.z) - pad), cz1 = cell_z(std::max(from.z, to.z) + pad);
	const float dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z;
	const float a = dx * dx + dz * dz;
	float best_t = std::numeric_limits<float>::infinity();
	int best_s = -1;
	for (int cz = cz0; cz <= cz1; cz++) {
		uint64_t first = (uint64_t)(cx0 + cz * gw) << SLOT_BITS;
		uint64_t last = (uint64_t)(cx1 + cz * gw);
		for (auto it = std::lower_bound(keys.begin(), keys.end(), first); it != keys.end(); ++it) {
			if ((*it >> SLOT_BITS) > last) break;
			int s = (int)(*it & SLOT_MASK);
			const Unit &u = units[s];
			if ((u.flags & (F_ALIVE | F_SPAWNING)) != F_ALIVE) continue;
			if (skip.size() > 0 && in_skip(skip, s)) continue;
			float ox = from.x - u.px, oz = from.z - u.pz;
			float cc = ox * ox + oz * oz - u.radius * u.radius;
			float t_in = 0.0f, t_out = 1.0f;
			if (a > 1e-6f) {
				float b = 2.0f * (dx * ox + dz * oz);
				float disc = b * b - 4.0f * a * cc;
				if (disc < 0.0f) continue;
				float sq = std::sqrt(disc);
				t_in = (-b - sq) / (2.0f * a);
				t_out = (-b + sq) / (2.0f * a);
			} else if (cc > 0.0f) {
				continue;
			}
			float lo = u.py, hi = u.py + u.height;
			float ty0 = 0.0f, ty1 = 1.0f;
			if (std::abs(dy) > 1e-6f) {
				float ta = (lo - from.y) / dy, tb = (hi - from.y) / dy;
				ty0 = std::min(ta, tb);
				ty1 = std::max(ta, tb);
			} else if (from.y < lo || from.y > hi) {
				continue;
			}
			float enter = std::max(std::max(t_in, ty0), 0.0f);
			float leave = std::min(std::min(t_out, ty1), 1.0f);
			if (enter <= leave && enter < best_t) {
				best_t = enter;
				best_s = s;
			}
		}
	}
	if (best_s < 0) return out;
	Vector3 p = from + (to - from) * best_t;
	const Unit &u = units[best_s];
	Vector3 n(p.x - u.px, 0.0f, p.z - u.pz);
	n = n.length_squared() > 1e-4f ? n.normalized() : -(to - from).normalized();
	out["slot"] = best_s;
	out["position"] = p;
	out["normal"] = n;
	out["fraction"] = best_t;
	return out;
}

PackedInt32Array SwarmCore::query_sphere(const Vector3 &center, float radius, int max_results) const {
	PackedInt32Array out;
	if (alive.empty() || keys.empty()) return out;
	const float reach = radius + max_radius;
	int cx0 = cell_x(center.x - reach), cx1 = cell_x(center.x + reach);
	int cz0 = cell_z(center.z - reach), cz1 = cell_z(center.z + reach);
	for (int cz = cz0; cz <= cz1; cz++) {
		uint64_t first = (uint64_t)(cx0 + cz * gw) << SLOT_BITS;
		uint64_t last = (uint64_t)(cx1 + cz * gw);
		for (auto it = std::lower_bound(keys.begin(), keys.end(), first); it != keys.end(); ++it) {
			if ((*it >> SLOT_BITS) > last) break;
			int s = (int)(*it & SLOT_MASK);
			const Unit &u = units[s];
			if ((u.flags & (F_ALIVE | F_SPAWNING)) != F_ALIVE) continue;
			float dx = center.x - u.px, dz = center.z - u.pz;
			float yy = std::clamp(center.y, u.py, u.py + u.height);
			float dy = center.y - yy;
			float r = radius + u.radius;
			if (dx * dx + dz * dz + dy * dy <= r * r) {
				out.push_back(s);
				if (out.size() >= max_results) return out;
			}
		}
	}
	return out;
}

PackedFloat32Array SwarmCore::find_nearest(const Vector3 &from, float max_range, const PackedInt32Array &skip) const {
	PackedFloat32Array out;
	if (alive.empty() || keys.empty()) return out;
	int best_s = -1;
	float best_d = max_range * max_range;
	int ccx = cell_x(from.x), ccz = cell_z(from.z);
	int max_ring = (int)std::ceil(max_range / crowd_cell) + 1;
	for (int ring = 0; ring <= max_ring; ring++) {
		float ring_min = std::max((float)(ring - 1) * crowd_cell, 0.0f);
		if (best_s >= 0 && ring_min * ring_min > best_d) break;
		for (int gz = ccz - ring; gz <= ccz + ring; gz++) {
			if (gz < 0 || gz >= gd) continue;
			for (int gx = ccx - ring; gx <= ccx + ring; gx++) {
				if (gx < 0 || gx >= gw) continue;
				if (std::abs(gx - ccx) != ring && std::abs(gz - ccz) != ring) continue;
				uint64_t cell = (uint64_t)(gx + gz * gw);
				for (auto it = std::lower_bound(keys.begin(), keys.end(), cell << SLOT_BITS); it != keys.end(); ++it) {
					if ((*it >> SLOT_BITS) != cell) break;
					int s = (int)(*it & SLOT_MASK);
					const Unit &u = units[s];
					if ((u.flags & (F_ALIVE | F_SPAWNING)) != F_ALIVE) continue;
					if (skip.size() > 0 && in_skip(skip, s)) continue;
					float dx = from.x - u.px, dy = from.y - (u.py + u.height * 0.5f), dz = from.z - u.pz;
					float d = dx * dx + dy * dy + dz * dz;
					if (d < best_d) {
						best_d = d;
						best_s = s;
					}
				}
			}
		}
	}
	if (best_s >= 0) {
		out.push_back((float)best_s);
		out.push_back(best_d);
	}
	return out;
}

PackedFloat32Array SwarmCore::lock_candidates(const Vector3 &origin, const Vector3 &fwd, float max_angle, float max_range, int limit) const {
	// Keeps the `limit` most centered (largest cosine) enemies inside the cone.
	std::vector<std::pair<float, int>> best;
	best.reserve((size_t)limit + 1);
	const float cos_max = std::cos(max_angle);
	const float r2 = max_range * max_range;
	float worst = cos_max;
	for (int s : alive) {
		const Unit &u = units[s];
		if (u.flags & F_SPAWNING) continue;
		float dx = u.px - origin.x, dz = u.pz - origin.z;
		float hh = dx * dx + dz * dz;
		if (hh > r2) continue;
		float dy = u.py + u.aim - origin.y;
		float d2 = hh + dy * dy;
		if (d2 < 1e-4f) continue;
		float dot = dx * fwd.x + dy * fwd.y + dz * fwd.z;
		if (dot <= 0.0f) continue;
		float c = dot / std::sqrt(d2);
		if (c < worst) continue;
		auto pos = std::find_if(best.begin(), best.end(), [c](const std::pair<float, int> &e) { return e.first < c; });
		best.insert(pos, {c, s});
		if ((int)best.size() > limit) {
			best.pop_back();
			worst = best.back().first;
		}
	}
	PackedFloat32Array out;
	for (auto &e : best) {
		out.push_back(std::acos(std::clamp(e.first, -1.0f, 1.0f)));
		out.push_back((float)e.second);
	}
	return out;
}

// ============================================================ bindings

void SwarmCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "bounds"), &SwarmCore::setup);
	ClassDB::bind_method(D_METHOD("set_tuning", "tuning"), &SwarmCore::set_tuning);
	ClassDB::bind_method(D_METHOD("set_world", "space_state", "exclude"), &SwarmCore::set_world);
	ClassDB::bind_method(D_METHOD("add_type"), &SwarmCore::add_type);
	ClassDB::bind_method(D_METHOD("add_unit", "type", "pos", "stats", "flags", "gold"), &SwarmCore::add_unit);
	ClassDB::bind_method(D_METHOD("remove_unit", "slot"), &SwarmCore::remove_unit);
	ClassDB::bind_method(D_METHOD("unit_count"), &SwarmCore::unit_count);
	ClassDB::bind_method(D_METHOD("get_alive"), &SwarmCore::get_alive);
	ClassDB::bind_method(D_METHOD("is_alive", "slot"), &SwarmCore::is_alive);
	ClassDB::bind_method(D_METHOD("is_spawning", "slot"), &SwarmCore::is_spawning);
	ClassDB::bind_method(D_METHOD("is_elite", "slot"), &SwarmCore::is_elite);
	ClassDB::bind_method(D_METHOD("get_pos", "slot"), &SwarmCore::get_pos);
	ClassDB::bind_method(D_METHOD("get_aim_position", "slot"), &SwarmCore::get_aim_position);
	ClassDB::bind_method(D_METHOD("get_height", "slot"), &SwarmCore::get_height);
	ClassDB::bind_method(D_METHOD("get_kb_resist", "slot"), &SwarmCore::get_kb_resist);
	ClassDB::bind_method(D_METHOD("get_health", "slot"), &SwarmCore::get_health);
	ClassDB::bind_method(D_METHOD("get_ground", "slot"), &SwarmCore::get_ground);
	ClassDB::bind_method(D_METHOD("get_gold", "slot"), &SwarmCore::get_gold);
	ClassDB::bind_method(D_METHOD("get_type", "slot"), &SwarmCore::get_type);
	ClassDB::bind_method(D_METHOD("get_attack", "slot"), &SwarmCore::get_attack);
	ClassDB::bind_method(D_METHOD("damage", "slot", "amount", "now_ms"), &SwarmCore::damage);
	ClassDB::bind_method(D_METHOD("knock_back", "slot", "push", "up"), &SwarmCore::knock_back);
	ClassDB::bind_method(D_METHOD("set_obstacles", "xzr"), &SwarmCore::set_obstacles);
	ClassDB::bind_method(D_METHOD("step", "delta", "player_pos", "now_ms"), &SwarmCore::step);
	ClassDB::bind_method(D_METHOD("get_buffer", "type"), &SwarmCore::get_buffer);
	ClassDB::bind_method(D_METHOD("get_prev_buffer", "type"), &SwarmCore::get_prev_buffer);
	ClassDB::bind_method(D_METHOD("get_instance_capacity", "type"), &SwarmCore::get_instance_capacity);
	ClassDB::bind_method(D_METHOD("get_visible_count", "type"), &SwarmCore::get_visible_count);
	ClassDB::bind_method(D_METHOD("raycast", "from", "to", "skip"), &SwarmCore::raycast);
	ClassDB::bind_method(D_METHOD("query_sphere", "center", "radius", "max_results"), &SwarmCore::query_sphere);
	ClassDB::bind_method(D_METHOD("find_nearest", "from", "max_range", "skip"), &SwarmCore::find_nearest);
	ClassDB::bind_method(D_METHOD("lock_candidates", "origin", "forward", "max_angle", "max_range", "limit"), &SwarmCore::lock_candidates);
	ClassDB::bind_method(D_METHOD("get_last_step_ms"), &SwarmCore::get_last_step_ms);
	ClassDB::bind_method(D_METHOD("get_terrain_size"), &SwarmCore::get_terrain_size);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &SwarmCore::get_grid_size);
}
