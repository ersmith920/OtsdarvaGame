# Enemy counter, top left of the HUD. Counts everything in the lock_target group.
extends Label

const PADDING := 16
const FONT_SIZE := 24
const REFRESH_INTERVAL := 0.1   # seconds between recounts; no need to do it every frame

var _last_count := -1
var _since_refresh := 0.0
@export var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, PADDING)
	
	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", FONT_SIZE)

	_refresh()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_INTERVAL:
		_since_refresh = 0.0
		_refresh()


func _refresh() -> void:
	var count := EnemyManager.enemies.size()

	# Only touch the text when the number actually changes.
	if count != _last_count:
		_last_count = count
		text = "Enemies: %d" % count

	# Only touch the text when the number actually changes.
	if count != _last_count:
		_last_count = count
		text = "Enemies: %d" % count
