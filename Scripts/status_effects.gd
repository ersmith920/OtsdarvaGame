# Autoload "StatusEffects": every damage-over-time effect (burn now, bleed/poison later)
# lives in flat arrays and ticks in one place, instead of a timer per enemy.
#
# Enemies are split into SLICES groups that tick on different physics frames, so 500
# burning enemies cost a little every frame instead of one big hitch every TICK seconds.
# Each tick, all of one enemy's DoT damage is added up into ONE hit (one damage number).
# DoT hits have a proc coefficient of 0, so they never trigger on-hit items.
extends Node

## Seconds between DoT damage ticks for any one enemy.
const TICK := 0.25
## How many groups the ticking is spread across (about TICK x physics rate).
const SLICES := 15


class Bucket:
	var enemy: Array[Enemy] = []
	var key: Array[StringName] = []
	var dps := PackedFloat32Array()
	var left := PackedFloat32Array()
	var last := PackedFloat64Array()   # game time this stack last dealt damage
	var source: Array = []


var _buckets: Array[Bucket] = []
var _counts := {}      # enemy -> {effect key: active stacks}
var _time := 0.0       # game time, advanced only while not paused
var _frame := 0
var _total := 0        # stacks across all buckets


func _ready() -> void:
	for i in SLICES:
		_buckets.append(Bucket.new())


## Adds one DoT stack: `total` damage spread evenly over `duration` seconds.
## Past max_stacks for this enemy and key, it replaces the stack closest to running out.
func add_dot(enemy: Enemy, key: StringName, total: float, duration: float, max_stacks: int, source: Gun) -> void:
	if enemy == null or enemy.dead or total <= 0.0 or duration <= 0.0:
		return
	var b := _bucket_of(enemy)
	var dps := total / duration
	var per_enemy: Dictionary = _counts.get(enemy, {})
	var count: int = per_enemy.get(key, 0)

	if max_stacks > 0 and count >= max_stacks:
		var weakest := -1
		for i in b.enemy.size():
			if b.enemy[i] == enemy and b.key[i] == key and (weakest == -1 or b.left[i] < b.left[weakest]):
				weakest = i
		if weakest != -1:
			_flush_one(b, weakest)   # bank the old stack's damage so far before replacing it
			b.dps[weakest] = dps
			b.left[weakest] = duration
			b.source[weakest] = source
			return

	b.enemy.append(enemy)
	b.key.append(key)
	b.dps.append(dps)
	b.left.append(duration)
	b.last.append(_time)
	b.source.append(source)
	per_enemy[key] = count + 1
	_counts[enemy] = per_enemy
	_total += 1


## How many stacks of a DoT an enemy has right now (e.g. for "more damage to burning enemies").
func get_stacks(enemy: Enemy, key: StringName) -> int:
	var per_enemy: Dictionary = _counts.get(enemy, {})
	return per_enemy.get(key, 0)


func _physics_process(delta: float) -> void:
	_time += delta
	_frame += 1
	if _total == 0:
		return
	var b := _buckets[_frame % SLICES]
	if b.enemy.is_empty():
		return

	var totals := {}    # enemy -> damage this tick
	var sources := {}   # enemy -> a source gun
	var i := b.enemy.size() - 1
	while i >= 0:
		var e := b.enemy[i]
		if not is_instance_valid(e) or e.dead:
			_remove(b, i)
			i -= 1
			continue
		var dt := _time - b.last[i]
		b.last[i] = _time
		var t := minf(dt, b.left[i])
		totals[e] = totals.get(e, 0.0) + b.dps[i] * t
		if not sources.has(e):
			sources[e] = b.source[i]
		b.left[i] -= dt
		if b.left[i] <= 0.0:
			_remove(b, i)
		i -= 1

	for e: Enemy in totals:
		_deal(e, totals[e], sources[e])


func _deal(e: Enemy, amount: float, src) -> void:
	if amount <= 0.0 or not is_instance_valid(e) or e.dead:
		return
	var hit := HitInfo.make(e, amount, false, src if is_instance_valid(src) else null, 0.0,
			HitInfo.Kind.DOT, e.get_aim_position())
	HitSystem.deal_hit(hit)


# Deals one stack's damage up to now (used before a capped stack gets replaced).
func _flush_one(b: Bucket, i: int) -> void:
	var dt := _time - b.last[i]
	b.last[i] = _time
	var t := minf(dt, b.left[i])
	if t > 0.0:
		_deal(b.enemy[i], b.dps[i] * t, b.source[i])


func _bucket_of(e: Enemy) -> Bucket:
	return _buckets[e.get_instance_id() % SLICES]


# Swap-with-last removal, keeping the per-enemy counts right.
func _remove(b: Bucket, i: int) -> void:
	var e := b.enemy[i]
	if is_instance_valid(e) and _counts.has(e):
		var per_enemy: Dictionary = _counts[e]
		var c: int = per_enemy.get(b.key[i], 1) - 1
		if c <= 0:
			per_enemy.erase(b.key[i])
		else:
			per_enemy[b.key[i]] = c
		if per_enemy.is_empty():
			_counts.erase(e)
	elif not is_instance_valid(e):
		_counts.erase(e)
	var last := b.enemy.size() - 1
	b.enemy[i] = b.enemy[last]
	b.key[i] = b.key[last]
	b.dps[i] = b.dps[last]
	b.left[i] = b.left[last]
	b.last[i] = b.last[last]
	b.source[i] = b.source[last]
	b.enemy.resize(last)
	b.key.resize(last)
	b.dps.resize(last)
	b.left.resize(last)
	b.last.resize(last)
	b.source.resize(last)
	_total -= 1
