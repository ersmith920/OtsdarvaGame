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

const INFO_SIZE := Vector2(260, 74)

var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _header: Control
var _title: Label
var _info: Control
var _info_time: Label
var _info_scrap: Label


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
	# KH2-style layout: a big "PAUSE" header across the top left, a stack of glossy command
	# plates down the left side, and a mission info plate (time, scrap) bottom right.
	var header := Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 90
	header.draw.connect(func() -> void:
		# A dark band with a thin blue line under it, the KH menu header.
		header.draw_rect(Rect2(0, 18, header.size.x, 56), Color(0.02, 0.04, 0.12, 0.7))
		header.draw_rect(Rect2(0, 74, header.size.x, 2), Color(HudStyle.CYAN, 0.8))
		header.draw_rect(Rect2(0, 77, header.size.x * 0.4, 1), Color(HudStyle.CYAN, 0.35)))
	_header = header
	_title = HudStyle.make_label("PAUSE", 44, HudStyle.WHITE, true)
	_title.position = Vector2(60, 16)
	header.add_child(_title)

	_main_page = _make_window("COMMAND")
	_main_page.add_child(_make_button("Resume", _resume))
	_main_page.add_child(_make_button("Settings", func(): _show_settings(true)))
	_main_page.add_child(_make_button("Exit", _on_exit_pressed))

	_settings_page = _make_window("CONFIG")
	_settings_page.visible = false
	_add_slider_row("Mouse Sensitivity", SENS_DISPLAY_MIN, SENS_DISPLAY_MAX, SENS_DISPLAY_STEP,
		GameManager.mouse_sensitivity * SENS_DISPLAY_SCALE, _on_sensitivity_changed, "%.1f")
	_add_slider_row("Master Volume", 0.0, 100.0, 1.0,
		GameManager.master_volume * 100.0, _on_volume_changed, "%d%%")
	_settings_page.add_child(_make_button("Back", func(): _show_settings(false)))

	# Mission info, bottom right (like KH's time / munny box).
	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)
	_info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_info.offset_left = -60 - INFO_SIZE.x
	_info.offset_right = -60
	_info.offset_top = -50 - INFO_SIZE.y
	_info.offset_bottom = -50
	_info.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, INFO_SIZE)
		HudStyle.draw_backing(_info, r.grow(4.0))
		HudStyle.draw_plate(_info, Rect2(4, 4, r.size.x - 8, 30), HudStyle.PLATE_TOP, HudStyle.PLATE_BOTTOM, HudStyle.PLATE_RIM, 15.0)
		HudStyle.draw_plate(_info, Rect2(4, 40, r.size.x - 8, 30), HudStyle.PLATE_TOP, HudStyle.PLATE_BOTTOM, HudStyle.PLATE_RIM, 15.0))
	for i in 2:
		var cap := HudStyle.make_label(["TIME", "SCRAP"][i], 13, HudStyle.WHITE)
		cap.position = Vector2(18, 10 + 36 * i)
		_info.add_child(cap)
		var num := HudStyle.make_label("0", 20, HudStyle.GOLD if i == 1 else HudStyle.WHITE, true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.position = Vector2(80, 6 + 36 * i)
		num.size = Vector2(INFO_SIZE.x - 98, 26)
		_info.add_child(num)
		if i == 0:
			_info_time = num
		else:
			_info_scrap = num


# The command window: a metal frame down the left side holding a column of plates.
func _make_window(tab_text: String) -> VBoxContainer:
	# Full-screen holder that keeps the window centered vertically, a fixed gap from the left.
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("margin_left", 80)
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := MarginContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 14)
	frame.add_theme_constant_override("margin_top", 22)
	frame.add_theme_constant_override("margin_right", 26)   # room for a lit plate's slide
	holder.add_child(frame)
	frame.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, frame.size)
		HudStyle.draw_backing(frame, r)
		# "COMMAND" tab on the top edge.
		var tab := Rect2(14, -10, 110, 20)
		HudStyle.draw_plate(frame, tab, Color(1, 1, 1, 0.98), Color(0.75, 0.82, 0.95, 0.98), Color(0.1, 0.2, 0.45), 10.0)
		frame.draw_string(HudStyle.MENU_FONT, Vector2(tab.position.x, tab.end.y - 5.0), tab_text,
				HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 13, Color(0.08, 0.16, 0.42)))
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", button_gap)
	frame.add_child(page)
	page.visibility_changed.connect(func() -> void: holder.visible = page.visible)
	return page


# A KH2 command plate: glossy blue, white rim, text on the left. Hovered, it lights up,
# slides right a little and a pointer appears beside it.
func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = button_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 30
		button.add_theme_stylebox_override(st, box)
	button.add_theme_font_override("font", HudStyle.MENU_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(c, HudStyle.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.12, 0.95))
	button.add_theme_constant_override("outline_size", 6)
	button.set_meta(&"lit", 0.0)
	# The plate is drawn by a child shown behind the button, so the text stays on top.
	var plate := Control.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	button.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.draw.connect(func() -> void:
		var lit : float = button.get_meta(&"lit")
		var r := Rect2(Vector2(lit * 10.0, 0), button.size)
		var top := HudStyle.PLATE_TOP.lerp(Color(0.55, 0.8, 1.0, 0.95), lit)
		var bottom := HudStyle.PLATE_BOTTOM.lerp(Color(0.12, 0.3, 0.7, 0.95), lit)
		HudStyle.draw_plate(plate, r, top, bottom, HudStyle.PLATE_RIM, r.size.y * 0.5)
		if lit > 0.01:
			# Pointer: a white arrowhead left of the plate.
			var y := r.get_center().y
			var x := r.position.x - 6.0
			var pts := PackedVector2Array([Vector2(x - 18, y - 9), Vector2(x, y), Vector2(x - 18, y + 9), Vector2(x - 13, y)])
			plate.draw_colored_polygon(pts, Color(1, 1, 1, lit))
			plate.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.1, 0.3, lit), 1.5, true))
	var light := func(to: float) -> void:
		var t := UIJuice.tween_of(button)
		t.tween_method(func(v: float) -> void:
			button.set_meta(&"lit", v)
			plate.queue_redraw(), button.get_meta(&"lit"), to, 0.12)
	button.mouse_entered.connect(func() -> void:
		light.call(1.0)
		UIJuice.play(UIJuice.Sfx.HOVER))
	button.mouse_exited.connect(func() -> void: light.call(0.0))
	button.button_down.connect(func() -> void:
		UIJuice.play(UIJuice.Sfx.CLICK)
		UIJuice.punch(button, -0.06))
	button.pressed.connect(on_pressed)
	return button


func _make_label(text: String) -> Label:
	return HudStyle.make_label(text.to_upper(), roundi(font_size * 0.75), HudStyle.WHITE)


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
		# Or on top of a pick-one popup (gun store): it has to be answered first.
		if GameManager.choice_open:
			return
		_pause()


# ---------- Pause / resume ----------

func _pause() -> void:
	_show_settings(false)
	get_parent().move_child(self, -1)   # over every HUD element
	visible = true
	var secs := int(GameManager.levelTime)
	@warning_ignore("integer_division")
	_info_time.text = "%02d:%02d" % [secs / 60, secs % 60]
	_info_scrap.text = str(GameManager.player.gold) if GameManager.player != null else "0"
	# Commands deal in from the left one after another; header and info slide in.
	for i in _main_page.get_child_count():
		var b : Control = _main_page.get_child(i)
		b.set_meta(&"lit", 0.0)
		b.get_child(0).queue_redraw()
		b.modulate.a = 0.0
		var t := UIJuice.tween_of(b)
		t.tween_interval(0.05 * i)
		t.tween_property(b, "modulate:a", 1.0, 0.12)
		t.parallel().tween_property(b, "position:x", 0.0, 0.25).from(-40.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for c : Control in [_header, _info]:
		c.modulate.a = 0.0
		UIJuice.tween_of(c).tween_property(c, "modulate:a", 1.0, 0.18)
	_title.pivot_offset = Vector2(0, 30)
	UIJuice.pop_in(_title, 0.0, 0.7)
	UIJuice.play(UIJuice.Sfx.OPEN)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	UIJuice.play(UIJuice.Sfx.CLOSE)
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_settings(show: bool) -> void:
	_main_page.visible = not show
	_settings_page.visible = show
	if _title != null:
		_title.text = "SETTINGS" if show else "PAUSE"


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
