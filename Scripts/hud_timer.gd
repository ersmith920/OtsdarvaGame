# Run timer, top center of the HUD. Shows GameManager.levelTime as M:SS.
extends Label

const TOP_PADDING := 16
const FONT_SIZE := 32

var _last_second := -1

@export var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Span the full width and center the text, so it stays centered as digits change.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, TOP_PADDING)

	add_theme_font_size_override("font_size", FONT_SIZE)
	if font != null:
		add_theme_font_override("font", font)

	_update_text()


func _process(_delta: float) -> void:
	# Only touch the text when the displayed second actually changes.
	if int(GameManager.levelTime) != _last_second:
		_update_text()


func _update_text() -> void:
	_last_second = int(GameManager.levelTime)
	@warning_ignore("integer_division")
	text = "%d:%02d" % [_last_second / 60, _last_second % 60]
