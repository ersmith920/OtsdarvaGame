#include "gold_core.h"

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <unordered_map>

using namespace godot;

static constexpr float TAU_F = 6.28318530718f;
static constexpr int FLOATS = 16;   // 12 transform + 4 custom per instance

GoldCore::GoldCore() {
	query.instantiate();
	query->set_collide_with_areas(false);
	rng ^= (uint32_t)Time::get_singleton()->get_ticks_usec();
}

float GoldCore::randf() {
	// xorshift32
	rng ^= rng << 13;
	rng ^= rng >> 17;
	rng ^= rng << 5;
	return (rng >> 8) * (1.0f / 16777216.0f);
}

// ============================================================ setup

void GoldCore::set_settings(const Dictionary &d) {
#define SET_F(name) if (d.has(#name)) name = (float)d[#name];
#define SET_I(name) if (d.has(#name)) name = (int)d[#name];
	SET_F(large_value)
	SET_F(huge_value)
	SET_F(burst_up_min)
	SET_F(burst_up_max)
	SET_F(burst_out_min)
	SET_F(burst_out_max)
	SET_F(gravity)
	SET_F(min_floor_normal_y)
	SET_F(restitution)
	SET_F(friction)
	SET_F(min_bounce_speed)
	SET_I(max_bounces)
	if (d.has("swirl")) swirl = (bool)d["swirl"];
	SET_F(swirl_time)
	SET_F(swirl_turns)
	SET_F(swirl_direction)
	SET_F(swirl_tightening)
	SET_F(swirl_spin_up)
	SET_F(swirl_min_time_fraction)
	SET_F(collect_distance)
	SET_F(pull_start_speed)
	SET_F(pull_max_speed)
	SET_F(pull_acceleration)
	SET_I(merge_threshold)
	SET_F(merge_cell_size)
	SET_I(merge_interval_ms)
	SET_F(fall_kill_y)
#undef SET_F
#undef SET_I
	merge_cell_size = std::max(merge_cell_size, 0.01f);
}

void GoldCore::set_looks(const PackedFloat32Array &small, const PackedFloat32Array &large, const PackedFloat32Array &huge) {
	looks.clear();
	const PackedFloat32Array *lists[3] = { &small, &large, &huge };
	for (int t = 0; t < 3; t++) {
		tier_start[t] = (int)looks.size();
		const PackedFloat32Array &l = *lists[t];
		for (int i = 0; i + 3 < l.size(); i += 4) {
			Look k;
			k.type = (int)l[i];
			k.sx = l[i + 1];
			k.sy = l[i + 2];
			k.fy = l[i + 3];
			looks.push_back(k);
		}
		tier_count[t] = (int)looks.size() - tier_start[t];
	}
}

int GoldCore::add_type() {
	types.emplace_back();
	return (int)types.size() - 1;
}

void GoldCore::set_world(Object *space_state, const TypedArray<RID> &exclude) {
	space = Object::cast_to<PhysicsDirectSpaceState3D>(space_state);
	base_exclude = exclude;
	query->set_exclude(base_exclude);
}

// ============================================================ instances

int GoldCore::take_instance(int type) {
	Type &t = types[type];
	if (!t.free_inst.empty()) {
		int i = t.free_inst.back();
		t.free_inst.pop_back();
		return i;
	}
	if (t.high >= t.capacity) {
		t.capacity = std::max(t.capacity * 2, 256);
		t.buf.resize((size_t)t.capacity * FLOATS, 0.0f);
		t.prev.resize((size_t)t.capacity * FLOATS, 0.0f);
	}
	return t.high++;
}

void GoldCore::release_instance(int type, int inst) {
	if (type < 0 || inst < 0) {
		return;
	}
	Type &t = types[type];
	float *b = t.buf.data() + (size_t)inst * FLOATS;
	float *p = t.prev.data() + (size_t)inst * FLOATS;
	std::fill(b, b + FLOATS, 0.0f);   // zero scale: draws nothing
	std::fill(p, p + FLOATS, 0.0f);
	t.changed = true;
	t.free_inst.push_back(inst);
}

// Same picks as GoldPickup._refresh_look: size by value, art by the coin's variant.
int GoldCore::look_for(double value, uint32_t variant) const {
	int tier = value >= huge_value ? 2 : (value >= large_value ? 1 : 0);
	if (tier_count[tier] == 0) {
		tier = 0;
	}
	if (tier_count[tier] == 0) {
		return -1;
	}
	return tier_start[tier] + (int)(variant % (uint32_t)tier_count[tier]);
}

// Picks the coin's look for its value; moves it to another MultiMesh if the art changed.
void GoldCore::set_look(Coin &c, bool snap) {
	int lk = look_for(c.value, c.variant);
	if (lk == c.look && c.inst >= 0) {
		return;
	}
	c.look = lk;
	int type = lk >= 0 ? looks[lk].type : -1;
	if (type != c.type || c.inst < 0) {
		release_instance(c.type, c.inst);
		c.type = type;
		c.inst = type >= 0 ? take_instance(type) : -1;
		snap = true;
	}
	write(c, -1.0f, c.state == ATTRACTED && swirl ? 0.0f : 1.0f, snap);
}

// lift < 0 = the look's normal hover height. bob: 1 = bobbing, 0 = still (mid-swirl).
// snap: no interpolation from the old spot (new coin, or it changed MultiMesh).
void GoldCore::write(const Coin &c, float lift, float bob, bool snap) {
	if (c.type < 0 || c.inst < 0) {
		return;
	}
	const Look &k = looks[c.look];
	Type &t = types[c.type];
	float *b = t.buf.data() + (size_t)c.inst * FLOATS;
	float y = c.py + (lift < 0.0f ? k.fy : lift);
	// Basis (scale only; the shader billboards it) + origin, row-major 3x4.
	b[0] = k.sx; b[1] = 0;    b[2] = 0;  b[3] = c.px;
	b[4] = 0;    b[5] = k.sy; b[6] = 0;  b[7] = y;
	b[8] = 0;    b[9] = 0;    b[10] = 1; b[11] = c.pz;
	b[12] = c.phase;
	b[13] = bob;
	b[14] = 0;
	b[15] = 1;
	if (snap) {
		memcpy(t.prev.data() + (size_t)c.inst * FLOATS, b, FLOATS * sizeof(float));
	}
	t.changed = true;
}

// ============================================================ coins

void GoldCore::drop(const Vector3 &origin, double value, int count) {
	if (count <= 0 || value <= 0.0) {
		return;
	}
	double each = value / (double)count;
	for (int n = 0; n < count; n++) {
		int i;
		if (!free_slots.empty()) {
			i = free_slots.back();
			free_slots.pop_back();
		} else {
			i = (int)coins.size();
			coins.emplace_back();
		}
		Coin &c = coins[i];
		c = Coin();
		c.alive = true;
		c.px = origin.x;
		c.py = origin.y;
		c.pz = origin.z;
		c.value = each;
		c.variant = rng = rng * 1664525u + 1013904223u;
		c.phase = randf() * TAU_F;
		// Burst: random up speed, random outward speed in a random direction.
		float up = rand_range(burst_up_min, burst_up_max);
		float out = rand_range(burst_out_min, burst_out_max);
		float a = randf() * TAU_F;
		c.vx = std::cos(a) * out;
		c.vz = std::sin(a) * out;
		c.vy = up;
		c.state = FLYING;
		set_look(c, true);
		alive_count++;
	}
}

void GoldCore::remove(int i) {
	Coin &c = coins[i];
	if (!c.alive) {
		return;
	}
	release_instance(c.type, c.inst);
	c.alive = false;
	c.type = c.inst = c.look = -1;
	free_slots.push_back(i);
	alive_count--;
}

void GoldCore::clear() {
	for (int i = 0; i < (int)coins.size(); i++) {
		if (coins[i].alive) {
			remove(i);
		}
	}
	coins.clear();
	free_slots.clear();
	alive_count = 0;
}

// Ray against the world, ignoring characters (player and enemies), like FloorPickup._raycast.
Dictionary GoldCore::raycast(const Vector3 &from, const Vector3 &to) {
	if (space == nullptr) {
		return Dictionary();
	}
	query->set_from(from);
	query->set_to(to);
	// The exclude list is only rebuilt when a ray hits a character (rare).
	TypedArray<RID> exclude;
	for (int n = 0; n < 8; n++) {
		Dictionary hit = space->intersect_ray(query);
		if (hit.is_empty() || Object::cast_to<CharacterBody3D>((Object *)hit["collider"]) == nullptr) {
			if (n > 0) {
				query->set_exclude(base_exclude);
			}
			return hit;
		}
		if (n == 0) {
			exclude = base_exclude.duplicate();
		}
		exclude.push_back(hit["rid"]);
		query->set_exclude(exclude);
	}
	query->set_exclude(base_exclude);
	return Dictionary();
}

PackedFloat32Array GoldCore::step(float delta, const Vector3 &player, float pickup_range, bool has_player, int64_t now_ms) {
	uint64_t t0 = Time::get_singleton()->get_ticks_usec();
	PackedFloat32Array events;
	events.push_back(0.0f);   // gold collected (exact value: get_last_gold)
	events.push_back(0.0f);   // coins collected
	double gold = 0.0;
	int collected = 0;

	for (Type &t : types) {
		if (t.changed_last) {
			memcpy(t.prev.data(), t.buf.data(), (size_t)t.high * FLOATS * sizeof(float));
		}
		t.changed = false;
	}

	pickup_range = std::max(pickup_range, 0.0f);
	float range_sq = pickup_range * pickup_range;
	bool want_merge = false;
	for (int i = 0; i < (int)coins.size(); i++) {
		Coin &c = coins[i];
		if (!c.alive) {
			continue;
		}

		if (c.state == FLYING) {
			// FloorPickup's launch arc plus GoldPickup's bounces.
			c.vy -= gravity * delta;
			Vector3 from(c.px, c.py, c.pz);
			Vector3 to = from + Vector3(c.vx, c.vy, c.vz) * delta;
			Dictionary hit = raycast(from, to);
			if (hit.is_empty()) {
				c.px = to.x;
				c.py = to.y;
				c.pz = to.z;
				if (c.py < fall_kill_y) {
					remove(i);
					continue;
				}
			} else {
				Vector3 hp = hit["position"];
				Vector3 hn = hit["normal"];
				if (hn.y >= min_floor_normal_y) {
					c.px = hp.x;
					c.py = hp.y;
					c.pz = hp.z;
					float impact = std::fabs(c.vy);
					events.push_back(c.px);
					events.push_back(c.py);
					events.push_back(c.pz);
					events.push_back(impact);
					float rebound = impact * restitution;
					if (rebound < min_bounce_speed || c.bounces >= max_bounces) {
						c.vx = c.vy = c.vz = 0.0f;
						c.state = LANDED;
					} else {
						c.bounces++;
						c.vx *= friction;
						c.vz *= friction;
						c.vy = rebound;
						c.py += 0.02f;   // just above the floor so the next ray doesn't re-hit it
					}
				} else {
					// Wall or ceiling: lose sideways motion and drop down along it.
					c.px = hp.x + hn.x * 0.05f;
					c.py = hp.y + hn.y * 0.05f;
					c.pz = hp.z + hn.z * 0.05f;
					c.vx = c.vz = 0.0f;
					if (hn.y < -min_floor_normal_y) {
						c.vy = std::min(c.vy, 0.0f);
					}
				}
			}
			write(c, -1.0f, 1.0f, false);
			if (c.state != LANDED) {
				continue;
			}
		}

		if (!has_player) {
			continue;
		}

		if (c.state == LANDED) {
			float dx = player.x - c.px, dy = player.y - c.py, dz = player.z - c.pz;
			if (dx * dx + dy * dy + dz * dz > range_sq) {
				want_merge = true;
				continue;
			}
			// Latch on: freeze where the coin sits relative to the player, in polar form.
			c.state = ATTRACTED;
			c.pull_speed = pull_start_speed;
			float ox = -dx, oy = -dy, oz = -dz;
			c.r0 = std::sqrt(ox * ox + oz * oz);
			c.a0 = std::atan2(oz, ox);
			c.h0 = oy;
			c.swirl_t = 0.0f;
			float frac = std::clamp(c.r0 / std::max(pickup_range, 0.01f), swirl_min_time_fraction, 1.0f);
			c.swirl_dur = std::max(swirl_time * frac, 0.01f);
		}

		// ATTRACTED
		if (swirl) {
			c.swirl_t = std::min(c.swirl_t + delta / c.swirl_dur, 1.0f);
			if (c.swirl_t >= 1.0f) {
				gold += c.value;
				collected++;
				remove(i);
				continue;
			}
			float shrink = 1.0f - std::pow(c.swirl_t, swirl_tightening);
			float ang = c.a0 + swirl_direction * swirl_turns * TAU_F * std::pow(c.swirl_t, swirl_spin_up);
			float r = c.r0 * shrink;
			c.px = player.x + std::cos(ang) * r;
			c.py = player.y + c.h0 * shrink;
			c.pz = player.z + std::sin(ang) * r;
			// No bobbing mid-swirl; the hover offset shrinks away as the coin closes in.
			write(c, looks[c.look].fy * (1.0f - c.swirl_t), 0.0f, false);
		} else {
			float tx = player.x - c.px, ty = player.y - c.py, tz = player.z - c.pz;
			float dist_sq = tx * tx + ty * ty + tz * tz;
			c.pull_speed = std::min(c.pull_speed + pull_acceleration * delta, pull_max_speed);
			float stp = c.pull_speed * delta;
			if (dist_sq <= std::max(stp * stp, collect_distance * collect_distance)) {
				gold += c.value;
				collected++;
				remove(i);
				continue;
			}
			float inv = stp / std::sqrt(dist_sq);
			c.px += tx * inv;
			c.py += ty * inv;
			c.pz += tz * inv;
			write(c, -1.0f, 1.0f, false);
		}
	}

	if (want_merge && now_ms - last_merge_ms >= merge_interval_ms) {
		last_merge_ms = now_ms;
		if (alive_count > merge_threshold) {
			merge_pass();
		}
	}

	for (Type &t : types) {
		t.changed_last = t.changed;
	}
	last_gold = gold;
	events.set(0, (float)gold);
	events.set(1, (float)collected);
	last_step_ms = (Time::get_singleton()->get_ticks_usec() - t0) / 1000.0;
	return events;
}

// Fuses landed coins that share a grid cell, like GoldPickup._try_merge.
void GoldCore::merge_pass() {
	std::unordered_map<int64_t, int> keepers;
	keepers.reserve(1024);
	for (int i = 0; i < (int)coins.size(); i++) {
		Coin &c = coins[i];
		if (!c.alive || c.state != LANDED) {
			continue;
		}
		int64_t cx = (int64_t)std::floor(c.px / merge_cell_size);
		int64_t cy = (int64_t)std::floor(c.py / merge_cell_size);
		int64_t cz = (int64_t)std::floor(c.pz / merge_cell_size);
		int64_t key = ((cx & 0x1FFFFF) << 42) | ((cy & 0x1FFFFF) << 21) | (cz & 0x1FFFFF);
		auto it = keepers.find(key);
		if (it == keepers.end()) {
			keepers.emplace(key, i);
		} else {
			Coin &keeper = coins[it->second];
			keeper.value += c.value;
			set_look(keeper, false);   // grows into a large / huge coin
			remove(i);
		}
	}
}

// ============================================================ buffers

static PackedFloat32Array to_packed(const std::vector<float> &v, int count) {
	PackedFloat32Array out;
	out.resize(count);
	if (count > 0) {
		memcpy(out.ptrw(), v.data(), (size_t)count * sizeof(float));
	}
	return out;
}

PackedFloat32Array GoldCore::get_buffer(int type) const {
	ERR_FAIL_INDEX_V(type, (int)types.size(), PackedFloat32Array());
	return to_packed(types[type].buf, types[type].capacity * FLOATS);
}

PackedFloat32Array GoldCore::get_prev_buffer(int type) const {
	ERR_FAIL_INDEX_V(type, (int)types.size(), PackedFloat32Array());
	return to_packed(types[type].prev, types[type].capacity * FLOATS);
}

int GoldCore::get_instance_capacity(int type) const {
	return (type >= 0 && type < (int)types.size()) ? types[type].capacity : 0;
}

int GoldCore::get_visible_count(int type) const {
	return (type >= 0 && type < (int)types.size()) ? types[type].high : 0;
}

bool GoldCore::needs_upload(int type) const {
	if (type < 0 || type >= (int)types.size()) {
		return false;
	}
	return types[type].changed || types[type].changed_last;
}

void GoldCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_settings", "settings"), &GoldCore::set_settings);
	ClassDB::bind_method(D_METHOD("set_looks", "small", "large", "huge"), &GoldCore::set_looks);
	ClassDB::bind_method(D_METHOD("add_type"), &GoldCore::add_type);
	ClassDB::bind_method(D_METHOD("set_world", "space_state", "exclude"), &GoldCore::set_world);
	ClassDB::bind_method(D_METHOD("drop", "origin", "value", "count"), &GoldCore::drop);
	ClassDB::bind_method(D_METHOD("step", "delta", "player_pos", "pickup_range", "has_player", "now_ms"), &GoldCore::step);
	ClassDB::bind_method(D_METHOD("clear"), &GoldCore::clear);
	ClassDB::bind_method(D_METHOD("count"), &GoldCore::count);
	ClassDB::bind_method(D_METHOD("get_last_gold"), &GoldCore::get_last_gold);
	ClassDB::bind_method(D_METHOD("get_last_step_ms"), &GoldCore::get_last_step_ms);
	ClassDB::bind_method(D_METHOD("get_buffer", "type"), &GoldCore::get_buffer);
	ClassDB::bind_method(D_METHOD("get_prev_buffer", "type"), &GoldCore::get_prev_buffer);
	ClassDB::bind_method(D_METHOD("get_instance_capacity", "type"), &GoldCore::get_instance_capacity);
	ClassDB::bind_method(D_METHOD("get_visible_count", "type"), &GoldCore::get_visible_count);
	ClassDB::bind_method(D_METHOD("needs_upload", "type"), &GoldCore::needs_upload);
}
