## Base for item on-hit effects. Add one to an item's On Hit Effects list.
## Make new effects by extending this and overriding _apply() (and on_kill() if needed).
class_name OnHitEffect
extends Resource

## Unique name for this effect. Used to stop it triggering itself in a proc chain.
@export var id: StringName
## Chance to trigger on a hit, with 1 stack and a proc coefficient of 1.0 (0.1 = 10%).
## The hit's proc coefficient scales this (0.5 proc = half the chance).
@export_range(0.0, 1.0, 0.01) var chance := 0.1
## Extra chance per stack after the first. Most effects grow stronger per stack instead.
@export_range(0.0, 1.0, 0.01) var chance_per_stack := 0.0


func try_proc(info: HitInfo, stacks: int) -> void:
	var key := get_key()
	if info.chain.has(key):
		return
	var c := (chance + chance_per_stack * float(stacks - 1)) * info.proc_coefficient
	if c <= 0.0 or randf() >= c:
		return
	_apply(info, stacks)


## What the effect does when it triggers. Override in each effect.
func _apply(_info: HitInfo, _stacks: int) -> void:
	pass


## Called for every enemy killed by any hit, regardless of chance. Override for on-kill items.
func on_kill(_info: HitInfo, _stacks: int) -> void:
	pass


func get_key() -> StringName:
	return id if id != &"" else StringName("effect_%d" % get_instance_id())


## The chain to give hits this effect causes: the parent's chain plus this effect.
func child_chain(info: HitInfo) -> Array[StringName]:
	var chain := info.chain.duplicate()
	chain.append(get_key())
	return chain
