class_name StatModifier
extends Resource

enum Type { FLAT, PERCENT, MULTIPLIER }

@export var stat: StringName
@export var type: Type
@export var amount_per_stack: float
