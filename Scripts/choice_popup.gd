# Pick-one popup: pauses the game and shows tall cards side by side; clicking one picks it.
# Escape can't close it (a choice must be made). Reusable for anything that offers a choice
# (gun stores now, level-up upgrades later). Lives on the HUD; reach it with GameManager.choice_popup.
#
#   GameManager.choice_popup.open("Gun Store", cards, func(index): ...)
#
# Each card is any Control you build (see GunCard). The popup wraps each one in a
# clickable frame in that card's color, so the content doesn't need to handle input.
class_name ChoicePopup
extends Control

@export_group("Look")
## Color over the frozen game behind the cards.
@export var dim_color := Color(0.0, 0.0, 0.0, 0.55)
@export var title_font : Font = preload("res://Fonts/KHMenu-Bold.otf")
@export var title_font_size := 34
@export var card_size := Vector2(300, 470)
@export var card_gap := 28
@export var card_padding := 16
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
var _row : HBoxContainer
var _on_pick : Callable
var _opened_at_ms := 0
var _was_paused := false
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the tree is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	GameManager.choice_popup = self

	var dim := ColorRect.new()
	dim.color = dim_color
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if title_font != null:
		_title.add_theme_font_override("font", title_font)
	_title.add_theme_font_size_override("font_size", title_font_size)
	column.add_child(_title)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", card_gap)
	column.add_child(_row)


func is_open() -> bool:
	return visible


## Shows the cards and pauses the game until one is clicked.
## cards: one Control per option. Set meta "color" on a card to color its frame.
## on_pick: called with the index of the chosen card, after the game unpauses.
func open(title: String, cards: Array[Control], on_pick: Callable) -> void:
	if visible:
		push_warning("ChoicePopup is already open")
		return
	_on_pick = on_pick
	_title.text = title
	_title.visible = not title.is_empty()

	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for i in cards.size():
		_row.add_child(_wrap_card(cards[i], i))

	_was_paused = get_tree().paused
	_prev_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	GameManager.choice_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_opened_at_ms = Time.get_ticks_msec()
	visible = true
	_play(open_sound)


# A Button (fires on release, so the click can't leak into shooting after unpausing)
# with the card's content inside it.
func _wrap_card(content: Control, index: int) -> Button:
	var color : Color = content.get_meta(&"color", Color(0.7, 0.7, 0.7))
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE   # keeps Space / Enter from picking a card
	button.clip_contents = false
	button.add_theme_stylebox_override("normal", _card_style(color, glow_size, 0.0))
	button.add_theme_stylebox_override("hover", _card_style(color, hover_glow_size, 0.12))
	button.add_theme_stylebox_override("pressed", _card_style(color, hover_glow_size, 0.22))
	button.add_theme_stylebox_override("hover_pressed", _card_style(color, hover_glow_size, 0.22))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_pick.bind(index))
	button.mouse_entered.connect(_play.bind(hover_sound))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, card_padding)
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ignore_mouse(content)
	margin.add_child(content)
	return button


func _card_style(color: Color, glow: int, lift: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_bg.lerp(color.darkened(0.6), 0.25 + lift)
	style.set_corner_radius_all(8)
	style.set_border_width_all(card_border)
	style.border_color = color.lerp(Color.WHITE, 0.35 + lift)
	style.shadow_color = Color(color, 0.55 + lift)
	style.shadow_size = glow
	style.shadow_offset = Vector2.ZERO
	return style


# Card contents must never take the click from the frame.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _pick(index: int) -> void:
	if not visible or Time.get_ticks_msec() - _opened_at_ms < int(input_delay * 1000.0):
		return
	_play(pick_sound)
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
