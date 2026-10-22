# Hostile counter, in the mission panel (top left, see hud_timer.gd). Counts node enemies and
# swarm enemies. Ticks up with a brief amber flash when the count rises.
extends Label

const FONT_SIZE := 22
const REFRESH_INTERVAL := 0.1   # seconds between recounts; no need to do it every frame

var _last_count := -1
var _since_refresh := 0.0
var _flash := 0.0
@export var font: Font   # unused now: the HUD uses HudStyle's fonts (kept so the scene still loads)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = HudStyle.MISSION_POS + Vector2(HudStyle.MISSION_SIZE.x - 10 - 120, HudStyle.MISSION_ROW_HOSTILE + 3)
	size = Vector2(120, 22)
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.add_phosphor(self, HudStyle.ORANGE_HOT)
	add_theme_font_override("font", HudStyle.NUMBER_FONT)
	add_theme_font_size_override("font_size", FONT_SIZE)
	_refresh()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_INTERVAL:
		_since_refresh = 0.0
		_refresh()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		add_theme_color_override("font_color", HudStyle.ORANGE_HOT.lerp(Color.WHITE, _flash))


func _refresh() -> void:
	var count := EnemyManager.get_total_count()
	# Only touch the text when the number actually changes.
	if count != _last_count:
		if count > _last_count and _last_count >= 0:
			_flash = 1.0
		_last_count = count
		text = "%04d" % count
		add_theme_color_override("font_color", HudStyle.ORANGE_HOT.lerp(Color.WHITE, _flash))
