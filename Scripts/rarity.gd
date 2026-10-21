# The rarities guns (and later other rolled things) come in.
# Rarity is the same scale as item tiers, just counted the other way:
#   COMMON = tier 5, UNCOMMON = tier 4, RARE = tier 3, EPIC = tier 2, LEGENDARY = tier 1.
# Colors come from TierColors, so rarity and item tiers always match.
#
# MYTHIC sits above Legendary and only comes from the Combiner (two Legendaries). It has no
# item tier. Instead of one color it's a pale rainbow gradient that rolls across the screen:
# get_color() gives white for it, and paint() puts the rainbow shader on the UI showing it
# (white x rainbow = rainbow). The glow layers and frame glows get the same gradient.
class_name Rarity
extends RefCounted

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHIC }

const COUNT := 6
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]

## Seconds for the Mythic rainbow to roll one full rainbow past a point.
const RAINBOW_CYCLE := 3.0
## How washed-out the rainbow is: lower = paler, brighter pastel colors (0 = white).
const RAINBOW_SATURATION := 0.42
## Screen pixels one full rainbow spans (smaller = tighter bands).
const RAINBOW_WIDTH := 420.0
## How much the gradient's bands shimmer brighter as they roll (0 = steady).
const RAINBOW_SHIMMER := 0.15

const _RAINBOW_SHADER := """
shader_type canvas_item;
render_mode BLEND;
uniform float cycle = 3.0;
uniform float saturation = 0.42;
uniform float width = 420.0;
uniform float shimmer = 0.15;
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	// Diagonal bands in screen space, so neighbouring Mythic things share one gradient.
	float t = (FRAGCOORD.x + FRAGCOORD.y * 0.6) / width - TIME / cycle;
	float glow = 1.0 + shimmer * sin(t * 6.2831853 * 2.0);
	c.rgb *= hsv(fract(t), saturation, 1.0) * glow;
	COLOR = c;
}
"""

## Legendary shine: a white sheen that rolls across its gold, like light sliding over metal.
## Seconds between sheens passing a point.
const SHINE_CYCLE := 2.4
## Screen pixels from one sheen to the next.
const SHINE_WIDTH := 520.0
## How white the sheen gets at its peak (0 = no shine, 1 = pure white).
const SHINE_STRENGTH := 0.8
## How thin the sheen is (higher = a sharper, narrower glint).
const SHINE_SHARPNESS := 10.0

const _SHINE_SHADER := """
shader_type canvas_item;
render_mode BLEND;
uniform float cycle = 2.4;
uniform float width = 520.0;
uniform float strength = 0.8;
uniform float sharpness = 10.0;
void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	// Diagonal sheen bands in screen space, sliding across.
	float t = (FRAGCOORD.x + FRAGCOORD.y * 0.6) / width - TIME / cycle;
	float band = pow(0.5 + 0.5 * sin(t * 6.2831853), sharpness);
	// A softer second glint trailing the main one.
	band = max(band, 0.35 * pow(0.5 + 0.5 * sin(t * 6.2831853 - 0.9), sharpness * 2.0));
	float bright = max(c.r, max(c.g, c.b));
	c.rgb = mix(c.rgb, vec3(bright) * 1.15, band * strength);
	COLOR = c;
}
"""
static var _materials := {}   # [rarity, additive] -> ShaderMaterial


static func to_tier(rarity: int) -> int:
	if rarity >= MYTHIC:
		return 0
	return 5 - clampi(rarity, 0, LEGENDARY)


## Item tier 0 is Mythic (special items only); 1-5 are Legendary down to Common.
static func from_tier(tier: int) -> int:
	if tier <= 0:
		return MYTHIC
	return clampi(5 - tier, 0, LEGENDARY)


static func name_of(rarity: int) -> String:
	return NAMES[clampi(rarity, 0, COUNT - 1)]


## The rarity's color. Mythic is white: paint() turns it into the rolling rainbow.
static func get_color(rarity: int) -> Color:
	if rarity >= MYTHIC:
		return Color.WHITE
	return TierColors.get_color(to_tier(rarity))


## True if this rarity's color has to be re-applied every frame. None do now (the Mythic
## rainbow moves in a shader), but RarityAnimator still supports it.
static func is_animated(_rarity: int) -> bool:
	return false


## Gives a piece of UI the look of this rarity: the rolling rainbow for Mythic, the rolling
## gold shine for Legendary, nothing extra for the others. Call it on everything drawn in the
## rarity's color (labels, frames, tiles); a TextGlow label's glow layers are done too.
## Safe to call again with another rarity (e.g. a reused tooltip), it switches back.
## Pass -1 to just clear it.
static func paint(item: CanvasItem, rarity: int) -> void:
	item.material = _effect_material(rarity, false)
	if item.has_meta(&"glow_layers"):
		for glow in item.get_meta(&"glow_layers"):
			var mat := _effect_material(rarity, true)
			(glow as CanvasItem).material = mat if mat != null else TextGlow._additive


## Same for an item tier (tier 1 = Legendary shine).
static func paint_tier(item: CanvasItem, tier: int) -> void:
	paint(item, from_tier(tier))


static func _effect_material(rarity: int, additive: bool) -> ShaderMaterial:
	if rarity < LEGENDARY:
		return null
	var key := [mini(rarity, MYTHIC), additive]
	if _materials.has(key):
		return _materials[key]
	var shader := Shader.new()
	var mat := ShaderMaterial.new()
	var blend := "blend_add" if additive else "blend_mix"
	if rarity >= MYTHIC:
		shader.code = _RAINBOW_SHADER.replace("BLEND", blend)
		mat.shader = shader
		mat.set_shader_parameter(&"cycle", RAINBOW_CYCLE)
		mat.set_shader_parameter(&"saturation", RAINBOW_SATURATION)
		mat.set_shader_parameter(&"width", RAINBOW_WIDTH)
		mat.set_shader_parameter(&"shimmer", RAINBOW_SHIMMER)
	else:
		shader.code = _SHINE_SHADER.replace("BLEND", blend)
		mat.shader = shader
		mat.set_shader_parameter(&"cycle", SHINE_CYCLE)
		mat.set_shader_parameter(&"width", SHINE_WIDTH)
		mat.set_shader_parameter(&"strength", SHINE_STRENGTH)
		mat.set_shader_parameter(&"sharpness", SHINE_SHARPNESS)
	_materials[key] = mat
	return mat


## The Mythic rainbow at this moment. offset (0-1) shifts the hue, for multi-colored effects.
static func rainbow(offset := 0.0) -> Color:
	var hue := fposmod(Time.get_ticks_msec() / 1000.0 / RAINBOW_CYCLE + offset, 1.0)
	return Color.from_hsv(hue, RAINBOW_SATURATION, 1.0)


## Rolls a rarity from a LootTable's tier odds, shifted toward higher rarities by luck.
## Pass null to get COMMON.
static func roll(table: LootTable, luck: float = 0.0) -> int:
	if table == null:
		return COMMON
	return from_tier(table.roll_tier(luck))
