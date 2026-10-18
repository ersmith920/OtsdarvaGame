class_name Stat
extends RefCounted

signal changed(new_value: float)

var base_value: float
var _flat: Dictionary = {}      # source -> float
var _additive: Dictionary = {}  # source -> float (0.2 = +20%)
var _multiplicative: Dictionary = {}  # source -> float (1.5 = x1.5)
var value: float

func _init(base: float = 0.0) -> void:
	base_value = base
	_recalculate()

func add_flat(source: Variant, amount: float) -> void:
	_flat[source] = _flat.get(source, 0.0) + amount
	_recalculate()

func add_percent(source: Variant, amount: float) -> void:
	_additive[source] = _additive.get(source, 0.0) + amount
	_recalculate()

func add_multiplier(source: Variant, mult: float) -> void:
	_multiplicative[source] = mult
	_recalculate()

func remove_source(source: Variant) -> void:
	_flat.erase(source)
	_additive.erase(source)
	_multiplicative.erase(source)
	_recalculate()

func _recalculate() -> void:
	var flat_sum := 0.0
	for v in _flat.values(): flat_sum += v
	var pct_sum := 1.0
	for v in _additive.values(): pct_sum += v
	var mult := 1.0
	for v in _multiplicative.values(): mult *= v

	value = (base_value + flat_sum) * pct_sum * mult
	changed.emit(value)
