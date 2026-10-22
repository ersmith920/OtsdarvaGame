# A retro screen over the game world (not the HUD, which has its own CRT pass): the 3D view
# looks like it's coming through the mech's cockpit monitors.
#   - chromatic aberration: red and blue split apart toward the edges of the screen,
#   - film grain: fine moving noise,
#   - scanlines: faint TV lines,
#   - a vignette: the corners fall off a little,
#   - a slow rolling refresh band.
# Lives under the HUD layer, before the HUD's own nodes, so only the world goes through it.
# Every effect has its own strength below (0 turns it off).
extends ColorRect

## Pixels the red / blue channels split apart at the screen corners.
@export_range(0.0, 8.0, 0.1) var aberration := 3.0
## Strength of the film grain.
@export_range(0.0, 0.3, 0.005) var grain := 0.045
## How dark the scanlines are.
@export_range(0.0, 0.5, 0.01) var scanlines := 0.07
## How dark the corners get.
@export_range(0.0, 1.0, 0.01) var vignette := 0.32
## Brightness of the rolling refresh band.
@export_range(0.0, 0.2, 0.005) var roll_band := 0.025

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float aberration = 2.4;
uniform float grain = 0.045;
uniform float scan = 0.07;
uniform float vignette = 0.32;
uniform float roll_band = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d) * 2.0;   // 0 in the middle, 1 in the corners
	// Chromatic aberration, growing toward the edges.
	vec2 off = normalize(d + 1e-5) * aberration * r2 * SCREEN_PIXEL_SIZE;
	vec3 col;
	col.r = texture(screen, uv + off).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - off).b;
	// Scanlines (every other row of pixels, softly).
	col *= 1.0 - scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	// Rolling refresh band.
	float band = fract(uv.y - TIME * 0.11);
	col += roll_band * smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.08, 0.2, band));
	// Film grain (changes every frame).
	float n = hash(FRAGCOORD.xy + vec2(fract(TIME * 13.7) * 977.0, fract(TIME * 7.3) * 613.0));
	col += (n - 0.5) * grain;
	// Vignette.
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, r2);
	COLOR = vec4(col, 1.0);
}
"""

var _mat : ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	_apply()
	# Godot copies the screen only once per frame for screen-reading shaders; copy it fresh
	# here so this sees everything drawn before it (e.g. the speed blur).
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	get_parent().add_child.call_deferred(copy)
	get_parent().move_child.call_deferred(copy, get_index())


func _apply() -> void:
	_mat.set_shader_parameter(&"aberration", aberration)
	_mat.set_shader_parameter(&"grain", grain)
	_mat.set_shader_parameter(&"scan", scanlines)
	_mat.set_shader_parameter(&"vignette", vignette)
	_mat.set_shader_parameter(&"roll_band", roll_band)
