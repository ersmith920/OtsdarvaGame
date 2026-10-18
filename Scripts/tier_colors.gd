# Single source of truth for tier colors (aura glow, popup name, future UI).
class_name TierColors
extends RefCounted

const COLORS := {
	1: Color(0.865, 0.33, 0.0, 1.0),
	2: Color(1.0, 0.248, 0.698, 1.0),
	3: Color(0.25, 0.55, 1.0, 1.0),
	4: Color(0.0, 0.829, 0.244, 1.0),
	5: Color(0.674, 0.665, 0.656, 1.0),
}

static func get_color(tier: int) -> Color:
	return COLORS.get(tier, COLORS[5])
