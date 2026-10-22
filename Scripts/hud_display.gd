# Shows the HUD the way a cockpit display would: the HUD readouts (StatBars, Timer,
# EnemyCount, Gold, ItemPopup, WeaponStack) are rendered off-screen into the sibling
# SubViewport "HudViewport", and this rect draws that image through a CRT pass:
#   - heavy phosphor bloom (bright parts bleed light, in three rings: tight, mid and wide),
#   - a slight curve, like symbology projected on the canopy glass,
#   - red / blue fringing toward the edges,
#   - fine scanlines and a faint flicker.
# It also hosts HudMotion, which sways the whole display as you turn, strafe and land.
# Menus (Tab, pause, popups) stay outside the viewport so they keep mouse input.
class_name HudDisplay
extends TextureRect

## How strong the bloom is (0 = none), and how far it spreads (1 = default).
@export_range(0.0, 4.0, 0.05) var bloom := 1.9
@export_range(0.25, 3.0, 0.05) var bloom_spread := 1.0
## Canopy curve (0 = flat).
@export_range(0.0, 0.2, 0.005) var curve := 0.04
## Color fringing toward the edges, in pixels.
@export_range(0.0, 4.0, 0.1) var fringe := 1.2
## Scanline darkness (0 = none) and flicker (0 = none).
@export_range(0.0, 0.6, 0.01) var scanlines := 0.16
@export_range(0.0, 0.2, 0.005) var flicker := 0.025
## How much the left and right sides bend toward you (0 = flat).
@export_range(0.0, 0.3, 0.005) var wrap := 0.11
## How far the HUD dims while the pause menu or a choice popup is up.
@export_range(0.0, 1.0, 0.05) var menu_dim := 0.2

const SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform sampler2D glow_near : filter_linear;   // HUD blurred at 1/4 resolution
uniform sampler2D glow_far : filter_linear;    // ...and again at 1/16
uniform float bloom = 1.6;
uniform float curve = 0.04;
uniform float fringe = 1.2;
uniform float scan = 0.16;
uniform float flicker = 0.025;
uniform float wrap = 0.11;
uniform float fade = 1.0;

vec2 warp(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curve * (c.yx * c.yx);
	// Canopy wrap: the display bends around you, so things toward the left and right
	// edges pinch in vertically, like symbology on curved glass seen from inside. (It only
	// ever pulls content inward, so nothing at the edges gets cut off.)
	c.y *= 1.0 + wrap * c.x * c.x;
	return c * 0.5 + 0.5;
}

vec4 premul(sampler2D tex, vec2 uv) {
	vec4 t = texture(tex, uv);
	return vec4(t.rgb * t.a, t.a);
}

void fragment() {
	vec2 uv = warp(UV);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE;
		// Color fringing: red pushed outward, blue inward, more toward the edges.
		vec2 f = (uv - 0.5) * fringe * px * 2.0;
		vec4 c = premul(TEXTURE, uv);
		c.r = premul(TEXTURE, uv + f).r;
		c.b = premul(TEXTURE, uv - f).b;
		// Tight halo straight from the image (a small cross of taps), then the soft bloom.
		vec3 halo = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = 6.2831853 * float(i) / 8.0;
			halo += premul(TEXTURE, uv + vec2(cos(a), sin(a)) * 1.6 * px).rgb;
		}
		vec3 glow = halo / 8.0 * 0.35 + texture(glow_near, uv).rgb * 0.9 + texture(glow_far, uv).rgb * 0.8;
		// Scanlines and flicker on the image (the bloom glows through them).
		float lines = 1.0 - scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
		float flick = 1.0 + flicker * sin(TIME * 47.0) * sin(TIME * 13.0);
		// (Writing COLOR drops the node's modulate, so fading goes through `fade`.)
		// Glow spills mostly outward: over the element itself it's held back, so text
		// inside filled tags stays readable while the edges burn.
		vec3 rgb = c.rgb * lines * flick + glow * bloom * flick * (1.0 - 0.65 * c.a);
		// Over-bright areas keep their hue (orange stays orange instead of clipping to
		// yellow) and only partly burn toward white, like an overdriven phosphor.
		float peak = max(rgb.r, max(rgb.g, rgb.b));
		if (peak > 1.0) {
			rgb = mix(rgb / peak, min(rgb, vec3(1.0)), 0.3);
		}
		COLOR = vec4(rgb, c.a) * fade;
	}
}
"""

## One blur pass: a 5x5 tent of taps over the source, written premultiplied. `threshold`
## keeps only the bright parts (first pass); later passes just blur.
const BLUR_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D src : filter_linear;
uniform vec2 src_px;
uniform float spread = 1.0;
uniform float threshold = 0.0;
uniform bool src_premul = false;

vec3 tap(vec2 uv) {
	vec4 t = texture(src, uv);
	vec3 c = src_premul ? t.rgb : t.rgb * t.a;
	float lum = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, threshold + 0.45, lum);
}

void fragment() {
	vec3 acc = vec3(0.0);
	float total = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			float w = (3.0 - abs(float(x))) * (3.0 - abs(float(y)));
			acc += tap(UV + vec2(float(x), float(y)) * src_px * spread) * w;
			total += w;
		}
	}
	COLOR = vec4(acc / total, 1.0);
}
"""

## Bloom chain resolution divisors (of the window size).
const NEAR_DIV := 4
const FAR_DIV := 16

var _viewport : SubViewport
var _mat : ShaderMaterial
var _fade := 1.0
var _near : SubViewport
var _far : SubViewport
var _near_mat : ShaderMaterial
var _far_mat : ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport = get_parent().get_node_or_null("HudViewport") as SubViewport
	if _viewport == null:
		push_warning("HudDisplay: needs a sibling SubViewport named HudViewport")
		return
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size_2d_override_stretch = true
	texture = _viewport.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	_apply_settings()

	# Bloom chain: the HUD, thresholded and blurred into a quarter-size image, then blurred
	# again into a 1/16 one. Sampled with linear filtering, these give a smooth, wide glow
	# with no stamped copies.
	var near_pair := _make_blur(_viewport.get_texture(), 0.45, false)
	_near = near_pair[0]
	_near_mat = near_pair[1]
	var far_pair := _make_blur(_near.get_texture(), 0.0, true)
	_far = far_pair[0]
	_far_mat = far_pair[1]
	_mat.set_shader_parameter(&"glow_near", _near.get_texture())
	_mat.set_shader_parameter(&"glow_far", _far.get_texture())

	get_tree().root.size_changed.connect(_resize)
	_resize()
	add_child(HudMotion.new())


func _apply_settings() -> void:
	_mat.set_shader_parameter(&"bloom", bloom)
	_mat.set_shader_parameter(&"curve", curve)
	_mat.set_shader_parameter(&"fringe", fringe)
	_mat.set_shader_parameter(&"scan", scanlines)
	_mat.set_shader_parameter(&"flicker", flicker)
	_mat.set_shader_parameter(&"wrap", wrap)


# Dims behind the pause menu and choice popups (they sit over the HUD); Tab keeps it lit,
# since it lays itself out around the clock and counters.
func _process(delta: float) -> void:
	var dim := get_tree().paused or GameManager.choice_open
	var target := menu_dim if dim else 1.0
	_fade = move_toward(_fade, target, delta * 6.0)
	if _mat != null:
		_mat.set_shader_parameter(&"fade", _fade)


# The viewport renders at the window's real resolution (so text is sharp) while its contents
# lay out in the same base units as the rest of the UI.
func _resize() -> void:
	var base := get_viewport().get_visible_rect().size
	var window := Vector2(get_tree().root.size)
	_viewport.size = Vector2i(maxi(roundi(window.x), 1), maxi(roundi(window.y), 1))
	_viewport.size_2d_override = Vector2i(roundi(base.x), roundi(base.y))
	_size_blur(_near, _near_mat, window, NEAR_DIV, window)
	_size_blur(_far, _far_mat, window, FAR_DIV, window / NEAR_DIV)


# A small off-screen viewport that draws `source` through BLUR_SHADER.
func _make_blur(source: Texture2D, threshold: float, source_premul: bool) -> Array:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := TextureRect.new()
	rect.texture = source
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"src", source)
	mat.set_shader_parameter(&"threshold", threshold)
	mat.set_shader_parameter(&"src_premul", source_premul)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	return [vp, mat]


func _size_blur(vp: SubViewport, mat: ShaderMaterial, window: Vector2, div: int, source_size: Vector2) -> void:
	if vp == null:
		return
	var s := Vector2i(maxi(roundi(window.x / div), 1), maxi(roundi(window.y / div), 1))
	vp.size = s
	(vp.get_child(0) as Control).size = Vector2(s)
	# Taps step about one output pixel (times the spread), so each pass blurs ~5 of its pixels.
	mat.set_shader_parameter(&"src_px", Vector2(1.0, 1.0) / Vector2(s) * bloom_spread)
