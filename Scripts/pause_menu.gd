# Pause menu. Escape toggles it; it really pauses the tree.
# Blurs and tints everything behind it, shows the cursor, and has Resume / Settings / Exit.
extends Control

@export_group("Background")
## Color and opacity of the layer over the blurred game. Alpha controls how strong it is.
@export var tint_color := Color(0.0, 0.0, 0.0, 0.5)
## How blurry the game behind the menu is. 0 = sharp.
@export_range(0.0, 6.0, 0.1) var blur_amount := 2.5

@export_group("Buttons")
@export var font: Font
@export var font_size := 28
@export var button_size := Vector2(260, 56)
@export var button_gap := 14

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 2.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	COLOR = vec4(mix(col, tint.rgb, tint.a), 1.0);
}
"""

# The slider shows sensitivity x1000 (0.008 is stored, 8.0 is displayed).
const SENS_DISPLAY_SCALE := 1000.0
const SENS_DISPLAY_MIN := 1.0
const SENS_DISPLAY_MAX := 20.0
const SENS_DISPLAY_STEP := 0.1

var _main_page: VBoxContainer
var _settings_page: VBoxContainer


func _ready() -> void:
	# Keep running while the tree is paused (children inherit this).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Register the action in code if it isn't in the Input Map yet.
	if not InputMap.has_action(&"pause"):
		InputMap.add_action(&"pause")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(&"pause", key)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_build_background()
	_build_pages()
	_apply_volume(GameManager.master_volume)


func _build_background() -> void:
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"blur", blur_amount)
	mat.set_shader_parameter(&"tint", tint_color)

	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.material = mat
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_pages() -> void:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Main page: Resume / Settings / Exit
	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", button_gap)
	center.add_child(_main_page)
	_main_page.add_child(_make_button("Resume", _resume))
	_main_page.add_child(_make_button("Settings", func(): _show_settings(true)))
	_main_page.add_child(_make_button("Exit", _on_exit_pressed))

	# Settings page: sensitivity slider + Back
	_settings_page = VBoxContainer.new()
	_settings_page.add_theme_constant_override("separation", button_gap)
	_settings_page.visible = false
	center.add_child(_settings_page)

	var title := _make_label("Settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_page.add_child(title)

	_add_slider_row("Mouse Sensitivity", SENS_DISPLAY_MIN, SENS_DISPLAY_MAX, SENS_DISPLAY_STEP,
		GameManager.mouse_sensitivity * SENS_DISPLAY_SCALE, _on_sensitivity_changed, "%.1f")
	_add_slider_row("Master Volume", 0.0, 100.0, 1.0,
		GameManager.master_volume * 100.0, _on_volume_changed, "%d%%")

	_settings_page.add_child(_make_button("Back", func(): _show_settings(false)))


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(on_pressed)
	return button


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	return label


# ---------- Input ----------

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()

	if visible:
		if _settings_page.visible:
			_show_settings(false)   # Escape in settings goes back one step
		else:
			_resume()
	else:
		# Don't open on top of the hold-Tab menu.
		if GameManager.player != null and GameManager.player.menu_open:
			return
		_pause()


# ---------- Pause / resume ----------

func _pause() -> void:
	_show_settings(false)
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_settings(show: bool) -> void:
	_main_page.visible = not show
	_settings_page.visible = show


func _on_exit_pressed() -> void:
	get_tree().quit()


# ---------- Settings ----------
# One settings row: name, slider, live value text.
func _add_slider_row(label_text: String, min_v: float, max_v: float, step: float,
		value: float, on_change: Callable, format: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_settings_page.add_child(row)

	var name_label := _make_label(label_text)
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(260, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)

	var value_label := _make_label("")
	value_label.custom_minimum_size = Vector2(110, 0)
	value_label.clip_text = true   # width stays fixed no matter what the text is
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var update_text := func(v: float) -> void:
		value_label.text = format % v
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		update_text.call(v))
	slider.set_value_no_signal(value)
	update_text.call(value)


func _on_sensitivity_changed(display_value: float) -> void:
	GameManager.mouse_sensitivity = display_value / SENS_DISPLAY_SCALE


func _on_volume_changed(percent: float) -> void:
	GameManager.master_volume = percent / 100.0
	_apply_volume(GameManager.master_volume)


func _apply_volume(linear: float) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	# At 0 the bus is muted outright, since linear_to_db(0) is minus infinity.
	AudioServer.set_bus_mute(bus, linear <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))
