# Gold counter, top left of the HUD, just under the enemy count.
extends Label

const PADDING := 16
const FONT_SIZE := 24
const ROW_OFFSET := 36   # pushes it below the EnemyCount label

@export var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, PADDING)
	offset_top += ROW_OFFSET
	offset_bottom += ROW_OFFSET

	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", FONT_SIZE)

	text = "Gold: 0"
	GameManager.gold_changed.connect(func(total: int) -> void: text = "Gold: %d" % total)
