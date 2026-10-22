# Pause menu. Escape toggles it; it really pauses the tree.
# Drawn as one old terminal screen (TermFrame): the game blurred and darkened behind it, an
# inverted title bar with the mission clock, scrap and hostiles, a COMMAND window of options
# down the left, a SYSTEM STATUS window on the right (a readout table, live oscilloscope
# traces and a sync meter), and key hints along the bottom. Opening powers the screen on
# like a CRT and types the text in; resuming powers it off.
# Settings swap the COMMAND window for a CONFIG window (sensitivity, volume, back).
extends Control

@export_group("Background")
## Color and opacity of the layer over the blurred game. Alpha controls how strong it is.
@export var tint_color := Color(0.02, 0.006, 0.0, 0.72)
## How blurry the game behind the menu is. 0 = sharp.
@export_range(0.0, 6.0, 0.1) var blur_amount := 2.5

@export_group("Buttons")
@export var font: Font   # unused now: buttons use HudStyle's terminal font (kept so the scene still loads)
@export var font_size := 28
@export var button_size := Vector2(300, 44)
@export var button_gap := 10

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 2.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.5);

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	// Pushed toward amber monochrome, like the game seen on a terminal behind the text.
	float l = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(l * 1.0, l * 0.55, l * 0.2), 0.6);
	COLOR = vec4(mix(col, tint.rgb, tint.a), 1.0);
}
"""

# The slider shows sensitivity x1000 (0.008 is stored, 8.0 is displayed).
const SENS_DISPLAY_SCALE := 1000.0
const SENS_DISPLAY_MIN := 1.0
const SENS_DISPLAY_MAX := 20.0
const SENS_DISPLAY_STEP := 0.1

const LEFT_X := 70.0
const STATUS_WIDTH := 430.0

var _screen: Control          # everything that powers on / off (not the blurred backdrop)
var _frame: TermFrame
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _main_window: Control
var _settings_window: Control
var _status_window: Control
var _rows := {}               # status row name -> its value Label
var _meter: Control
var _closing := false


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
	theme = HudStyle.menu_theme()

	_build_background()
	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = TermFrame.new()
	_frame.title = "SYSTEM PAUSED"
	_frame.hints = "[ESC] RESUME     [LMB] SELECT"
	_screen.add_child(_frame)
	_build_pages()
	_build_status()
	HudStyle.add_menu_bloom(self)   # CRT bloom, fringe and scanlines over the screen
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
	_main_window = _make_window("Command", "3 OPT")
	_main_page = _main_window.get_meta(&"body")
	_main_page.add_theme_constant_override("separation", button_gap)
	_main_page.add_child(_make_button("Resume", _resume))
	_main_page.add_child(_make_button("Settings", func(): _show_settings(true)))
	_main_page.add_child(_make_button("Exit", _on_exit_pressed))
	var note := TermUI.label("> AWAITING INPUT", 12, HudStyle.ORANGE_DIM)
	_main_page.add_child(note)

	_settings_window = _make_window("Config", "SYS.CFG")
	_settings_page = _settings_window.get_meta(&"body")
	_settings_page.add_theme_constant_override("separation", 14)
	_add_slider_row("Mouse Sensitivity", SENS_DISPLAY_MIN, SENS_DISPLAY_MAX, SENS_DISPLAY_STEP,
		GameManager.mouse_sensitivity * SENS_DISPLAY_SCALE, _on_sensitivity_changed, "%04.1f")
	_add_slider_row("Master Volume", 0.0, 100.0, 1.0,
		GameManager.master_volume * 100.0, _on_volume_changed, "%03d%%")
	_settings_page.add_child(_make_button("Back", func(): _show_settings(false)))
	_settings_window.visible = false


# A window on the left, centered vertically.
func _make_window(title: String, value: String) -> Control:
	var window := HudStyle.make_window(title, value)
	window.custom_minimum_size.x = button_size.x + 40.0
	_screen.add_child(window)
	window.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	window.offset_left = LEFT_X
	window.resized.connect(func() -> void:
		window.offset_top = -window.size.y * 0.5
		window.offset_bottom = window.size.y * 0.5)
	return window


# The status window on the right: a readout table, oscilloscope traces and a sync meter.
func _build_status() -> void:
	_status_window = HudStyle.make_window("System Status", "LIVE", HudStyle.ORANGE)
	_status_window.custom_minimum_size.x = STATUS_WIDTH
	_screen.add_child(_status_window)
	_status_window.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_status_window.offset_right = -LEFT_X
	_status_window.offset_left = -LEFT_X - STATUS_WIDTH
	_status_window.resized.connect(func() -> void:
		_status_window.offset_top = -_status_window.size.y * 0.5
		_status_window.offset_bottom = _status_window.size.y * 0.5)
	var body : VBoxContainer = _status_window.get_meta(&"body")
	body.add_theme_constant_override("separation", 6)
	for row_name in ["Mission Time", "Scrap", "Hostiles", "Items Held", "Arms Mounted", "Reactor"]:
		var row := TermUI.leader_row(row_name.to_upper(), "--", 14,
				HudStyle.ORANGE, HudStyle.GOLD if row_name == "Scrap" else HudStyle.WHITE)
		body.add_child(row)
		_rows[row_name] = row.get_meta(&"value")
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	body.add_child(gap)
	body.add_child(TermUI.label("BIO-MONITOR  /  PILOT LINK", 12, HudStyle.ORANGE_DIM))
	body.add_child(TermUI.make_scope(96.0))
	var sync_row := HBoxContainer.new()
	sync_row.add_theme_constant_override("separation", 10)
	sync_row.add_child(TermUI.label("SYNC", 12, HudStyle.ORANGE_DIM))
	_meter = TermUI.make_meter(28, HudStyle.GREEN, 10.0)
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sync_row.add_child(_meter)
	body.add_child(sync_row)


# A command (HudStyle.make_button): left-aligned, nudges right when hovered.
func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := HudStyle.make_button(text, button_size, 18, HudStyle.ORANGE, true, HORIZONTAL_ALIGNMENT_LEFT)
	button.size_flags_horizontal = Control.SIZE_FILL
	button.pressed.connect(func() -> void:
		if not _closing:
			on_pressed.call())
	return button


# ---------- Input ----------

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()

	if visible:
		if _closing:
			return
		if _settings_window.visible:
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


func _process(_delta: float) -> void:
	if visible:
		_update_status()


# ---------- Pause / resume ----------

func _pause() -> void:
	_closing = false
	_show_settings(false, false)
	get_parent().move_child(self, -1)   # over every HUD element
	visible = true
	_update_status()
	# The screen powers on, the frame traces itself, then the text types in.
	TermUI.power_on(_screen)
	_frame.boot(0.12)
	for w : Control in [_main_window, _status_window]:
		w.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.22)
	t.tween_callback(func() -> void:
		_main_window.modulate.a = 1.0
		TermUI.type_tree(_main_window, 0.0))
	t.tween_interval(0.12)
	t.tween_callback(func() -> void:
		_status_window.modulate.a = 1.0
		TermUI.type_tree(_status_window, 0.0, TermUI.TYPE_SPEED * 2.0, 0.015))
	for b in _main_page.get_children():
		if b is Button:
			b.set_meta(&"lit", 0.0)
			b.get_child(0).queue_redraw()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	if _closing:
		return
	_closing = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	TermUI.power_off(_screen, func() -> void:
		visible = false
		_closing = false
		_screen.scale = Vector2.ONE
		_screen.modulate = Color.WHITE)


func _show_settings(show: bool, animate := true) -> void:
	_main_window.visible = not show
	_settings_window.visible = show
	_frame.title = "SYSTEM CONFIG" if show else "SYSTEM PAUSED"
	_frame.hints = "[ESC] BACK     [LMB] SELECT     [DRAG] ADJUST" if show else "[ESC] RESUME     [LMB] SELECT"
	if animate and visible:
		var w := _settings_window if show else _main_window
		TermUI.type_tree(w, 0.0)
		UIJuice.play(UIJuice.Sfx.OPEN if show else UIJuice.Sfx.CLOSE, 1.2)


func _on_exit_pressed() -> void:
	get_tree().quit()


# Live numbers in the title bar and the status window.
func _update_status() -> void:
	var secs := int(GameManager.levelTime)
	@warning_ignore("integer_division")
	var clock := "%02d:%02d" % [secs / 60, secs % 60]
	var player := GameManager.player
	var scrap := player.gold if player != null else 0
	var hostiles := EnemyManager.get_total_count()
	var items := 0
	var guns := 0
	var slots := 0
	if player != null:
		for item in player.inventory:
			items += player.inventory[item]
		slots = player.gun_slots.size()
		for slot in player.gun_slots:
			if slot.get_child_count() > 0 and slot.get_child(0) is Gun:
				guns += 1
	_frame.status = ["T+" + clock, "SCRAP %d" % scrap, "HOSTILE %d" % hostiles]
	var reactor := 412.0 + 6.0 * sin(Time.get_ticks_msec() / 900.0)
	var values := {"Mission Time": clock, "Scrap": str(scrap), "Hostiles": "%04d" % hostiles,
			"Items Held": "%03d" % items, "Arms Mounted": "%d/%d" % [guns, slots], "Reactor": "%.1fK" % reactor}
	for key in values:
		var l : Label = _rows[key]
		if l.visible_characters == -1 or l.text == "--":
			l.text = values[key]
	_meter.set_meta(&"value", 0.88 + 0.08 * sin(Time.get_ticks_msec() / 700.0))
	_meter.queue_redraw()


# ---------- Settings ----------
# One settings row: name over a segmented slider with its live value.
func _add_slider_row(label_text: String, min_v: float, max_v: float, step: float,
		value: float, on_change: Callable, format: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_settings_page.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := TermUI.label(label_text.to_upper(), 13, HudStyle.ORANGE, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := TermUI.label("", 16, HudStyle.WHITE)
	value_label.add_theme_font_override("font", HudStyle.READOUT_FONT)
	value_label.set_meta(TermUI.NO_TYPE, true)
	head.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(button_size.x, 18)
	slider.focus_mode = Control.FOCUS_NONE
	# The look is drawn by a child: a row of segments, lit up to the value.
	for key in ["slider", "grabber_area", "grabber_area_highlight"]:
		slider.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	var blank := ImageTexture.create_from_image(Image.create(14, 18, false, Image.FORMAT_RGBA8))
	slider.add_theme_icon_override("grabber", blank)
	slider.add_theme_icon_override("grabber_highlight", blank)
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_behind_parent = true
	slider.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, bar.size)
		var k := inverse_lerp(slider.min_value, slider.max_value, slider.value)
		var n := 30
		var w := r.size.x / n
		for i in n:
			var on := (i + 0.5) / n <= k
			bar.draw_rect(Rect2(i * w + 1.0, 3.0, w - 3.0, r.size.y - 6.0), HudStyle.ORANGE if on else Color(HudStyle.ORANGE, 0.14))
		var x := r.size.x * k
		bar.draw_rect(Rect2(x - 2.0, 0, 4.0, r.size.y), HudStyle.WHITE))
	box.add_child(slider)

	var update_text := func(v: float) -> void:
		value_label.text = format % v
		bar.queue_redraw()
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		update_text.call(v)
		UIJuice.play(UIJuice.Sfx.TYPE, 0.8 + 0.6 * inverse_lerp(min_v, max_v, v)))
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
