# Full-screen radial speed blur at the screen edges, driven by the player's dash_fx (0..1).
extends ColorRect

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float max_blur = 0.12;
uniform float inner_radius = 0.2;

void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5);
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(dir * vec2(aspect, 1.0));
	float mask = smoothstep(inner_radius, inner_radius + 0.4, dist) * strength;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0;
		col += texture(screen_tex, SCREEN_UV - dir * (max_blur * mask * t)).rgb;
	}
	COLOR = vec4(col / 12.0, 1.0);
}
"""

## How far samples smear toward the center at full strength (fraction of the distance).
@export_range(0.0, 0.5, 0.01) var max_blur := 0.12
## Distance from the center (in screen heights) with no blur.
@export_range(0.0, 1.0, 0.01) var inner_radius := 0.2
@export_range(0.0, 1.0, 0.05) var max_strength := 1.0

var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter(&"max_blur", max_blur)
	_mat.set_shader_parameter(&"inner_radius", inner_radius)
	material = _mat
	visible = false


func _process(_delta: float) -> void:
	var player := GameManager.player
	var fx := player.dash_fx if player != null else 0.0
	# Hidden at rest, so the screen copy and 12 samples per pixel only cost anything mid-dash.
	visible = fx > 0.001
	if visible:
		_mat.set_shader_parameter(&"strength", fx * max_strength)
