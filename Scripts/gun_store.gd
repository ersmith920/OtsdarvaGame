# Gun store: pay gold, the game freezes and shows 3 randomly rolled guns, pick one and it
# goes straight into your next gun slot. One purchase per store.
# Price works like chests (base price + % per purchase), but counts gun stores bought this run,
# separate from chests opened.
extends Chest
class_name GunStore

@export_group("Stock")
## Guns the store can offer. Each of the 3 options picks from this list (repeats allowed).
@export var gun_pool : Array[PackedScene]
## How many options to show.
@export_range(1, 6) var option_count := 3
## Off: the options are always 3 different guns (when the pool has enough).
@export var allow_duplicate_guns := true
## How much each stat rolls (Items/weapon_roll_table.tres).
@export var roll_table : WeaponRollTable
## Rarity odds: this table's tier odds (Items/loot_table.tres, the same odds as item chests),
## shifted toward higher rarities by the player's luck stat.
@export var rarity_table : LootTable
@export var popup_title := "Gun Store"
## Size of the gun cards (1 = full size, 0.5 = half).
@export_range(0.3, 1.5, 0.05) var card_scale := 0.5

@export_group("Dev / Testing")
## Never gets used up: can be opened again and again (for test scenes).
@export var reusable := false
## Adds a Reroll button that swaps the options for new ones (free).
@export var show_reroll := false
## Adds a Close button that leaves without picking.
@export var show_close := false

@export_group("Used Look")
## Meshes that change to Used Material after the store has been bought from (e.g. its screen).
@export var used_meshes : Array[MeshInstance3D]
## Empty = the meshes are just hidden.
@export var used_material : Material

# The rolled guns waiting on the player's pick (not in the tree until chosen).
var _offers : Array[Gun] = []
var _offer_scenes : Array[PackedScene] = []
var _saved_materials := {}


func _get_purchase_count() -> int:
	return GameManager.gun_stores_purchased


func _count_purchase() -> void:
	GameManager.gun_stores_purchased += 1
	GameManager.gun_stores_purchased_changed.emit(GameManager.gun_stores_purchased)


func interact(_normal: Vector3) -> void:
	if open or GameManager.choice_open:
		return
	var player := GameManager.player
	if player == null or GameManager.choice_popup == null:
		push_warning("GunStore: needs a player and a ChoicePopup on the HUD")
		return
	if gun_pool.is_empty() or roll_table == null:
		push_warning("GunStore: assign gun_pool and roll_table")
		return
	if not player.has_free_gun_slot():
		_deny()
		return
	if not _try_pay():
		return
	if counts_toward_price:
		_count_purchase()
	if not reusable:
		open = true
		_refresh_cost_display()
		_set_used_look(true)
	_play_sound(open_sound, open_volume_db)

	_roll_offers(player.stats_node.get_value(&"luck"))
	var buttons := []
	if show_reroll:
		buttons.append({"text": "Reroll", "pressed": _reroll})
	if show_close:
		buttons.append({"text": "Close", "pressed": GameManager.choice_popup.cancel})
	GameManager.choice_popup.open(popup_title, _build_cards(), _on_pick, buttons)


func _build_cards() -> Array[Control]:
	var cards : Array[Control] = []
	for i in _offers.size():
		cards.append(GunCard.build(_offer_scenes[i], _offers[i], "", card_scale))
	return cards


func _reroll() -> void:
	var player := GameManager.player
	_roll_offers(player.stats_node.get_value(&"luck") if player != null else 0.0)
	GameManager.choice_popup.set_cards(_build_cards())


func _roll_offers(luck: float) -> void:
	_clear_offers()
	var pool := gun_pool.filter(func(s: PackedScene) -> bool: return s != null)
	for i in option_count:
		if pool.is_empty():
			break
		var scene : PackedScene = pool.pick_random()
		if not allow_duplicate_guns and pool.size() > 1:
			pool.erase(scene)
		var gun := scene.instantiate() as Gun
		if gun == null:
			continue
		gun.apply_roll(roll_table.roll_for(gun, Rarity.roll(rarity_table, luck)))
		_offers.append(gun)
		_offer_scenes.append(scene)


func _on_pick(index: int) -> void:
	if index < 0 or index >= _offers.size():
		_clear_offers()
		return
	var gun := _offers[index]
	_offers.remove_at(index)
	_clear_offers()
	get_tree().current_scene.add_child(gun)
	gun.global_position = global_position
	gun.equip()


func _clear_offers() -> void:
	for gun in _offers:
		if is_instance_valid(gun) and not gun.is_inside_tree():
			gun.free()
	_offers.clear()
	_offer_scenes.clear()


func _set_used_look(used: bool) -> void:
	for mesh in used_meshes:
		if mesh == null:
			continue
		if not _saved_materials.has(mesh):
			_saved_materials[mesh] = mesh.material_override
		if used_material == null:
			mesh.visible = not used
		else:
			mesh.material_override = used_material if used else _saved_materials[mesh]


## The Reset Pylon reopens every chest, stores included.
func reset() -> void:
	open = false
	_set_used_look(false)
	_refresh_cost_display()


func _exit_tree() -> void:
	_clear_offers()
