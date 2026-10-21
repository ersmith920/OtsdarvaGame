# Autoload "StatusEffects": every damage-over-time effect (burn now, bleed/poison later)
# lives in flat arrays and ticks in one place, instead of a timer per enemy.
#
# Enemies are split into SLICES groups that tick on different physics frames, so 500
# burning enemies cost a little every frame instead of one big hitch every TICK seconds.
# Each tick, all stacks of one DoT type on one enemy are added up into ONE hit, using
# that DoT's own proc coefficient (0 = its ticks can't trigger on-hit items).
# A DoT's ticks can never re-trigger the effect that applied it (it's in their proc chain).
extends Node

## How many groups the ticking is spread across. Each enemy's DoTs tick once every
## SLICES physics frames, so at 60 physics ticks per second that's every 0.25s.
const SLICES := 15
## Seconds between DoT ticks for any one enemy (at 60 physics ticks per second).
const TICK := SLICES / 60.0


class Bucket:
	# Untyped on purpose: an enemy can be freed while it still has stacks here, and a
	# typed Array[Enemy] refuses to hold (or move) a freed instance.
	var enemy: Array = []
	var id := PackedInt64Array()       # enemy instance id, still usable after it's freed
	var key: Array[StringName] = []
	var dmg := PackedFloat32Array()    # damage per tick
	var ticks := PackedInt32Array()    # ticks left
	var source: Array = []
	var proc := PackedFloat32Array()   # proc coefficient of this DoT's ticks


var _buckets: Array[Bucket] = []
var _counts := {}      # enemy instance id -> {effect key: active stacks}
var _frame := 0
var _total := 0        # stacks across all buckets


func _ready() -> void:
	for i in SLICES:
		_buckets.append(Bucket.new())


## Adds one DoT stack that deals `damage_per_tick` every TICK seconds for `duration` seconds.
## Past max_stacks for this enemy and key, it replaces the stack closest to running out.
## `proc` is the proc coefficient of its ticks (0 = they never trigger on-hit items).
func add_dot(enemy: Enemy, key: StringName, damage_per_tick: float, duration: float, max_stacks: int,
		source: Gun, proc: float = 0.0) -> void:
	if enemy == null or enemy.dead or damage_per_tick <= 0.0 or duration <= 0.0:
		return
	var b := _bucket_of(enemy)
	var tick_count := maxi(roundi(duration / TICK), 1)
	var eid := enemy.get_instance_id()
	var per_enemy: Dictionary = _counts.get(eid, {})
	var count: int = per_enemy.get(key, 0)

	if max_stacks > 0 and count >= max_stacks:
		var weakest := -1
		for i in b.enemy.size():
			if b.id[i] == eid and b.key[i] == key and (weakest == -1 or b.ticks[i] < b.ticks[weakest]):
				weakest = i
		if weakest != -1:
			b.dmg[weakest] = damage_per_tick
			b.ticks[weakest] = tick_count
			b.source[weakest] = source
			b.proc[weakest] = proc
			return

	b.enemy.append(enemy)
	b.id.append(eid)
	b.key.append(key)
	b.dmg.append(damage_per_tick)
	b.ticks.append(tick_count)
	b.source.append(source)
	b.proc.append(proc)
	per_enemy[key] = count + 1
	_counts[eid] = per_enemy
	_total += 1


## How many stacks of a DoT an enemy has right now (e.g. for "more damage to burning enemies").
func get_stacks(enemy: Enemy, key: StringName) -> int:
	if not is_instance_valid(enemy):
		return 0
	var per_enemy: Dictionary = _counts.get(enemy.get_instance_id(), {})
	return per_enemy.get(key, 0)


func _physics_process(delta: float) -> void:
	_frame += 1
	if _total == 0:
		return
	var b := _buckets[_frame % SLICES]
	if b.enemy.is_empty():
		return

	# One hit per enemy per DoT type: enemy -> {key: [damage, source, proc]}
	var totals := {}
	var i := b.enemy.size() - 1
	while i >= 0:
		var e = b.enemy[i]
		if not is_instance_valid(e) or (e as Enemy).dead:
			_remove(b, i)
			i -= 1
			continue
		var per_enemy: Dictionary = totals.get(e, {})
		var entry: Array = per_enemy.get(b.key[i], [0.0, b.source[i], b.proc[i]])
		entry[0] += b.dmg[i]
		per_enemy[b.key[i]] = entry
		totals[e] = per_enemy
		b.ticks[i] -= 1
		if b.ticks[i] <= 0:
			_remove(b, i)
		i -= 1

	for e: Enemy in totals:
		var per_enemy: Dictionary = totals[e]
		for key: StringName in per_enemy:
			var entry: Array = per_enemy[key]
			_deal(e, entry[0], entry[1], key, entry[2])


func _deal(e: Enemy, amount: float, src, key: StringName, proc: float) -> void:
	if amount <= 0.0 or not is_instance_valid(e) or e.dead:
		return
	var hit := HitInfo.make(e, amount, false, src if is_instance_valid(src) else null, proc,
			HitInfo.Kind.DOT, e.get_aim_position())
	hit.chain.append(key)   # a burn tick can't apply more burn, and so on
	HitSystem.deal_hit(hit)


func _bucket_of(e: Enemy) -> Bucket:
	return _buckets[e.get_instance_id() % SLICES]


# Swap-with-last removal, keeping the per-enemy counts right.
# Counts are keyed by instance id, so they're cleaned up even if the enemy was already freed.
func _remove(b: Bucket, i: int) -> void:
	var eid := b.id[i]
	if _counts.has(eid):
		var per_enemy: Dictionary = _counts[eid]
		var c: int = per_enemy.get(b.key[i], 1) - 1
		if c <= 0:
			per_enemy.erase(b.key[i])
		else:
			per_enemy[b.key[i]] = c
		if per_enemy.is_empty():
			_counts.erase(eid)
	var last := b.enemy.size() - 1
	b.enemy[i] = b.enemy[last]
	b.id[i] = b.id[last]
	b.key[i] = b.key[last]
	b.dmg[i] = b.dmg[last]
	b.ticks[i] = b.ticks[last]
	b.source[i] = b.source[last]
	b.proc[i] = b.proc[last]
	b.enemy.resize(last)
	b.id.resize(last)
	b.key.resize(last)
	b.dmg.resize(last)
	b.ticks.resize(last)
	b.source.resize(last)
	b.proc.resize(last)
	_total -= 1
