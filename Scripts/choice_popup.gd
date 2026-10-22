# Pick-one popup: pauses the game and shows tall cards side by side; clicking one picks it.
# Escape can't close it (a choice must be made). Reusable for anything that offers a choice
# (gun stores now, level-up upgrades later). Lives on the HUD; reach it with GameManager.choice_popup.
#
#   GameManager.choice_popup.open("Gun Store", cards, func(index): ...)
#
# Optional buttons under the cards (the dev gun store uses Reroll and Close):
#   open(title, cards, on_pick, [{"text": "Reroll", "pressed": func(): ...}])
# A button can swap the cards with set_cards(), or close without a pick with cancel()
# (on_pick is then called with -1).
#
# Each card is any Control you build (see GunCard). The popup wraps each one in a
# clickable frame in that card's color, so the content doesn't need to handle input.
#
# Feel (see UIJuice): the game behind blurs, the cards are dealt in, a reroll flips them,
# cards lift, light up and glint on hover, and picking one flashes it with a burst of sparks
# (bigger for rarer picks) before the popup closes.
# Look: the HUD style (HudStyle): letter-spaced title over an accent rule, cards framed as
# HUD panels in their rarity color with a soft glow, HUD command buttons.
class_name ChoicePopup
extends Control

@export_group("Look")
## Tint over the frozen (blurred) game behind the cards; alpha = how dark.
@export var dim_color := Color(0.0, 0.04, 0.015, 0.55)
## Unused now: titles use HudStyle's font (kept so scenes that set it still load).
@export var title_font : Font = preload("res://Fonts/KHMenu-Bold.otf")
@export var title_font_size := 34
## Smallest a card's frame can be; cards with bigger content (gun cards) are as big as it.
@export var card_size := Vector2(120, 160)
@export var card_gap := 28
@export var card_padding := 10
## Unused now: card frames use HudStyle.card_style (kept so scenes that set them still load).
@export var card_bg := Color(0.05, 0.05, 0.06, 0.94)
@export var card_border := 3
## How far the colored glow spreads around a card (more on hover).
@export var glow_size := 14
@export var hover_glow_size := 26
## Seconds before clicks count, so a click already in progress when it opened can't pick by accident.
@export var input_delay := 0.25

@export_group("Audio")
@export var open_sound : AudioStream
@export var pick_sound : AudioStream
@export var hover_sound : AudioStream
@export var volume_db := 0.0

var _title : Label
var _title_box : Control
var _dim : ColorRect
var _column : VBoxContainer
var _closing := false
var _row : HBoxContainer
var _buttons : HBoxContainer
var _on_pick : Callable
var _opened_at_ms := 0
var _was_paused := false
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the tree is paused
	theme = HudStyle.menu_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	GameManager.choice_popup = self

	_dim = ColorRect.new()
	_dim.color = dim_color
	_dim.material = UIJuice.blur_material()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	_column = column

	_title_box = HudStyle.make_title("", title_font_size)
	_title = _title_box.get_meta(&"label")
	column.add_child(_title_box)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", card_gap)
	column.add_child(_row)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 20)
	column.add_child(_buttons)


func is_open() -> bool:
	return visible


## Shows the cards and pauses the game until one is clicked.
## cards: one Control per option. Set meta "color" on a card to color its frame.
## on_pick: called with the index of the chosen card, after the game unpauses.
## buttons: optional [{"text": String, "pressed": Callable}] shown under the cards.
func open(title: String, cards: Array[Control], on_pick: Callable, buttons: Array = []) -> void:
	if visible:
		push_warning("ChoicePopup is already open")
		return
	_on_pick = on_pick
	_closing = false
	_column.modulate.a = 1.0
	_column.scale = Vector2.ONE
	_title.text = title.to_upper()
	_title_box.visible = not title.is_empty()
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for b in buttons:
		_buttons.add_child(_make_button(b.text, b.pressed))
	_buttons.visible = not buttons.is_empty()
	set_cards(cards, 0.08)

	# Blur the game in, drop the title in, then the buttons after the cards.
	(_dim.material as ShaderMaterial).set_shader_parameter(&"amount", 0.0)
	UIJuice.fade_backdrop(_dim, 1.0, 0.2)
	UIJuice.pop_in(_title_box, 0.0, 0.8)
	for i in _buttons.get_child_count():
		UIJuice.pop_in(_buttons.get_child(i), 0.12 + cards.size() * UIJuice.DEAL_STAGGER + i * 0.04)
	if open_sound == null:
		UIJuice.play(UIJuice.Sfx.OPEN)

	_was_paused = get_tree().paused
	_prev_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	GameManager.choice_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_opened_at_ms = Time.get_ticks_msec()
	visible = true
	_play(open_sound)


## Replaces the cards shown (e.g. a reroll) without closing. They flip in one by one.
func set_cards(cards: Array[Control], start_delay := 0.0) -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	var frames := []
	for i in cards.size():
		var frame := _wrap_card(cards[i], i)
		_row.add_child(frame)
		frames.append(frame)
	UIJuice.deal_in(frames, start_delay)
	if visible:
		UIJuice.play(UIJuice.Sfx.CLICK, 1.2)


## Closes without picking anything; on_pick gets -1.
func cancel() -> void:
	if visible and not _closing:
		_close(-1)


func _make_button(text: String, pressed: Callable) -> Button:
	var button := HudStyle.make_button(text, Vector2(200, 46), 18)
	button.pressed.connect(func() -> void:
		if not _closing:
			pressed.call())
	if hover_sound != null:
		button.mouse_entered.connect(_play.bind(hover_sound))
	return button


# A Button (fires on release, so the click can't leak into shooting after unpausing)
# with the card's content inside it.
func _wrap_card(content: Control, index: int) -> Button:
	var color : Color = content.get_meta(&"color", Color(0.7, 0.7, 0.7))
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space / Enter from picking a card
	button.clip_contents = false
	Rarity.paint(button, content.get_meta(&"rarity", -1))   # Legendary shine / Mythic rainbow frame
	button.add_theme_stylebox_override("normal", _card_style(color, 0.0))
	button.add_theme_stylebox_override("hover", _card_style(color, 0.55))
	button.add_theme_stylebox_override("pressed", _card_style(color, 1.0))
	button.add_theme_stylebox_override("hover_pressed", _card_style(color, 1.0))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_pick.bind(index))
	button.set_meta(&"rarity", content.get_meta(&"rarity", 0))
	button.set_meta(&"color", color)
	UIJuice.hover_lift(button, hover_sound == null)
	if hover_sound != null:
		button.mouse_entered.connect(_play.bind(hover_sound))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, card_padding)
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ignore_mouse(content)
	margin.add_child(content)
	# A glint sweeps across the card when it's hovered (drawn over its content).
	var glint := HudStyle.add_glint(button, 1.0)
	button.mouse_entered.connect(glint)
	# Fixed-size content (GunCard) makes every card the same size; anything bigger than
	# card_size just makes its card bigger. Set once: cards never resize while shown.
	# (Uses the content's set minimum size: measuring it before it's on screen is unreliable.)
	var content_size := content.custom_minimum_size
	if content_size == Vector2.ZERO:
		content_size = content.get_combined_minimum_size()
	var need := content_size + Vector2(card_padding, card_padding) * 2.0
	button.custom_minimum_size = Vector2(maxf(card_size.x, need.x), maxf(card_size.y, need.y))
	return button


# A card frame in the HUD style (HudStyle.card_style). lit: 0 resting, more when hovered.
func _card_style(color: Color, lit: float) -> HudPanelStyle:
	var style := HudStyle.card_style(color, lit)
	style.glow_size = lerpf(glow_size, hover_glow_size, lit) * 0.5   # a tight glow suits the thin frames
	return style


# Card contents must never take the click from the frame.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _pick(index: int) -> void:
	if not visible or _closing or Time.get_ticks_msec() - _opened_at_ms < int(input_delay * 1000.0):
		return
	_closing = true
	# Payoff: the picked card flashes and bursts (bigger for rarer picks), the rest fall away.
	var picked : Control = _row.get_child(index)
	var rarity : int = picked.get_meta(&"rarity", 0)
	UIJuice.flash(picked, 0.6 + rarity * 0.15)
	UIJuice.punch(picked, 0.08)
	UIJuice.burst(self, picked.get_global_rect().get_center(), picked.get_meta(&"color", Color.WHITE), rarity)
	for card in _row.get_children():
		if card != picked:
			UIJuice.pop_out(card)
	if pick_sound != null:
		_play(pick_sound)
	else:
		UIJuice.play(UIJuice.Sfx.JACKPOT if rarity >= Rarity.MYTHIC else
				(UIJuice.Sfx.REWARD if rarity >= Rarity.EPIC else UIJuice.Sfx.PICK))
	var hold := 0.35 + 0.1 * maxi(rarity - Rarity.RARE, 0)
	get_tree().create_timer(hold, true, false, true).timeout.connect(_close.bind(index))


# Fades everything out, then hands over the pick.
func _close(index: int) -> void:
	_closing = true
	UIJuice.fade_backdrop(_dim, 0.0, 0.18)
	UIJuice.pop_out(_column, _finish.bind(index))
	if index < 0:
		UIJuice.play(UIJuice.Sfx.CLOSE)


func _finish(index: int) -> void:
	_closing = false
	visible = false
	GameManager.choice_open = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _prev_mouse_mode
	for child in _row.get_children():
		child.queue_free()
	var callback := _on_pick
	_on_pick = Callable()
	if callback.is_valid():
		callback.call(index)


# Swallow Escape / Tab while open so the pause and Tab menus stay shut.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"menu"):
		get_viewport().set_input_as_handled()


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
