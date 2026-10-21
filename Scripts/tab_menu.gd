# Hold-Tab menu. Opens while the "menu" action is held, closes the instant it's released.
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

const TILE_GLOW_SIZE := 10        # how far the glow spreads, in px
const TILE_GLOW_ALPHA := 0.6
const TILE_BORDER := 2
const TILE_BORDER_WHITEN := 0.6   # 0 = border is the tier color, 1 = white


var _box: Panel

@export var name_font: Font = preload("res://Fonts/KHMenu-Bold.otf")
@export var description_font: Font = preload("res://Fonts/KHMenu.otf")
@export var tip_name_font_size := 20
@export var tip_description_font_size := 15
@export var tip_description_color := Color(0.85, 0.85, 0.85)
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

	var box := Panel.new()
	box.anchor_left = EDGE_MARGIN
	box.anchor_top = EDGE_MARGIN
	box.anchor_right = 1.0 - EDGE_MARGIN
	box.anchor_bottom = 1.0 - EDGE_MARGIN
	box.offset_left = 0
	box.offset_top = 0
	box.offset_right = 0
	box.offset_bottom = 0
	var style := StyleBoxFlat.new()
	style.bg_color = BOX_COLOR
	box.add_theme_stylebox_override("panel", style)
	add_child(box)
	_box = box

	content = MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 24)
	box.add_child(content)

	# Three equal-width columns.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 0)
	content.add_child(columns)
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
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_column.add_child(scroll)

	_stat_list = VBoxContainer.new()
	_stat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_stat_list)


# One row per stat: name on the left, value on the right.
func _rebuild_stat_rows() -> void:
	for child in _stat_list.get_children():
		child.queue_free()
	_stat_value_labels.clear()

	for stat_name in GameManager.player.stats_node.stats:
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = String(stat_name).capitalize()   # "max_health" -> "Max Health"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		_stat_list.add_child(row)
		_stat_value_labels[stat_name] = value_label


func _update_stat_values() -> void:
	var stats_node := GameManager.player.stats_node
	for stat_name in _stat_value_labels:
		var value: float = stats_node.get_value(stat_name)
		(_stat_value_labels[stat_name] as Label).text = str(snappedf(value, 0.01))

# ---------- Buttons (middle column) ----------

func _build_buttons_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", COLUMN_PADDING)
	margin.add_theme_constant_override("margin_right", COLUMN_PADDING)
	middle_column.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	margin.add_child(list)

	_pause_toggle = CheckButton.new()
	_pause_toggle.text = "Pause Timer"
	# No keyboard focus: otherwise clicking it once would make Space (your jump key)
	# toggle it every time you jump. Mouse clicks still work.
	_pause_toggle.focus_mode = Control.FOCUS_NONE
	_pause_toggle.toggled.connect(_on_pause_toggled)
	list.add_child(_pause_toggle)

	var minor_button := Button.new()
	minor_button.text = "Spawn 25 Minors"
	minor_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	minor_button.pressed.connect(_on_spawn_minors_pressed)
	list.add_child(minor_button)

	var minor_1000_button := Button.new()
	minor_1000_button.text = "Spawn 1000 Minors"
	minor_1000_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	minor_1000_button.pressed.connect(_on_spawn_many_minors_pressed.bind(1000))
	list.add_child(minor_1000_button)

	var major_button := Button.new()
	major_button.text = "Spawn 25 Majors"
	major_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	major_button.pressed.connect(_on_spawn_majors_pressed)
	list.add_child(major_button)

	var elite_minor_button := Button.new()
	elite_minor_button.text = "Spawn 5 Elite Minors"
	elite_minor_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	elite_minor_button.pressed.connect(_on_spawn_elites_pressed.bind("Minor", 5))
	list.add_child(elite_minor_button)

	var elite_major_button := Button.new()
	elite_major_button.text = "Spawn 3 Elite Majors"
	elite_major_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	elite_major_button.pressed.connect(_on_spawn_elites_pressed.bind("Major", 3))
	list.add_child(elite_major_button)

	var swarm_button := Button.new()
	swarm_button.text = "Start / End Swarm"
	swarm_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	swarm_button.pressed.connect(_on_toggle_swarm_pressed)
	list.add_child(swarm_button)

	var clear_button := Button.new()
	clear_button.text = "Clear Floor Pickups"
	clear_button.focus_mode = Control.FOCUS_NONE   # keeps Space (jump) from re-pressing it
	clear_button.pressed.connect(_on_clear_pickups_pressed)
	list.add_child(clear_button)


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
	halves.add_theme_constant_override("separation", 8)
	left_column.add_child(halves)

	_item_scroll = _add_grid_section(halves, "Items")
	_item_grid = _item_scroll.get_meta(&"grid")
	_weapon_scroll = _add_grid_section(halves, "Weapons  (drag to move)")
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
	var header := Label.new()
	header.text = title
	header.add_theme_font_override("font", name_font)
	header.add_theme_font_size_override("font_size", section_header_font_size)
	header.add_theme_color_override("font_color", section_header_color)
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
	for item: ItemData in items:
		_item_grid.add_child(_make_item_tile(item, inventory[item]))


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
		var label := Label.new()
		label.text = Player.quadrant_label(q)
		label.add_theme_font_override("font", name_font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", section_header_color)
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
		_weapon_quads.add_child(box)


# ---- Manual / Auto toggle per quadrant ----

const MANUAL_COLOR := Color(0.85, 0.18, 0.18)
const AUTO_COLOR := Color(0.2, 0.45, 1.0)

func _make_fire_mode_button(q: Player.Quadrant) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(62, 0)
	button.add_theme_font_override("font", name_font)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_fire_mode_button(button, GameManager.player.quadrant_auto[q])
	button.pressed.connect(func() -> void:
		var auto : bool = not GameManager.player.quadrant_auto[q]
		GameManager.player.set_quadrant_auto(q, auto)
		_style_fire_mode_button(button, auto))
	return button


func _style_fire_mode_button(button: Button, auto: bool) -> void:
	button.text = "Auto" if auto else "Manual"
	var color := AUTO_COLOR if auto else MANUAL_COLOR
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.darkened({"normal": 0.25, "hover": 0.05, "pressed": 0.4}[state])
		style.border_color = color.lightened(0.35)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_corner_radius_all(4)
	style.set_border_width_all(TILE_BORDER)
	style.border_color = Color(0.45, 0.45, 0.45, 0.6)
	tile.add_theme_stylebox_override("panel", style)
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
	GameManager.player.swap_gun_slots(data.gun_slot, tile.get_meta(&"slot"))
	_rebuild_weapon_grid.call_deferred()


func _notification(what: int) -> void:
	# A drag that ended anywhere else: undo the dimming.
	if what == NOTIFICATION_DRAG_END and _weapon_quads != null:
		for tile in _weapon_tiles:
			if is_instance_valid(tile):
				tile.modulate = Color.WHITE


func _make_weapon_tile(gun: Gun) -> Control:
	var tile := _make_tile_frame(gun, Rarity.get_color(gun.get_rarity()))
	if Rarity.is_animated(gun.get_rarity()):   # Mythic: keep the frame cycling
		var style := tile.get_theme_stylebox("panel") as StyleBoxFlat
		RarityAnimator.attach(tile, gun.get_rarity(), func(c: Color) -> void: _color_tile_style(style, c))
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
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(TILE_BORDER)
	style.shadow_size = TILE_GLOW_SIZE
	style.shadow_offset = Vector2.ZERO
	_color_tile_style(style, tier_color)
	tile.add_theme_stylebox_override("panel", style)
	return tile


func _color_tile_style(style: StyleBoxFlat, tier_color: Color) -> void:
	style.bg_color = Color(tier_color.darkened(0.8), 0.5)   # faintly lit inside
	style.border_color = tier_color.lerp(Color.WHITE, TILE_BORDER_WHITEN)
	style.shadow_color = Color(tier_color, TILE_GLOW_ALPHA)


func _make_item_tile(item: ItemData, count: int) -> Control:
	var tile := _make_tile_frame(item, item.get_tier_color())
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
	count_label.add_theme_font_override("font", name_font)
	count_label.add_theme_font_size_override("font_size", 16)

	tile.add_child(count_label)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)

	return tile


# ---------- Hover popup ----------

func _build_item_tooltip() -> void:
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # must not steal the hover it depends on
	_tip.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = tip_box_color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(TIP_PADDING)
	_tip.add_theme_stylebox_override("panel", style)
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

	if hovered == null or not is_instance_valid(hovered):
		_hovered = null
		_tip.visible = false
		return

	if hovered != _hovered:
		_hovered = hovered
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


func _tile_data_at(scroll: ScrollContainer, grid: GridContainer, mouse: Vector2) -> Object:
	if not scroll.get_global_rect().has_point(mouse):
		return null
	for tile in grid.get_children():
		if (tile as Control).get_global_rect().has_point(mouse):
			return tile.get_meta(&"data")
	return null


func _fill_tooltip(item: ItemData) -> void:
	_fill_tip(item.display_name, item.get_tier_color(), item.description)


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

# Sizes the panel so it stops short of the timer and enemy count (top) and the
# health/energy bars (bottom right). Measured on open, so font or size changes
# to those elements are picked up automatically.
func _fit_to_hud() -> void:
	var hud := get_parent()

	var top := size.y * EDGE_MARGIN
	for node_name in ["Timer", "EnemyCount", "Gold"]:
		var label := hud.get_node_or_null(node_name) as Control
		if label != null:
			top = maxf(top, label.get_global_rect().end.y + HUD_CLEARANCE)

	var bottom := size.y * EDGE_MARGIN
	var bars := hud.get_node_or_null("StatBars")
	if bars != null and bars.get_child_count() > 0:
		var bars_rect := (bars.get_child(0) as Control).get_global_rect()
		bottom = maxf(bottom, size.y - bars_rect.position.y + HUD_CLEARANCE)

	_box.anchor_top = 0.0
	_box.anchor_bottom = 1.0
	_box.offset_top = top
	_box.offset_bottom = -bottom

func _open() -> void:
	visible = true
	_fit_to_hud()
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


func _close() -> void:
	visible = false
	_tip.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if GameManager.player != null:
		GameManager.player.menu_open = false
