# The Combiner's pause menu, built in code.
#   Left:   the player's guns. Click one to put it in the first slot; every gun that isn't the
#           same kind then grays out. Click a matching one to fill the second slot.
#   Middle: the two picks (click a pick to take it back out).
#   Right:  the gun they'll make, and the Combine button.
# Cancel (or Escape) closes it without combining.
#
# Feel (see UIJuice): the game blurs behind it, it pops in and out, tiles lift on hover, a
# picked gun flies from its tile into its slot, the result flips in, Combine pulses while it's
# ready, and combining bursts the result (a bigger jackpot burst for a Mythic).
class_name CombinerMenu
extends Control

signal closed

const TITLE_FONT := preload("res://Fonts/KHMenu-Bold.otf")
const BODY_FONT := preload("res://Fonts/KHMenu.otf")

const TILE_SIZE := 64
const TILE_GAP := 8
const TILE_GLOW_ROOM := 10   # space around the tile grid for glows and hover growth
const GRID_COLUMNS := 4
const CARD_PADDING := 10
## Size of the gun cards here (1 = full size, the gun store uses 0.5).
const CARD_SCALE := 0.55
## Every slot / result frame: one gun card plus padding (same size whatever is in it).
var CARD_SIZE := GunCard.get_size(CARD_SCALE) + Vector2(CARD_PADDING, CARD_PADDING) * 2.0
const HINT_WIDTH := 440.0
const TITLE_SIZE := 28
const HEADER_SIZE := 15
const HINT_SIZE := 15
const BUTTON_SIZE := Vector2(170, 38)
const BUTTON_FONT_SIZE := 18
const PANEL_GAP := 16
const PANEL_PADDING := 14
const PLUS_WIDTH := 30
const EMPTY_TEXT_SIZE := 14
const PANEL_BG := Color(0.05, 0.05, 0.06, 0.94)
const EMPTY_BORDER := Color(0.4, 0.4, 0.42)
const HINT_COLOR := Color(0.65, 0.65, 0.68)
const GRAYED := Color(0.3, 0.3, 0.3, 0.8)
const DIM_COLOR := Color(0, 0, 0, 0.55)
const BUTTON_BG := Color(0.13, 0.13, 0.16, 0.95)

var combiner : Combiner

var _first : Gun
var _second : Gun
var _preview_gun : Gun   # the result shown on the right (not in the tree)

var _holder : Control
var _dim : ColorRect
var _closing := false        # input is ignored (combining or closing)
var _close_started := false
var _content : VBoxContainer
var _grid : GridContainer
var _slots : Array[PanelContainer] = []
var _result : PanelContainer
var _combine_button : Button
var _hint : Label
var _tip : PanelContainer
var _tip_gun : Gun

var _hud_was_visible := true   # the player's HUD is hidden while the menu is open
var _was_paused := false
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_refresh()
	_fit.call_deferred()   # the layout's size never changes after this (only on window resize)
	_open_anim.call_deferred()

	_was_paused = get_tree().paused
	_prev_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	GameManager.choice_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := GameManager.player.get_node_or_null("HUD")   # a CanvasLayer
	if hud != null:
		_hud_was_visible = hud.visible
		hud.visible = false


# ======================================================================
# Building
# ======================================================================

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.material = UIJuice.blur_material()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Everything sits in one holder that's centered and scaled down to fit small screens.
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_holder.add_child(_content)

	var title := _label(combiner.title if combiner != null else "Combiner", TITLE_SIZE, Color.WHITE, TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	# Three panels side by side, all the same height, so their headers and their contents
	# line up: your weapons / the two picks / the result.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", PANEL_GAP)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(columns)

	# ---- Left: the player's guns ----
	var left := _panel(columns, "Your Weapons")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(GRID_COLUMNS * (TILE_SIZE + TILE_GAP) - TILE_GAP + 2 * TILE_GLOW_ROOM, CARD_SIZE.y)
	left.add_child(scroll)
	var pad := MarginContainer.new()   # room for the tiles' glow and hover lift
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, TILE_GLOW_ROOM)
	scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", TILE_GAP)
	_grid.add_theme_constant_override("v_separation", TILE_GAP)
	pad.add_child(_grid)

	# ---- Middle: the two picks ----
	var middle := _panel(columns, "Combine")
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 0)
	middle.add_child(pair)
	for i in 2:
		if i == 1:
			var plus := _label("+", 26, Color(1, 1, 1, 0.7), TITLE_FONT)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.custom_minimum_size = Vector2(PLUS_WIDTH, CARD_SIZE.y)
			pair.add_child(plus)
		var slot := _card_frame()
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(_on_slot_input.bind(i))
		pair.add_child(slot)
		_slots.append(slot)

	# ---- Right: the result ----
	var right := _panel(columns, "Result")
	_result = _card_frame()
	right.add_child(_result)

	# ---- Footer: the hint, then Cancel and Combine side by side ----
	_hint = _label("", HINT_SIZE, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Fixed size, so a longer hint never pushes the layout around.
	_hint.custom_minimum_size = Vector2(HINT_WIDTH, _hint.get_theme_font("font").get_height(HINT_SIZE))
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.clip_text = true
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_content.add_child(buttons)
	var cancel := _button("Cancel")
	cancel.pressed.connect(func() -> void:
		if not _closing:
			_close())
	buttons.add_child(cancel)
	_combine_button = _button("Combine")
	_combine_button.pressed.connect(_on_combine)
	buttons.add_child(_combine_button)

	# Hover popup for the gun tiles.
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.top_level = true
	add_child(_tip)


# A glass panel with a small header; returns the box its content goes in.
func _panel(parent: Control, header: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := UIJuice.glass_style(10, Color(1, 1, 1, 0.1), Color(0.03, 0.035, 0.05, 0.7))
	style.set_content_margin_all(PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var label := _label(header.to_upper(), HEADER_SIZE, Color(0.78, 0.8, 0.86), TITLE_FONT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


func _label(text: String, size_px: int, color: Color, font: Font = BODY_FONT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.42))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.set_content_margin_all(6)
		match state:
			"normal":
				style.bg_color = BUTTON_BG
				style.border_color = Color(0.55, 0.55, 0.6)
			"hover":
				style.bg_color = BUTTON_BG.lightened(0.15)
				style.border_color = Color(0.85, 0.85, 0.9)
			"pressed":
				style.bg_color = BUTTON_BG.lightened(0.3)
				style.border_color = Color.WHITE
			"disabled":
				style.bg_color = Color(BUTTON_BG.darkened(0.4), 0.8)
				style.border_color = Color(0.25, 0.25, 0.27)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UIJuice.hover_lift(button)
	return button


# A card-sized frame (slot or result). Its border is set by _color_frame.
func _card_frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.set_content_margin_all(CARD_PADDING)
	style.shadow_offset = Vector2.ZERO
	frame.add_theme_stylebox_override("panel", style)
	_color_frame(frame, -1)
	return frame


# rarity -1 = empty (gray, no glow). Mythic frames keep cycling through an animator.
func _color_frame(frame: PanelContainer, rarity: int) -> void:
	for child in frame.get_children():
		if child is RarityAnimator:
			(child as RarityAnimator).apply = Callable()   # stop it before it's freed
			child.queue_free()
	var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	Rarity.paint(frame, rarity)   # Mythic: rainbow border and glow (-1 clears it)
	if rarity < 0:
		style.border_color = EMPTY_BORDER
		style.bg_color = PANEL_BG
		style.shadow_size = 0
		return
	style.shadow_size = 14
	RarityAnimator.attach(frame, rarity, func(c: Color) -> void:
		style.border_color = c.lerp(Color.WHITE, 0.35)
		style.bg_color = PANEL_BG.lerp(c.darkened(0.6), 0.25)
		style.shadow_color = Color(c, 0.55))


# ======================================================================
# State
# ======================================================================

func _player_guns() -> Array[Gun]:
	var guns : Array[Gun] = []
	for slot in GameManager.player.gun_slots:
		if slot.get_child_count() > 0 and slot.get_child(0) is Gun:
			guns.append(slot.get_child(0) as Gun)
	return guns


static func _same_kind(a: Gun, b: Gun) -> bool:
	return a.scene_file_path == b.scene_file_path


# Can this gun be clicked right now?
func _pickable(gun: Gun) -> bool:
	if gun == _first or gun == _second or not WeaponRollTable.can_combine(gun):
		return false
	if _first != null and not _same_kind(gun, _first):
		return false
	return true


func _refresh() -> void:
	_rebuild_grid()
	for i in 2:
		var gun := _first if i == 0 else _second
		_fill_frame(_slots[i], gun, "", "Empty\n\nPick a weapon\nfrom the left" if i == 0 \
				else "Empty\n\nPick another\nof the same weapon")
	_rebuild_result()

	if _first == null:
		_hint.text = "Pick two of the same weapon"
	elif _second == null:
		var any := _player_guns().any(func(g: Gun) -> bool: return _pickable(g))
		_hint.text = ("Pick another %s" if any else "You have no other %s to combine") % _first.get_display_name()
	else:
		_hint.text = "Click a weapon to take it back out"
	var ready := _first != null and _second != null
	if ready and _combine_button.disabled:
		UIJuice.pulse(_combine_button)   # waiting to be pressed
	elif not ready:
		UIJuice.stop_pulse(_combine_button)
	_combine_button.disabled = not ready


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for gun in _player_guns():
		_grid.add_child(_make_tile(gun))


func _make_tile(gun: Gun) -> Control:
	var rarity := gun.get_rarity()
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.shadow_size = 10
	style.shadow_offset = Vector2.ZERO
	tile.add_theme_stylebox_override("panel", style)
	RarityAnimator.attach(tile, rarity, func(c: Color) -> void:
		style.bg_color = Color(c.darkened(0.8), 0.5)
		style.border_color = c.lerp(Color.WHITE, 0.6)
		style.shadow_color = Color(c, 0.6))
	Rarity.paint(tile, rarity)

	if gun.icon != null:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = gun.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	else:
		var preview := GunPreview.create(load(gun.scene_file_path), Vector2i(TILE_SIZE - 8, TILE_SIZE - 8), 0.0)
		tile.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)

	# Picked guns show which slot they're in; guns that can't be picked are grayed out.
	var pick := 1 if gun == _first else (2 if gun == _second else 0)
	if pick > 0:
		var badge := _label(str(pick), 16, Color.WHITE, TITLE_FONT)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		tile.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		style.set_border_width_all(4)
	elif not _pickable(gun):
		tile.modulate = GRAYED

	tile.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS so the scroll wheel still reaches the list
	if _pickable(gun) or pick > 0:
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UIJuice.hover_lift(tile)
	tile.set_meta(&"gun", gun)
	tile.gui_input.connect(_on_tile_input.bind(gun))
	tile.mouse_entered.connect(_show_tip.bind(gun))
	tile.mouse_exited.connect(_hide_tip.bind(gun))
	return tile


# Puts a gun card in a frame, or the empty text.
func _fill_frame(frame: PanelContainer, gun: Gun, note: String, empty_text: String) -> void:
	for child in frame.get_children():
		if not (child is RarityAnimator):
			frame.remove_child(child)
			child.queue_free()
	if gun == null:
		var label := _label(empty_text, EMPTY_TEXT_SIZE, HINT_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(label)
		_color_frame(frame, -1)
		return
	var card := GunCard.build(load(gun.scene_file_path), gun, note, CARD_SCALE)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_mouse(card)
	frame.add_child(card)
	_color_frame(frame, gun.get_rarity())


func _rebuild_result() -> void:
	if _preview_gun != null:
		_preview_gun.free()
		_preview_gun = null
	if _first == null or _second == null:
		_fill_frame(_result, null, "", "The combined\nweapon shows here")
		return
	_preview_gun = (load(_first.scene_file_path) as PackedScene).instantiate() as Gun
	_preview_gun.apply_roll(combiner.roll_table.combine(_preview_gun, _first.roll, _second.roll, false))
	_fill_frame(_result, _preview_gun, WeaponRollTable.combine_note(_first.roll, _second.roll), "")


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


# Centers the menu and shrinks it if the screen is too small for it.
func _fit() -> void:
	var need := _content.get_combined_minimum_size()
	_content.size = need
	var avail := size * 0.96
	var s := minf(1.0, minf(avail.x / maxf(need.x, 1.0), avail.y / maxf(need.y, 1.0)))
	_holder.scale = Vector2(s, s)
	_holder.position = ((size - need * s) * 0.5).floor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _content != null:
		_fit()


# ======================================================================
# Input
# ======================================================================

func _on_tile_input(event: InputEvent, gun: Gun) -> void:
	if _closing or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var had_both := _first != null and _second != null
	var fly_to := -1
	var from_rect := Rect2()
	if gun == _first or gun == _second:
		_unpick(gun)
	elif _pickable(gun):
		fly_to = 0 if _first == null else 1
		from_rect = _tile_rect(gun)
		if _first == null:
			_first = gun
		else:
			_second = gun
	_hide_tip(_tip_gun)
	_refresh()
	if fly_to >= 0:
		_fly_into_slot(gun, from_rect, fly_to)
	if not had_both and _first != null and _second != null:
		UIJuice.flip_in(_result, 0.22)   # both picked: the result turns over
		UIJuice.play(UIJuice.Sfx.PICK, 0.9)


func _on_slot_input(event: InputEvent, index: int) -> void:
	if _closing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if (_first if index == 0 else _second) == null:
			return
		_unpick(_first if index == 0 else _second)
		_refresh()
		UIJuice.punch(_slots[index], -0.05)
		UIJuice.play(UIJuice.Sfx.CLOSE, 1.3)


# Where a gun's tile is on screen right now.
func _tile_rect(gun: Gun) -> Rect2:
	for tile in _grid.get_children():
		if tile.get_meta(&"gun", null) == gun:
			return (tile as Control).get_global_rect()
	return Rect2()


# A copy of the gun's tile flies from where it was into the slot, then the slot's card pops in.
func _fly_into_slot(gun: Gun, from_rect: Rect2, slot_index: int) -> void:
	var slot := _slots[slot_index]
	var card := slot.get_child(slot.get_child_count() - 1) as Control
	if card != null:
		UIJuice.pop_in(card, 0.16, 0.85)
	if from_rect.size == Vector2.ZERO:
		return
	var ghost := _make_tile(gun)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.top_level = true
	ghost.modulate = Color.WHITE
	add_child(ghost)
	ghost.global_position = from_rect.position
	ghost.scale = _holder.scale
	var to_rect := slot.get_global_rect()
	var target := to_rect.get_center() - from_rect.size * 0.5
	var t := UIJuice.tween_of(ghost)
	t.set_parallel(true)
	t.tween_property(ghost, "global_position", target, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(ghost, "scale", _holder.scale * 1.5, 0.2)
	t.tween_property(ghost, "modulate:a", 0.0, 0.12).set_delay(0.12)
	t.chain().tween_callback(func() -> void:
		ghost.queue_free()
		UIJuice.flash(slot, 0.5))


# Takes a pick back out. Taking out the first moves the second up into its place.
func _unpick(gun: Gun) -> void:
	if gun == null:
		return
	if gun == _first:
		_first = _second
		_second = null
	elif gun == _second:
		_second = null


func _on_combine() -> void:
	if _closing or _first == null or _second == null:
		return
	var a := _first
	var b := _second
	_closing = true
	UIJuice.stop_pulse(_combine_button)
	# Payoff: the result flashes and bursts; a Mythic gets a jackpot (bigger, longer, sparks
	# from both inputs too, and the card swells as it's revealed).
	var rarity := _preview_gun.get_rarity() if _preview_gun != null else Rarity.COMMON
	var color := Rarity.get_color(rarity)
	var center := _result.get_global_rect().get_center()
	UIJuice.flash(_result, 0.8 + rarity * 0.2)
	var hold := 0.5
	if rarity >= Rarity.MYTHIC:
		hold = 1.1
		UIJuice.play(UIJuice.Sfx.JACKPOT)
		for slot in _slots:
			UIJuice.burst(self, slot.get_global_rect().get_center(), color, Rarity.LEGENDARY, 0.8)
		var t := UIJuice.tween_of(_result)
		UIJuice.center_pivot(_result)
		t.tween_property(_result, "scale", Vector2.ONE * 1.12, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_callback(UIJuice.burst.bind(self, center, color, Rarity.MYTHIC, 1.6))
		t.tween_property(_result, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		UIJuice.play(UIJuice.Sfx.REWARD if rarity >= Rarity.EPIC else UIJuice.Sfx.PICK)
		UIJuice.punch(_result, 0.1)
		UIJuice.burst(self, center, color, rarity, 1.2)
	for slot in _slots:
		UIJuice.pop_out(slot)
	get_tree().create_timer(hold, true, false, true).timeout.connect(func() -> void:
		_first = null
		_second = null
		_close(func() -> void: combiner.combine(a, b)))


func _input(event: InputEvent) -> void:
	# Escape cancels; Tab and the pause menu stay shut while this is open.
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if not _closing:
			_close()
	elif event.is_action_pressed(&"menu"):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _tip.visible:
		_place_tip()


func _open_anim() -> void:
	(_dim.material as ShaderMaterial).set_shader_parameter(&"amount", 0.0)
	UIJuice.fade_backdrop(_dim, 1.0, 0.2)
	UIJuice.pop_in(_content, 0.0, 0.92, 0.22)
	UIJuice.play(UIJuice.Sfx.OPEN)


# Animates out, then closes (and runs after_close, e.g. the actual combine).
func _close(after_close := Callable()) -> void:
	if not is_inside_tree() or _close_started:
		return
	_close_started = true
	_closing = true
	_tip.visible = false
	UIJuice.fade_backdrop(_dim, 0.0, 0.16)
	if not after_close.is_valid():
		UIJuice.play(UIJuice.Sfx.CLOSE)
	UIJuice.pop_out(_content, func() -> void:
		_finish_close()
		if after_close.is_valid():
			after_close.call())


func _finish_close() -> void:
	if not is_inside_tree():
		return
	if _preview_gun != null:
		_preview_gun.free()
		_preview_gun = null
	get_tree().paused = _was_paused
	GameManager.choice_open = false
	if GameManager.player != null:
		var hud := GameManager.player.get_node_or_null("HUD")
		if hud != null:
			hud.visible = _hud_was_visible
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()
	queue_free()


# ======================================================================
# Hover popup
# ======================================================================

func _show_tip(gun: Gun) -> void:
	_tip_gun = gun
	for child in _tip.get_children():
		_tip.remove_child(child)
		child.queue_free()
	_tip.add_theme_stylebox_override("panel", UIJuice.glass_style(6, Color(1, 1, 1, 0.14), Color(0.04, 0.045, 0.06, 0.94)))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_tip.add_child(column)
	var name_label := _label("", 20, Color.WHITE, TITLE_FONT)
	column.add_child(name_label)
	column.add_child(_label(Rarity.name_of(gun.get_rarity()), 15, Color(0.85, 0.85, 0.85)))
	var lit : Array[Label] = []
	for stat in gun.get_stat_summary():
		var line : String = "%s: %s" % [stat.name, stat.value]
		if not stat.bonus.is_empty():
			line += "  (%s)" % stat.bonus
		var label := _label(line, 15, Color(0.6, 0.6, 0.6))
		column.add_child(label)
		if stat.boosted:
			lit.append(label)
	if not WeaponRollTable.can_combine(gun):
		column.add_child(_label("Mythic weapons can't be combined", 15, HINT_COLOR))
	var display_name := gun.get_display_name()
	RarityAnimator.attach(column, gun.get_rarity(), func(c: Color) -> void:
		TextGlow.set_text(name_label, display_name, c)
		var boost := c.lerp(Color.WHITE, 0.45)
		for label in lit:
			label.add_theme_color_override("font_color", boost))
	for item in [name_label] + lit:
		Rarity.paint(item, gun.get_rarity())
	_tip.reset_size()
	_tip.visible = true
	_place_tip()


func _hide_tip(gun: Gun) -> void:
	if gun == _tip_gun:
		_tip.visible = false
		_tip_gun = null


func _place_tip() -> void:
	_tip.reset_size()
	var pos := get_global_mouse_position() + Vector2(18, 18)
	var view := get_viewport_rect().size
	pos.x = minf(pos.x, view.x - _tip.size.x - 8.0)
	pos.y = minf(pos.y, view.y - _tip.size.y - 8.0)
	_tip.position = pos
