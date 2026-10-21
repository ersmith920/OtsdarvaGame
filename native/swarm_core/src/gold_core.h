// GoldCore: every gold coin on the map as plain arrays instead of nodes. Flight (arc,
// bounces), hover, swirl collection and merging all run here; the Coins autoload (coins.gd)
// owns the rest: settings, sounds, the player's gold and the MultiMesh nodes that draw them.
// The behavior matches the GoldPickup node coin (gold_pickup.gd / floor_pickup.gd), which
// is still used when this library isn't loaded.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class GoldCore : public RefCounted {
	GDCLASS(GoldCore, RefCounted)

public:
	enum State { FLYING = 0, LANDED = 1, ATTRACTED = 2 };

private:
	struct Coin {
		float px = 0, py = 0, pz = 0;   // the coin's spot (its hover height is added on top)
		float vx = 0, vy = 0, vz = 0;
		double value = 1;
		float phase = 0;                // bob offset, so a pile doesn't bob in sync
		uint32_t variant = 0;           // random pick among the art; fixed for life
		int32_t look = -1, type = -1, inst = -1;
		int32_t bounces = 0;
		int32_t state = FLYING;
		bool alive = false;
		// swirl / pull (relative to the player)
		float swirl_t = 0, swirl_dur = 0.5f, r0 = 0, a0 = 0, h0 = 0, pull_speed = 0;
	};

	struct Look {   // one texture at one size
		int32_t type = 0;
		float sx = 0.3f, sy = 0.3f, fy = 0.175f;
	};

	struct Type {   // one MultiMesh (one texture)
		std::vector<float> buf, prev;
		std::vector<int32_t> free_inst;
		int32_t high = 0;
		int32_t capacity = 0;
		bool changed = false;        // written this tick
		bool changed_last = false;   // written last tick (prev still differs from buf)
	};

	// ---- settings (set_settings) ----
	float large_value = 20, huge_value = 100;
	float burst_up_min = 5, burst_up_max = 8, burst_out_min = 1.5f, burst_out_max = 4;
	float gravity = 20, min_floor_normal_y = 0.7f;
	float restitution = 0.45f, friction = 0.6f, min_bounce_speed = 2;
	int max_bounces = 3;
	bool swirl = true;
	float swirl_time = 1, swirl_turns = 1.5f, swirl_direction = 1, swirl_tightening = 2;
	float swirl_spin_up = 1.5f, swirl_min_time_fraction = 0.4f;
	float collect_distance = 0.9f, pull_start_speed = 4, pull_max_speed = 30, pull_acceleration = 60;
	int merge_threshold = 150;
	float merge_cell_size = 3;
	int merge_interval_ms = 500;
	float fall_kill_y = -100;

	std::vector<Coin> coins;
	std::vector<int32_t> free_slots;
	int alive_count = 0;
	std::vector<Look> looks;
	int tier_start[3] = { 0, 0, 0 }, tier_count[3] = { 0, 0, 0 };
	std::vector<Type> types;

	PhysicsDirectSpaceState3D *space = nullptr;
	Ref<PhysicsRayQueryParameters3D> query;
	TypedArray<RID> base_exclude;
	int64_t last_merge_ms = -1000000;
	uint32_t rng = 0x9E3779B9u;
	double last_gold = 0.0;
	double last_step_ms = 0.0;

	float randf();
	float rand_range(float a, float b) { return a + (b - a) * randf(); }
	int look_for(double value, uint32_t variant) const;
	int take_instance(int type);
	void release_instance(int type, int inst);
	void set_look(Coin &c, bool snap);
	void write(const Coin &c, float lift, float bob, bool snap);
	Dictionary raycast(const Vector3 &from, const Vector3 &to);
	void remove(int i);
	void merge_pass();

protected:
	static void _bind_methods();

public:
	GoldCore();

	void set_settings(const Dictionary &d);
	// Per size (0 small, 1 large, 2 huge): one look per texture choice, as
	// [type, scale_x, scale_y, float_height] quads.
	void set_looks(const PackedFloat32Array &small, const PackedFloat32Array &large, const PackedFloat32Array &huge);
	int add_type();
	void set_world(Object *space_state, const TypedArray<RID> &exclude);

	void drop(const Vector3 &origin, double value, int count);
	// Returns [gold collected, coins collected, then x, y, z, impact speed per floor impact].
	PackedFloat32Array step(float delta, const Vector3 &player_pos, float pickup_range, bool has_player, int64_t now_ms);
	void clear();
	int count() const { return alive_count; }
	double get_last_gold() const { return last_gold; }   // exact gold collected last step
	double get_last_step_ms() const { return last_step_ms; }

	PackedFloat32Array get_buffer(int type) const;
	PackedFloat32Array get_prev_buffer(int type) const;
	int get_instance_capacity(int type) const;
	int get_visible_count(int type) const;
	bool needs_upload(int type) const;
};

} // namespace godot
