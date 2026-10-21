// SwarmCore: the heavy loops of the swarm (movement, crowd grid, terrain cache, drawing
// buffers, hit queries) in C++. The Swarm autoload (swarm.gd) owns everything else:
// spawning rules, unit handles, sounds, gold, MultiMesh nodes. swarm_core_gd.gd is a
// GDScript copy of this class with the same functions, used if this library isn't loaded.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class SwarmCore : public RefCounted {
	GDCLASS(SwarmCore, RefCounted)

public:
	// Unit flags (same values as swarm.gd).
	enum {
		F_ALIVE = 1,
		F_SPAWNING = 2,
		F_CLIMBER = 4,
		F_ELITE = 8,
		F_NEW = 16,
	};

	// Order of the stats array passed to add_unit().
	enum Stat {
		S_HEALTH, S_SPEED, S_RADIUS, S_HEIGHT, S_STEP, S_CLIMB_SPEED, S_MAX_CLIMB,
		S_KB_RESIST, S_ATTACK, S_ATTACK_CD, S_KB_FORCE, S_KB_UP, S_REACH, S_SCALE,
		S_AIM, S_EMERGE_TIME, S_EMERGE_PAUSE, S_EMERGE_DEPTH, S_FLASH_TIME,
		S_COUNT
	};

private:
	struct Unit {
		float px = 0, py = 0, pz = 0;
		float fx = 0, fz = 1;      // facing (unit, horizontal)
		float vx = 0, vz = 0;      // walking velocity from the last think
		float kx = 0, kz = 0;      // knockback velocity
		float vy = 0;
		float gnd = 0;             // ground height of the current terrain column
		float hp = 1;
		float speed = 5, radius = 0.9f, height = 1.6f, step = 1, climb = 6, max_climb = 6;
		float kb_resist = 0, atk = 10, atk_cd = 1, kb_force = 8, kb_up = 3, reach = 0.3f;
		float scale = 1, aim = 0.5f;
		float spawn_t = 0, surface = 0, emerge_time = 0, emerge_pause = 0, emerge_depth = 0, flash_time = 0;
		int64_t flash_until = 0, next_attack = 0;
		int32_t type = 0, inst = 0, col = -1, flags = 0, gold = 0;
	};

	struct Type {
		std::vector<float> buf, prev;
		std::vector<int32_t> free_inst;
		int32_t high = 0;
		int32_t capacity = 0;
	};

	// ---- Tuning (set_tuning) ----
	float crowd_cell = 2.0f;
	int crowd_capacity = 2;
	float crowd_push = 1.1f;
	float cell_spread = 0.8f;
	float close_range = 14.0f;
	int max_neighbors = 6;
	int max_looked = 14;
	float pile_layer = 0.75f;
	int pile_capacity = 1;
	float climber_push_scale = 0.3f;
	float gravity = 24.0f;
	float step_up_speed = 10.0f;
	float fall_kill_y = -100.0f;
	float knock_decel = 40.0f;
	float max_knock_speed = 40.0f;
	float player_radius = 0.5f;
	float player_half_height = 1.0f;
	float max_wall_climb = 30.0f;
	float turn_rate = 10.0f;
	int think_interval = 2;
	int ground_recheck = 8;
	int fill_budget = 150;
	int prefill_budget = 60;
	int prefill_radius = 70;

	// ---- Units ----
	std::vector<Unit> units;
	std::vector<int32_t> alive;      // dense list of live slots
	std::vector<int32_t> alive_at;   // slot -> index in alive
	std::vector<int32_t> free_slots;
	std::vector<Type> types;
	float max_radius = 1.0f;

	// ---- Crowd grid ----
	float gx0 = 0, gz0 = 0;
	int gw = 1, gd = 1;
	std::vector<int32_t> dens;
	std::vector<uint64_t> keys;      // (cell << 20) | slot, sorted each tick
	std::vector<float> obstacles;    // x, z, radius triples (node enemies)

	// ---- Terrain cache (see swarm_terrain.gd for the idea) ----
	static constexpr int MAX_LAYERS = 3;
	static constexpr uint8_t UNKNOWN = 255;
	float t_cell = 1.0f;
	float t_ox = 0, t_oz = 0, t_top = 100, t_bottom = -100;
	int t_w = 1, t_d = 1;
	std::vector<uint8_t> t_count;
	std::vector<float> t_tops, t_clear;
	int fills_left = 0;
	PhysicsDirectSpaceState3D *space = nullptr;
	Ref<PhysicsRayQueryParameters3D> q_down, q_up;
	int pf_cx = -99999, pf_cz = -99999, pf_ring = 0, pf_step = 0;

	int64_t tick = 0;
	double last_step_ms = 0.0;

	// helpers
	int cell_of(float x, float z) const;
	int cell_x(float x) const;
	int cell_z(float z) const;
	int col_of(float x, float z) const;
	float ground(int col, float y, float step, float height);   // NAN = unknown, -INF = blocked
	float wall_top(int col, float y, float step) const;
	void measure(int col);
	void prefill(const Vector3 &p);
	bool can_climb(int col, float y, float step, float gnd) const;
	void build_grid();
	Vector2 separate(int s, float x, float y, float z, float r, float h, int cell) const;
	void step_spawn(Unit &u, float delta);
	void render(int64_t now_ms);
	int take_instance(int type);
	void release_instance(int type, int inst);
	bool alive_ok(int s) const { return s >= 0 && s < (int)units.size() && (units[s].flags & F_ALIVE); }

protected:
	static void _bind_methods();

public:
	SwarmCore();

	void setup(const AABB &bounds);
	void set_tuning(const Dictionary &d);
	void set_world(Object *space_state, const TypedArray<RID> &exclude);
	int add_type();
	int add_unit(int type, const Vector3 &pos, const PackedFloat32Array &stats, int flags, int gold);
	void remove_unit(int slot);
	int unit_count() const { return (int)alive.size(); }
	PackedInt32Array get_alive() const;

	bool is_alive(int s) const { return alive_ok(s); }
	bool is_spawning(int s) const { return alive_ok(s) && (units[s].flags & F_SPAWNING); }
	bool is_elite(int s) const { return alive_ok(s) && (units[s].flags & F_ELITE); }
	Vector3 get_pos(int s) const;
	Vector3 get_aim_position(int s) const;
	float get_height(int s) const;
	float get_kb_resist(int s) const;
	float get_health(int s) const;
	float get_ground(int s) const;
	int get_gold(int s) const;
	int get_type(int s) const;
	PackedFloat32Array get_attack(int s) const;   // damage, knockback force, knockback up

	int damage(int s, float amount, int64_t now_ms);   // -1 ignored, 0 hurt, 1 killed
	void knock_back(int s, const Vector3 &push, float up);
	void set_obstacles(const PackedFloat32Array &xzr);

	PackedInt32Array step(float delta, const Vector3 &player_pos, int64_t now_ms);

	PackedFloat32Array get_buffer(int type) const;
	PackedFloat32Array get_prev_buffer(int type) const;
	int get_instance_capacity(int type) const;
	int get_visible_count(int type) const;

	Dictionary raycast(const Vector3 &from, const Vector3 &to, const PackedInt32Array &skip) const;
	PackedInt32Array query_sphere(const Vector3 &center, float radius, int max_results) const;
	PackedFloat32Array find_nearest(const Vector3 &from, float max_range, const PackedInt32Array &skip) const;
	PackedFloat32Array lock_candidates(const Vector3 &origin, const Vector3 &forward, float max_angle, float max_range, int limit) const;

	double get_last_step_ms() const { return last_step_ms; }
	Vector2i get_terrain_size() const { return Vector2i(t_w, t_d); }
	Vector2i get_grid_size() const { return Vector2i(gw, gd); }
};

} // namespace godot
