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
	# KH2-style layout: a "SYSTEM PAUSED" header across the top left, a column of command buttons
	# down the left side, and a mission info panel (time, scrap) bottom right.
	var header := Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 90
	header.draw.connect(func() -> void:
		# A dark band fading out to the right, with a hairline under it.
		var w := header.size.x
		header.draw_polygon(PackedVector2Array([Vector2(0, 20), Vector2(w, 20), Vector2(w, 72), Vector2(0, 72)]),
				PackedColorArray([Color(HudStyle.PANEL_TOP, 0.85), Color(HudStyle.PANEL_TOP, 0.0),
				Color(HudStyle.PANEL_BOTTOM, 0.0), Color(HudStyle.PANEL_BOTTOM, 0.85)]))
		header.draw_rect(Rect2(0, 72, w * 0.6, 1), Color(HudStyle.CYAN, 0.6))
		header.draw_rect(Rect2(60, 71, 80, 3), HudStyle.CYAN))
	_header = header
	_title = HudStyle.make_label("SYSTEM PAUSED", 30, HudStyle.PHOSPHOR, true)
	_title.add_theme_font_override("font", HudStyle.spaced(HudStyle.NUMBER_FONT, 4))
	HudStyle.add_phosphor(_title, HudStyle.PHOSPHOR, 0.35)
	_title.position = Vector2(60, 22)
	header.add_child(_title)

	_main_page = _make_window()
	_main_page.add_child(_make_button("Resume", _resume))
	_main_page.add_child(_make_button("Settings", func(): _show_settings(true)))
	_main_page.add_child(_make_button("Exit", _on_exit_pressed))

	_settings_page = _make_window(true)
	_settings_page.visible = false
	_add_slider_row("Mouse Sensitivity", SENS_DISPLAY_MIN, SENS_DISPLAY_MAX, SENS_DISPLAY_STEP,
		GameManager.mouse_sensitivity * SENS_DISPLAY_SCALE, _on_sensitivity_changed, "%.1f")
	_add_slider_row("Master Volume", 0.0, 100.0, 1.0,
		GameManager.master_volume * 100.0, _on_volume_changed, "%d%%")
	_settings_page.add_child(_make_button("Back", func(): _show_settings(false)))

	# Mission info, bottom right (like KH's time / munny box): one panel, two rows.
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
		HudStyle.draw_panel(_info, r)
		HudStyle.draw_divider(_info, Vector2(12, r.size.y * 0.5), r.size.x - 24))
	for i in 2:
		var cap := HudStyle.make_caption(["TIME", "SCRAP"][i], 11)
		cap.position = Vector2(18, 12 + 37 * i)
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


# A column of buttons down the left side, centered vertically. panel: draws a HUD panel
# behind the column (the settings page, whose rows would otherwise float).
func _make_window(panel := false) -> VBoxContainer:
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
	frame.add_theme_constant_override("margin_right", 26)   # room for a lit button's slide
	holder.add_child(frame)
	if panel:
		frame.draw.connect(func() -> void: HudStyle.draw_panel(frame, Rect2(Vector2.ZERO, frame.size)))
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", button_gap)
	frame.add_child(page)
	page.visibility_changed.connect(func() -> void: holder.visible = page.visible)
	return page


# A command button (HudStyle.make_button): left-aligned, nudges right when hovered.
func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := HudStyle.make_button(text, Vector2(button_size.x, minf(button_size.y, 46.0)),
			roundi(font_size * 0.75), HudStyle.CYAN, true, HORIZONTAL_ALIGNMENT_LEFT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(on_pressed)
	return button


func _make_label(text: String) -> Label:
	var l := HudStyle.make_label(text.to_upper(), roundi(font_size * 0.6), HudStyle.WHITE)
	l.add_theme_font_override("font", HudStyle.spaced(HudStyle.LABEL_FONT, 2))
	return l


# A small white square for the slider grabbers.
static func _grabber_texture() -> Texture2D:
	var img := Image.create(10, 14, false, Image.FORMAT_RGBA8)
	img.fill(HudStyle.WHITE)
	return ImageTexture.create_from_image(img)




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
		_title.text = "SYSTEM CONFIG" if show else "SYSTEM PAUSED"


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
	# Thin track, accent fill, small square grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.01, 0.03, 0.8)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudStyle.CYAN
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grab := _grabber_texture()
	slider.add_theme_icon_override("grabber", grab)
	slider.add_theme_icon_override("grabber_highlight", grab)
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
