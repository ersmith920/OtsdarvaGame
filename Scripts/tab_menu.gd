# Hold-Tab menu. Opens while the "menu" action is held, closes the instant it's released.
# Look: the HUD style (HudStyle): one see-through HUD panel split into three columns by
# hairlines, letter-spaced section headers, HUD tiles glowing in their tier color (they lift
# when hovered), HUD buttons and toggles, and a tooltip framed in the hovered thing's color.
# The columns deal in when it opens.
extends Control

const EDGE_MARGIN := 0.03   # fraction of the screen left clear on each side
const BOX_COLOR := Color(0.1, 0.1, 0.1, 0.2)   # 20% opacity lives in the box color only

## Put future menu elements inside these columns (or in `content` itself).
var content: MarginContainer
var left_column: Control
var middle_column: Control
var right_column: Control   # holds the stats list

var _stat_list: VBoxContainer
var _stat_value_labels := {}   # stat name -> Label showing its value
var _pause_toggle: CheckButton
var _item_scroll: ScrollContainer
var _item_grid: GridContainer
var _weapon_scroll: ScrollContainer
var _weapon_quads: GridContainer   # 2 x 2: Upper L. / Upper R. / Lower L. / Lower R.
var _weapon_tiles: Array[Control] = []   # one per gun slot (empty or not)
var _swapped_slots: Array = []   # slots just changed by a drop (their tiles pop when rebuilt)
var _drop_target: Control        # tile lit up under a dragged gun
var _tip: PanelContainer
var _tip_name: Label
var _tip_desc: Label
var _tip_stats: VBoxContainer   # weapon stats, one Label per line (rolled ones in the rarity color)
var _hovered: Object   # the ItemData or Gun under the cursor

const ITEM_COLUMNS := 4
const ITEM_TILE_SIZE := 72     # 32x32 icon at 2x (64) plus 4px padding on each side
const ITEM_TILE_GAP := 8
const TIP_OFFSET := Vector2(18, 18)   # hover popup distance from the cursor
const TIP_PADDING := 12
const TIP_MAX_TEXT_WIDTH := 320.0
const HUD_CLEARANCE := 16.0   # gap kept between the menu and the HUD elements it avoids
const COLUMN_PADDING := 24   # horizontal padding inside the middle column (put with the other constants)

const TILE_GLOW_SIZE := 6         # room around the tile grids for the tiles' glow and hover lift, in px


var _box: Panel
var _columns: HBoxContainer
var _tip_style: HudPanelStyle
var _hover_tile: Control       # item / weapon tile under the cursor (lifted)
var _last_values := {}         # stat name -> last shown value (changes flash)

@export var name_font: Font = preload("res://Fonts/KHMenu-Bold.otf")
@export var description_font: Font = preload("res://Fonts/KHMenu.otf")
@export var tip_name_font_size := 20
@export var tip_description_font_size := 15
@export var tip_description_color := Color(0.85, 0.85, 0.85)
## Unused now: the tooltip and headers use HudStyle (kept so scenes that set them still load).
@export var tip_box_color := Color(0.06, 0.06, 0.06, 0.95)
@export var section_header_font_size := 18
@export var section_header_color := Color(0.8, 0.8, 0.8)
## Weapon tooltips: color of the stat lines (the gun's stats with its rolls applied).
@export var tip_base_stat_color := Color(0.6, 0.6, 0.6)

func _ready() -> void:
	# Register the action in code if it isn't in the Input Map yet.
	if not InputMap.has_action(&"menu"):
		InputMap.add_action(&"menu")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_TAB
		InputMap.action_add_event(&"menu", key)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	theme = HudStyle.menu_theme()

	var box := Panel.new()
	box.anchor_left = EDGE_MARGIN
	box.anchor_top = EDGE_MARGIN
	box.anchor_right = 1.0 - EDGE_MARGIN
	box.anchor_bottom = 1.0 - EDGE_MARGIN
	box.offset_left = 0
	box.offset_top = 0
	box.offset_right = 0
	box.offset_bottom = 0
	# HUD panel, kept see-through: the game keeps running behind the Tab menu.
	box.add_theme_stylebox_override("panel", HudStyle.panel_style(HudStyle.CYAN, 0.0, 0.6))
	add_child(box)
	_box = box

	content = MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		content.add_theme_constant_override("margin_" + side, 18)
	for side in ["top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 12)
	box.add_child(content)

	# Three equal-width columns.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 0)
	content.add_child(columns)
	_columns = columns
	# Hairlines between the columns.
	columns.draw.connect(func() -> void:
		for i in range(1, columns.get_child_count()):
			var x := (columns.get_child(i) as Control).position.x
			columns.draw_rect(Rect2(x, 0, 1, columns.size.y), HudStyle.PANEL_EDGE)
			columns.draw_rect(Rect2(x - 1, 0, 3, 24), Color(HudStyle.CYAN, 0.7)))
	left_column = _make_column(columns)
	middle_column = _make_column(columns)
	right_column = _make_column(columns)

	_build_stats_panel()
	_build_buttons_panel()
	_build_items_panel()
	_build_item_tooltip()

# A plain Control with zero minimum size, so all three columns stay exactly equal
# no matter what ends up inside them.
func _make_column(parent: Control) -> Control:
	var column := Control.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	column.clip_contents = true
	parent.add_child(column)
	return column


# ---------- Stats list (right column) ----------

func _build_stats_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", COLUMN_PADDING)
	right_column.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(HudStyle.make_header("Stats", 13))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	_stat_list = VBoxContainer.new()
	_stat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_stat_list)


# One row per stat: name on the left, value on the right.
func _rebuild_stat_rows() -> void:
	for child in _stat_list.get_children():
		child.queue_free()
	_stat_value_labels.clear()

	_last_values.clear()
	var index := 0
	for stat_name in GameManager.player.stats_node.stats:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 26
		# Faint stripe on every other row, so long lists stay easy to read across.
		if index % 2 == 0:
			row.draw.connect(func() -> void: row.draw_rect(Rect2(Vector2.ZERO, row.size), Color(HudStyle.CYAN, 0.05)))
		index += 1

		var name_label := HudStyle.make_label(String(stat_name).capitalize(), 15, Color(HudStyle.WHITE, 0.75))   # "max_health" -> "Max Health"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		var value_label := HudStyle.make_label("", 16, HudStyle.WHITE, true)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.custom_minimum_size.x = 70
		row.add_child(value_label)
		var pad := Control.new()
		pad.custom_minimum_size.x = 8
		row.add_child(pad)

		_stat_list.add_child(row)
		_stat_value_labels[stat_name] = value_label


func _update_stat_values() -> void:
	var stats_node := GameManager.player.stats_node
	for stat_name in _stat_value_labels:
		var value: float = stats_node.get_value(stat_name)
		var label := _stat_value_labels[stat_name] as Label
		label.text = str(snappedf(value, 0.01))
		# A stat that changed while the menu is open pops and flashes (green up, red down).
		if _last_values.has(stat_name) and not is_equal_approx(_last_values[stat_name], value):
			var up : bool = value > _last_values[stat_name]
			label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if up else HudStyle.RED)
			label.pivot_offset = Vector2(label.size.x, label.size.y * 0.5)
			UIJuice.punch(label, 0.2)
			UIJuice.tween_of(label).tween_method(func(c: Color) -> void:
				label.add_theme_color_override("font_color", c),
				Color(0.5, 1.0, 0.6) if up else HudStyle.RED, HudStyle.WHITE, 0.6)
		_last_values[stat_name] = value

# ---------- Buttons (middle column) ----------

func _build_buttons_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", COLUMN_PADDING)
	margin.add_theme_constant_override("margin_right", COLUMN_PADDING)
	middle_column.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	margin.add_child(list)
	list.add_child(HudStyle.make_header("Dev tools", 13))

	_pause_toggle = CheckButton.new()
	_pause_toggle.text = "PAUSE TIMER"
	_pause_toggle.add_theme_font_size_override("font_size", 13)
	# No keyboard focus: otherwise clicking it once would make Space (your jump key)
	# toggle it every time you jump. Mouse clicks still work.
	_pause_toggle.focus_mode = Control.FOCUS_NONE
	_pause_toggle.toggled.connect(_on_pause_toggled)
	list.add_child(_pause_toggle)

	list.add_child(_dev_button("Spawn 25 Minors", _on_spawn_minors_pressed))

	list.add_child(_dev_button("Spawn 1000 Minors", _on_spawn_many_minors_pressed.bind(1000)))

	list.add_child(_dev_button("Spawn 25 Majors", _on_spawn_majors_pressed))

	list.add_child(_dev_button("Spawn 5 Elite Minors", _on_spawn_elites_pressed.bind("Minor", 5)))

	list.add_child(_dev_button("Spawn 3 Elite Majors", _on_spawn_elites_pressed.bind("Major", 3)))

	list.add_child(_dev_button("Start / End Swarm", _on_toggle_swarm_pressed))

	list.add_child(_dev_button("Clear Floor Pickups", _on_clear_pickups_pressed))


# A HUD command button for the dev tools list (left-aligned, nudges right on hover).
func _dev_button(text: String, on_pressed: Callable) -> Button:
	var button := HudStyle.make_button(text, Vector2(0, 34), 13, HudStyle.CYAN, true, HORIZONTAL_ALIGNMENT_LEFT)
	button.size_flags_horizontal = Control.SIZE_FILL
	button.pressed.connect(on_pressed)
	return button


func _on_pause_toggled(on: bool) -> void:
	GameManager.timer_paused = on

func _on_spawn_minors_pressed() -> void:
	if GameManager.player == null:
		return
	var spawner := GameManager.player.get_node_or_null("EnemySpawner") as EnemySpawner
	if spawner != null:
		spawner.spawn_from_tier("Minor", 25)

# Big debug spawns go out in batches over a few frames, so the game doesn't freeze while
# a thousand spawn points are found at once.
const SPAWN_BATCH := 250

func _on_spawn_many_minors_pressed(amount: int) -> void:
	if GameManager.player == null:
		return
	var spawner := GameManager.player.get_node_or_null("EnemySpawner") as EnemySpawner
	if spawner == null:
		return
	var left := amount
	while left > 0:
		spawner.spawn_from_tier("Minor", mini(left, SPAWN_BATCH))
		left -= SPAWN_BATCH
		if left > 0:
			await get_tree().physics_frame
			if not is_instance_valid(spawner):
				return

func _on_spawn_majors_pressed() -> void:
	if GameManager.player == null:
		return
	var spawner := GameManager.player.get_node_or_null("EnemySpawner") as EnemySpawner
	if spawner != null:
		spawner.spawn_from_tier("Major", 25)

func _on_spawn_elites_pressed(tier_name: String, amount: int) -> void:
	if GameManager.player == null:
		return
	var spawner := GameManager.player.get_node_or_null("EnemySpawner") as EnemySpawner
	if spawner != null:
		spawner.spawn_from_tier(tier_name, amount, true)

func _on_toggle_swarm_pressed() -> void:
	if GameManager.player == null:
		return
	var spawner := GameManager.player.get_node_or_null("EnemySpawner") as EnemySpawner
	if spawner == null:
		return
	if spawner.swarm_active:
		spawner.end_swarm()
	else:
		spawner.start_swarm()

func _on_clear_pickups_pressed() -> void:
	Coins.clear()
	for node in get_tree().get_nodes_in_group(&"floor_pickups"):
		var pickup := node as FloorPickup
		if pickup != null and pickup.can_be_cleared():
			pickup.queue_free()

# ---------- Item list (left column) ----------

# ---------- Item grid (top of left column) + weapon grid (bottom) ----------

func _build_items_panel() -> void:
	var halves := VBoxContainer.new()
	halves.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	halves.add_theme_constant_override("separation", 6)
	left_column.add_child(halves)

	_item_scroll = _add_grid_section(halves, "Items")
	_item_grid = _item_scroll.get_meta(&"grid")
	# Always room for at least one full row of items.
	_item_scroll.custom_minimum_size.y = ITEM_TILE_SIZE + TILE_GLOW_SIZE * 2
	_weapon_scroll = _add_grid_section(halves, "Weapons  /  drag to move")
	# Swap the plain grid for the four quadrants.
	var grid : GridContainer = _weapon_scroll.get_meta(&"grid")
	_weapon_quads = GridContainer.new()
	_weapon_quads.columns = 2
	_weapon_quads.add_theme_constant_override("h_separation", ITEM_TILE_GAP * 2)
	_weapon_quads.add_theme_constant_override("v_separation", ITEM_TILE_GAP * 2)
	grid.replace_by(_weapon_quads)
	grid.free()
	# Always tall enough for both rows of quadrants; the items list gets the rest.
	_weapon_scroll.size_flags_vertical = Control.SIZE_FILL
	_weapon_scroll.custom_minimum_size.y = 2 * (ITEM_TILE_SIZE + 22) + ITEM_TILE_GAP * 2 + TILE_GLOW_SIZE * 2 + 4


# A header plus a scrolling tile grid taking an equal share of the column's height.
func _add_grid_section(parent: Control, title: String) -> ScrollContainer:
	var header := HudStyle.make_header(title, 13)
	parent.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = ITEM_COLUMNS
	grid.add_theme_constant_override("h_separation", ITEM_TILE_GAP)
	grid.add_theme_constant_override("v_separation", ITEM_TILE_GAP)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, TILE_GLOW_SIZE)
	scroll.add_child(pad)
	pad.add_child(grid)
	scroll.set_meta(&"grid", grid)
	scroll.set_meta(&"header", header.get_meta(&"label"))
	return scroll


# One tile per item the player owns. Rows are added automatically every 4 tiles.
func _rebuild_item_grid() -> void:
	for child in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	_hovered = null

	var inventory := GameManager.player.inventory
	var items: Array = inventory.keys()
	items.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		if a.tier != b.tier:
			return a.tier > b.tier   # tier 5 (most common) first, tier 1 (rarest) last
		return a.display_name < b.display_name)
	var total := 0
	for item: ItemData in items:
		_item_grid.add_child(_make_item_tile(item, inventory[item]))
		total += inventory[item]
	# "ITEMS  /  12": how many you're carrying in all.
	(_item_scroll.get_meta(&"header") as Label).text = HudStyle.caption("Items  /  %d" % total)


# Every gun slot, laid out like they sit on screen: four quadrants (upper on top, left on
# the left), each with its slots left to right in the order they appear on screen.
# Guns can be dragged onto any slot; dropping on a gun swaps the two.
const QUADRANT_ORDER := [Player.Quadrant.UPPER_LEFT, Player.Quadrant.UPPER_RIGHT,
		Player.Quadrant.LOWER_LEFT, Player.Quadrant.LOWER_RIGHT]

func _rebuild_weapon_grid() -> void:
	for child in _weapon_quads.get_children():
		_weapon_quads.remove_child(child)
		child.queue_free()
	_weapon_tiles.clear()
	var player := GameManager.player
	for q in QUADRANT_ORDER:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var label := HudStyle.make_caption(Player.quadrant_label(q), 11)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		header.add_child(label)
		header.add_child(_make_fire_mode_button(q))
		box.add_child(header)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ITEM_TILE_GAP)
		box.add_child(row)
		for slot in _slots_on_screen_order(player.get_quadrant_slots(q)):
			var gun : Gun = slot.get_child(0) as Gun if slot.get_child_count() > 0 else null
			var tile := _make_weapon_tile(gun) if gun != null else _make_empty_slot_tile()
			tile.set_meta(&"slot", slot)
			tile.mouse_filter = Control.MOUSE_FILTER_PASS   # needed for dragging; the wheel still scrolls
			tile.set_drag_forwarding(_get_slot_drag.bind(tile), _can_drop_on_slot.bind(tile), _drop_on_slot.bind(tile))
			row.add_child(tile)
			_weapon_tiles.append(tile)
			UIJuice.hover_lift(tile, false)
			if slot in _swapped_slots:   # just dropped here: pop in
				UIJuice.pop_in(tile, 0.0, 0.7)
				if gun != null:
					UIJuice.flash(tile, 0.6)
		_weapon_quads.add_child(box)
	_swapped_slots.clear()


# ---- Manual / Auto toggle per quadrant ----

const MANUAL_COLOR := Color(0.85, 0.18, 0.18)
const AUTO_COLOR := Color(0.2, 0.45, 1.0)

func _make_fire_mode_button(q: Player.Quadrant) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(66, 20)
	button.add_theme_font_override("font", HudStyle.spaced(HudStyle.MENU_FONT, 1))
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_fire_mode_button(button, GameManager.player.quadrant_auto[q])
	button.pressed.connect(func() -> void:
		var auto : bool = not GameManager.player.quadrant_auto[q]
		GameManager.player.set_quadrant_auto(q, auto)
		_style_fire_mode_button(button, auto)
		UIJuice.punch(button, 0.2)
		UIJuice.flash(button, 0.5)
		UIJuice.play(UIJuice.Sfx.CLICK, 1.25 if auto else 0.85))
	return button


func _style_fire_mode_button(button: Button, auto: bool) -> void:
	button.text = "AUTO" if auto else "MANUAL"
	var color := AUTO_COLOR if auto else MANUAL_COLOR
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := HudPanelStyle.new()
		style.accent = color.lightened(0.3)
		style.cut = 4.0
		style.bracket = 5.0
		style.bar = false
		style.fill_top = Color(color.darkened(0.45), 0.9)
		style.fill_bottom = Color(color.darkened(0.65), 0.9)
		style.edge = Color(color.lightened(0.2), 0.8)
		style.lit = {"normal": 0.0, "hover": 0.5, "pressed": 1.0, "hover_pressed": 1.0}[state]
		style.glow = Color(color, 0.7)
		style.glow_size = 4.0 + 4.0 * style.lit
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, Color.WHITE)


# Left to right as the player sees them (by where each slot lands on screen).
func _slots_on_screen_order(slots: Array) -> Array:
	var cam := get_viewport().get_camera_3d()
	var sorted := slots.duplicate()
	sorted.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if cam != null:
			return cam.unproject_position(a.global_position).x < cam.unproject_position(b.global_position).x
		return a.position.x < b.position.x)
	return sorted


func _make_empty_slot_tile() -> Panel:
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(ITEM_TILE_SIZE, ITEM_TILE_SIZE)
	tile.add_theme_stylebox_override("panel", HudStyle.empty_tile_style())
	return tile


# ---- Drag and drop between slots ----

func _get_slot_drag(_at: Vector2, tile: Control) -> Variant:
	var slot : Node3D = tile.get_meta(&"slot")
	if slot.get_child_count() == 0:
		return null   # nothing to drag
	var gun := slot.get_child(0) as Gun
	var preview := _make_weapon_tile(gun)
	preview.modulate = Color(1, 1, 1, 0.85)
	var holder := Control.new()   # centers the preview on the cursor
	holder.add_child(preview)
	preview.position = -Vector2(ITEM_TILE_SIZE, ITEM_TILE_SIZE) * 0.5
	tile.set_drag_preview(holder)
	tile.modulate = Color(1, 1, 1, 0.35)   # dim the original while it's being moved
	_tip.visible = false
	return {"gun_slot": slot}


func _can_drop_on_slot(_at: Vector2, data: Variant, _tile: Control) -> bool:
	return data is Dictionary and data.has("gun_slot")


func _drop_on_slot(_at: Vector2, data: Variant, tile: Control) -> void:
	var target : Node3D = tile.get_meta(&"slot")
	GameManager.player.swap_gun_slots(data.gun_slot, target)
	_swapped_slots = [data.gun_slot, target]
	UIJuice.play(UIJuice.Sfx.PICK, 1.2)
	_rebuild_weapon_grid.call_deferred()


# While dragging a gun: the slot under the cursor lights up and grows a little.
func _update_drop_target() -> void:
	var target : Control = null
	if get_viewport().gui_is_dragging():
		var mouse := get_global_mouse_position()
		for tile in _weapon_tiles:
			if is_instance_valid(tile) and tile.get_global_rect().has_point(mouse):
				target = tile
				break
	if target == _drop_target:
		return
	if _drop_target != null and is_instance_valid(_drop_target):
		_drop_target.self_modulate = Color.WHITE
		_drop_target.scale = Vector2.ONE
	_drop_target = target
	if target != null:
		UIJuice.center_pivot(target)
		target.self_modulate = Color(1.6, 1.6, 1.6)
		target.scale = Vector2.ONE * 1.08
		UIJuice.play(UIJuice.Sfx.HOVER)


func _notification(what: int) -> void:
	# A drag that ended anywhere else: undo the dimming.
	if what == NOTIFICATION_DRAG_END and _weapon_quads != null:
		for tile in _weapon_tiles:
			if is_instance_valid(tile):
				tile.modulate = Color.WHITE
				tile.self_modulate = Color.WHITE
				tile.scale = Vector2.ONE
		_drop_target = null


func _make_weapon_tile(gun: Gun) -> Control:
	var tile := _make_tile_frame(gun, Rarity.get_color(gun.get_rarity()))
	Rarity.paint(tile, gun.get_rarity())   # Mythic: rainbow frame and glow
	if Rarity.is_animated(gun.get_rarity()):
		var style := tile.get_theme_stylebox("panel") as HudPanelStyle
		RarityAnimator.attach(tile, gun.get_rarity(), func(c: Color) -> void: HudStyle.color_tile(style, c))
	if gun.icon != null:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = gun.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	elif not gun.scene_file_path.is_empty():
		# No icon: a still render of the model (drawn once, so it's cheap).
		var px := ITEM_TILE_SIZE - 8
		var preview := GunPreview.create(load(gun.scene_file_path), Vector2i(px, px), 0.0)
		tile.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	return tile


# Rarity/tier colored tile shared by items and weapons. `data` is what hovering shows.
func _make_tile_frame(data: Object, tier_color: Color) -> Panel:
	# Tiles ignore the mouse (hover is polled in _update_item_hover), so the
	# scroll wheel still reaches the ScrollContainer underneath.
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(ITEM_TILE_SIZE, ITEM_TILE_SIZE)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.set_meta(&"data", data)
	tile.add_theme_stylebox_override("panel", HudStyle.tile_style(tier_color))
	return tile


func _make_item_tile(item: ItemData, count: int) -> Control:
	var tile := _make_tile_frame(item, item.get_tier_color())
	Rarity.paint_tier(tile, item.tier)   # Legendary items shine too
	if item.icon != null:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	else:
		# No icon assigned yet: show the name so the tile isn't blank.
		var fallback := Label.new()
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.text = item.display_name
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_override("font", description_font)
		fallback.add_theme_font_size_override("font_size", 11)
		tile.add_child(fallback)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)

	# "x3" in the bottom right corner, drawn over the icon.
	var count_label := Label.new()
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.text = "x%d" % count
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_font_override("font", HudStyle.NUMBER_FONT)
	count_label.add_theme_font_size_override("font_size", 15)
	count_label.add_theme_color_override("font_outline_color", Color(HudStyle.SHADOW, 0.9))
	count_label.add_theme_constant_override("outline_size", 4)

	tile.add_child(count_label)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)

	return tile


# ---------- Hover popup ----------

func _build_item_tooltip() -> void:
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # must not steal the hover it depends on
	_tip.visible = false
	_tip_style = HudStyle.panel_style(HudStyle.CYAN, TIP_PADDING)
	_tip_style.fill_top = Color(_tip_style.fill_top, 0.95)
	_tip_style.fill_bottom = Color(_tip_style.fill_bottom, 0.95)
	_tip.add_theme_stylebox_override("panel", _tip_style)
	add_child(_tip)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	_tip.add_child(column)

	_tip_name = Label.new()
	_tip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_name.add_theme_font_override("font", name_font)
	_tip_name.add_theme_font_size_override("font_size", tip_name_font_size)
	column.add_child(_tip_name)

	_tip_desc = Label.new()
	_tip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_desc.add_theme_font_override("font", description_font)
	_tip_desc.add_theme_font_size_override("font_size", tip_description_font_size)
	_tip_desc.add_theme_color_override("font_color", tip_description_color)
	column.add_child(_tip_desc)

	_tip_stats = VBoxContainer.new()
	_tip_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_stats.add_theme_constant_override("separation", 0)
	_tip_stats.visible = false
	column.add_child(_tip_stats)


# Polled every frame: also handles tiles scrolling under a stationary cursor.
func _update_item_hover() -> void:
	var mouse := get_global_mouse_position()
	var hovered: Object = _tile_data_at(_item_scroll, _item_grid, mouse)
	if hovered == null and _weapon_scroll.get_global_rect().has_point(mouse) and not get_viewport().gui_is_dragging():
		for tile in _weapon_tiles:
			if tile.get_global_rect().has_point(mouse):
				hovered = tile.get_meta(&"data") if tile.has_meta(&"data") else null   # empty slots have none
				break

	_set_hover_tile(_tile_at(mouse) if hovered != null else null)
	if hovered == null or not is_instance_valid(hovered):
		_hovered = null
		_tip.visible = false
		return

	if hovered != _hovered:
		_hovered = hovered
		# A new thing under the cursor: the tooltip pops in from the cursor.
		_tip.pivot_offset = Vector2.ZERO
		_tip.scale = Vector2.ONE * 0.92
		UIJuice.tween_of(_tip).tween_property(_tip, "scale", Vector2.ONE, 0.12) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if hovered is Gun:
			_fill_weapon_tooltip(hovered)
		else:
			_fill_tooltip(hovered)
	elif hovered is Gun and Rarity.is_animated((hovered as Gun).get_rarity()):
		_color_weapon_tooltip(hovered)   # Mythic: keep the rainbow moving

	# Follow the cursor, kept fully on screen.
	var pos := get_local_mouse_position() + TIP_OFFSET
	pos.x = minf(pos.x, size.x - _tip.size.x - 8.0)
	pos.y = minf(pos.y, size.y - _tip.size.y - 8.0)
	_tip.position = pos
	_tip.visible = true


# The item or weapon tile under the mouse, if any.
func _tile_at(mouse: Vector2) -> Control:
	if _item_scroll.get_global_rect().has_point(mouse):
		for tile in _item_grid.get_children():
			if (tile as Control).get_global_rect().has_point(mouse):
				return tile
	if _weapon_scroll.get_global_rect().has_point(mouse):
		for tile in _weapon_tiles:
			if is_instance_valid(tile) and tile.get_global_rect().has_point(mouse):
				return tile
	return null


# Item tiles ignore the mouse (so the wheel scrolls), so their hover lift is done here.
# (Weapon tiles lift on their own through UIJuice.hover_lift.)
func _set_hover_tile(tile: Control) -> void:
	if tile == _hover_tile:
		return
	if _hover_tile != null and is_instance_valid(_hover_tile) and not _hover_tile.has_meta(&"slot"):
		UIJuice.tween_of(_hover_tile).tween_property(_hover_tile, "scale", Vector2.ONE, 0.12)
	_hover_tile = tile
	if tile != null and not tile.has_meta(&"slot"):
		UIJuice.center_pivot(tile)
		UIJuice.tween_of(tile).tween_property(tile, "scale", Vector2.ONE * 1.1, 0.14) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		UIJuice.play(UIJuice.Sfx.HOVER)


func _tile_data_at(scroll: ScrollContainer, grid: GridContainer, mouse: Vector2) -> Object:
	if not scroll.get_global_rect().has_point(mouse):
		return null
	for tile in grid.get_children():
		if (tile as Control).get_global_rect().has_point(mouse):
			return tile.get_meta(&"data")
	return null


func _fill_tooltip(item: ItemData) -> void:
	_fill_tip(item.display_name, item.get_tier_color(), item.description)
	Rarity.paint_tier(_tip_name, item.tier)   # Legendary shine (and clears a gun's effect: the tooltip is reused)


# Name in its rarity color, then rarity, rolled bonuses, and the gun's own base stats.
func _fill_weapon_tooltip(gun: Gun) -> void:
	var color := Rarity.get_color(gun.get_rarity())
	# The gun's own stats with its rolls applied. Rolled ones are lit up in the rarity color
	# (like the gun store cards) with the roll in brackets; the rest stay gray.
	var boost_color := color.lerp(Color.WHITE, 0.45)
	var stats : Array[Dictionary] = []
	for stat in gun.get_stat_summary():
		var line : String = "%s: %s" % [stat.name, stat.value]
		if not stat.bonus.is_empty():
			line += "  (%s)" % stat.bonus
		stats.append({"text": line, "color": boost_color if stat.boosted else tip_base_stat_color, "boosted": stat.boosted})
	_fill_tip(gun.get_display_name(), color, Rarity.name_of(gun.get_rarity()), stats)
	# Mythic: the name and rolled stats get the rolling rainbow (other rarities clear it).
	Rarity.paint(_tip_name, gun.get_rarity())
	for label in _tip_stats.get_children():
		if label.get_meta(&"boosted", false):
			Rarity.paint(label, gun.get_rarity())


# Re-tints a weapon tooltip that's already showing (for animated rarity colors).
func _color_weapon_tooltip(gun: Gun) -> void:
	var color := Rarity.get_color(gun.get_rarity())
	TextGlow.set_text(_tip_name, gun.get_display_name(), color)
	var boost_color := color.lerp(Color.WHITE, 0.45)
	for label in _tip_stats.get_children():
		if label.get_meta(&"boosted", false):
			(label as Label).add_theme_color_override("font_color", boost_color)


func _num(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.01))


## stats: optional {text, color} lines shown under the description.
func _fill_tip(title: String, tier_color: Color, description: String, stats: Array[Dictionary] = []) -> void:
	_tip_style.accent = tier_color
	_tip_style.edge = Color(tier_color, 0.45)
	_tip_name.add_theme_color_override("font_color", tier_color)
	TextGlow.set_text(_tip_name, title, tier_color)
	# Line breaks are put in here instead of using Label autowrap: a wrapping Label works out
	# its height from its current width, which is stale right after the text changes (zero the
	# very first time, so every word got its own line: the screen-tall box), and that made
	# the box come out a different height each time.
	_tip_desc.text = _wrap(description, _tip_desc, TIP_MAX_TEXT_WIDTH)
	_tip_desc.visible = not description.is_empty()
	for child in _tip_stats.get_children():
		_tip_stats.remove_child(child)
		child.queue_free()
	for stat in stats:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", description_font)
		label.add_theme_font_size_override("font_size", tip_description_font_size)
		label.add_theme_color_override("font_color", stat.color)
		label.text = _wrap(stat.text, label, TIP_MAX_TEXT_WIDTH)
		label.set_meta(&"boosted", stat.get("boosted", false))
		_tip_stats.add_child(label)
	_tip_stats.visible = not stats.is_empty()

	# Hug the text: as wide as the widest line.
	var width := maxf(_text_width(_tip_name), _text_width(_tip_desc))
	for label in _tip_stats.get_children():
		width = maxf(width, _text_width(label))
	width = ceilf(width) + 2.0
	_tip_name.custom_minimum_size.x = width
	_tip_desc.custom_minimum_size.x = width
	_tip.reset_size()   # containers grow on their own but never shrink back


# Breaks text into lines no wider than max_width (keeps existing line breaks).
func _wrap(text: String, label: Label, max_width: float) -> String:
	if text.is_empty():
		return text
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var out := PackedStringArray()
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate := word if line.is_empty() else line + " " + word
			if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
				out.append(line)
				line = word
			else:
				line = candidate
		out.append(line)
	return "\n".join(out)


# Widest line of the label's text (tooltips can have several lines).
func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var widest := 0.0
	for line in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return widest

# ---------- Open / close ----------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu") and not visible:
		_open()
		get_viewport().set_input_as_handled()   # stops Tab from moving UI focus


func _process(_delta: float) -> void:
	if not visible:
		return
	# Polling (instead of waiting for the release event) also covers alt-tabbing
	# away while holding Tab, which would otherwise leave the menu stuck open.
	if not Input.is_action_pressed(&"menu"):
		_close()
		return
	_update_stat_values()   # keeps values live if a stat changes while open
	_update_item_hover()
	_update_drop_target()

# Sizes the panel so it stops short of the timer, enemy count and scrap counter (top).
# Measured on open, so font or size changes to those elements are picked up automatically.
func _fit_to_hud() -> void:
	var hud := get_parent()

	var top := size.y * EDGE_MARGIN
	for node_name in ["Timer", "EnemyCount", "Gold"]:
		var label := hud.get_node_or_null(node_name) as Control
		if label != null:
			top = maxf(top, label.get_global_rect().end.y + HUD_CLEARANCE)

	# The bottom runs down to the screen margin, over the health / energy gauges: the menu
	# needs the room more than the gauges need to show while it's held open.
	var bottom := size.y * EDGE_MARGIN

	_box.anchor_top = 0.0
	_box.anchor_bottom = 1.0
	_box.offset_top = top
	_box.offset_bottom = -bottom

func _open() -> void:
	visible = true
	_fit_to_hud()
	_fade_vitals(0.12)
	UIJuice.pop_in(_box, 0.0, 0.97, 0.12)
	# The columns deal in one after another.
	for i in _columns.get_child_count():
		var column := _columns.get_child(i) as Control
		column.modulate.a = 0.0
		var t := UIJuice.tween_of(column)
		t.tween_interval(0.03 + 0.05 * i)
		t.tween_property(column, "modulate:a", 1.0, 0.14)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_toggle.set_pressed_no_signal(GameManager.timer_paused)
	if GameManager.player != null:
		GameManager.player.menu_open = true
		_rebuild_item_grid()
		_rebuild_weapon_grid()
		# Stats are created in PlayerStats._ready(), so build rows on first open
		# (or again if a stat is ever added later).
		if _stat_value_labels.size() != GameManager.player.stats_node.stats.size():
			_rebuild_stat_rows()
		_update_stat_values()


# The health / energy gauges sit under the bottom of the menu: they fade back while it's open
# so they don't show through the stats.
func _fade_vitals(alpha: float) -> void:
	var bars := get_parent().get_node_or_null("StatBars") as CanvasItem
	if bars != null:
		var t := bars.create_tween()
		t.tween_property(bars, "modulate:a", alpha, 0.12)


func _close() -> void:
	visible = false
	_fade_vitals(1.0)
	_tip.visible = false
	_set_hover_tile(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if GameManager.player != null:
		GameManager.player.menu_open = false
