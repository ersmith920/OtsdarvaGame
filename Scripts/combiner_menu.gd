# The Combiner's pause menu, built in code.
#   Left:   the player's guns. Click one to put it in the first slot; every gun that isn't the
#           same kind then grays out. Click a matching one to fill the second slot.
#   Middle: the two picks (click a pick to take it back out).
#   Right:  the gun they'll make, and the Combine button.
# Cancel (or Escape) closes it without combining.
class_name CombinerMenu
extends Control

signal closed

const TITLE_FONT := preload("res://Fonts/KHMenu-Bold.otf")
const BODY_FONT := preload("res://Fonts/KHMenu.otf")

const TILE_SIZE := 72
const TILE_GAP := 8
const GRID_COLUMNS := 4
const CARD_SIZE := Vector2(260, 470)
const CARD_PREVIEW := Vector2i(220, 130)
const PANEL_BG := Color(0.05, 0.05, 0.06, 0.94)
const EMPTY_BORDER := Color(0.4, 0.4, 0.42)
const HINT_COLOR := Color(0.65, 0.65, 0.68)
const GRAYED := Color(0.3, 0.3, 0.3, 0.8)
const DIM_COLOR := Color(0, 0, 0, 0.7)
const BUTTON_BG := Color(0.13, 0.13, 0.16, 0.95)

var combiner : Combiner

var _first : Gun
var _second : Gun
var _preview_gun : Gun   # the result shown on the right (not in the tree)

var _holder : Control
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
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Everything sits in one holder that's centered and scaled down to fit small screens.
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 18)
	_holder.add_child(_content)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 34)
	title.text = combiner.title if combiner != null else "Combiner"
	_content.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(columns)

	# ---- Left: the player's guns ----
	var left := _section(columns, "Your Weapons")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(GRID_COLUMNS * (TILE_SIZE + TILE_GAP) + 20, CARD_SIZE.y)
	left.add_child(scroll)
	var pad := MarginContainer.new()   # room for the tiles' glow
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", TILE_GAP)
	_grid.add_theme_constant_override("v_separation", TILE_GAP)
	pad.add_child(_grid)

	# ---- Middle: the two picks ----
	var middle := _section(columns, "Combine")
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 14)
	middle.add_child(pair)
	for i in 2:
		if i == 1:
			var plus := _label("+", 40, Color.WHITE, TITLE_FONT)
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.size_flags_vertical = Control.SIZE_EXPAND_FILL
			pair.add_child(plus)
		var slot := _card_frame()
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(_on_slot_input.bind(i))
		pair.add_child(slot)
		_slots.append(slot)
	_hint = _label("", 18, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_hint)

	# ---- Right: the result ----
	var right := _section(columns, "Result")
	_result = _card_frame()
	right.add_child(_result)
	_combine_button = _button("Combine")
	_combine_button.pressed.connect(_on_combine)
	right.add_child(_combine_button)

	var cancel := _button("Cancel")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size.x = 220
	cancel.pressed.connect(_close)
	_content.add_child(cancel)

	# Hover popup for the gun tiles.
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.top_level = true
	add_child(_tip)


func _section(parent: Control, header: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	var label := _label(header, 22, Color(0.85, 0.85, 0.88), TITLE_FONT)
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
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.42))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.set_content_margin_all(8)
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
	return button


# A card-sized frame (slot or result). Its border is set by _color_frame.
func _card_frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.set_content_margin_all(14)
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
	_combine_button.disabled = _first == null or _second == null
	_fit.call_deferred()


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
		var badge := _label(str(pick), 20, Color.WHITE, TITLE_FONT)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		tile.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		style.set_border_width_all(4)
	elif not _pickable(gun):
		tile.modulate = GRAYED

	tile.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS so the scroll wheel still reaches the list
	if _pickable(gun):
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
		var label := _label(empty_text, 18, HINT_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(label)
		_color_frame(frame, -1)
		return
	var card := GunCard.build(load(gun.scene_file_path), gun, note, CARD_PREVIEW)
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
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if gun == _first or gun == _second:
		_unpick(gun)
	elif _pickable(gun):
		if _first == null:
			_first = gun
		else:
			_second = gun
	_hide_tip(_tip_gun)
	_refresh()


func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_unpick(_first if index == 0 else _second)
		_refresh()


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
	if _first == null or _second == null:
		return
	var a := _first
	var b := _second
	_first = null
	_second = null
	_close()
	combiner.combine(a, b)


func _input(event: InputEvent) -> void:
	# Escape cancels; Tab and the pause menu stay shut while this is open.
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed(&"menu"):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _tip.visible:
		_place_tip()


func _close() -> void:
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.06, 0.95)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_tip.add_theme_stylebox_override("panel", style)

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
