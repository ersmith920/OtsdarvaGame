# Gold counter, top left of the HUD, just under the enemy count: [glowing coin] x123
# The coin mimics the floor coins: brightened by the same tint x strength, plus a soft
# additive halo standing in for the 3D bloom (the HUD layer doesn't get the scene's Glow).
extends Label

const PADDING := 16
const FONT_SIZE := 24
const ROW_OFFSET := 36   # pushes it below the EnemyCount label

@export var font: Font

@export_group("Icon")
## Coin art. Use the same image as the floor coins (e.g. gold1.png). Empty = generated gold disc.
@export var icon_texture: Texture2D
## Icon width and height, in pixels.
@export var icon_size := 28.0
## Gap between the icon and the text, in pixels.
@export var icon_gap := 6.0
## Text shown before the amount.
@export var prefix := "x"
## Crisp pixels instead of smoothing. Turn off for soft art.
@export var pixel_art := true

@export_group("Glow")
## Match these to the GoldPickup scene's Glow settings so the HUD coin looks like the floor ones.
@export var glow_tint := Color(0.92, 0.93, 0.64)
@export_range(1.0, 4.0, 0.05) var glow_strength := 2.0
## Size of the halo area as a multiple of the icon. 2 = halo hugs the coin, higher = spreads wider.
@export_range(1.5, 4.0, 0.05) var halo_size := 2.4
## Halo brightness. 0 = no halo.
@export_range(0.0, 1.0, 0.01) var halo_opacity := 0.6

@export_group("Pickup Pulse")
## Kick every gold gain adds, however small. Kicks stack, so a stream of pickups builds up.
@export var pulse_base := 0.25
## Extra kick per gold gained, so big pickups hit harder than small ones.
@export var pulse_per_gold := 0.01
## Cap on the stacked kick, so a huge haul can't blow the counter up forever.
@export var pulse_max := 2.0
## How fast the kick dies down. Higher = snappier.
@export var pulse_decay := 8.0
## Extra size per unit of kick (0.15 = 15% bigger at a kick of 1).
@export var grow_amount := 0.15
## Shake distance in pixels per unit of kick.
@export var shake_amount := 3.0
## Extra halo brightness per unit of kick.
@export var flash_amount := 0.5

var _icon: TextureRect
var _halo: TextureRect
var _kick := 0.0
var _last_total := 0
var _base_pos := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, PADDING)
	offset_top += ROW_OFFSET
	offset_bottom += ROW_OFFSET
	# Make room on the left for the coin, which sits just outside the label's text.
	offset_left += icon_size + icon_gap
	offset_right += icon_size + icon_gap

	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", FONT_SIZE)

	_build_icon()
	resized.connect(_place_icon)
	_place_icon()

	text = "%s%d" % [prefix, 0]
	GameManager.gold_changed.connect(_on_gold_changed)
	_base_pos = position


func _on_gold_changed(total: int) -> void:
	text = "%s%d" % [prefix, total]
	var gained := total - _last_total
	_last_total = total
	if gained > 0:
		_kick = minf(_kick + pulse_base + pulse_per_gold * gained, pulse_max)


func _process(delta: float) -> void:
	if _kick <= 0.001:
		if _kick != 0.0:
			_kick = 0.0
			scale = Vector2.ONE
			position = _base_pos
			if _halo != null:
				_halo.self_modulate = Color.WHITE
		return
	_kick *= exp(-pulse_decay * delta)
	# Grow from the coin's center, so the counter swells in place instead of sliding.
	pivot_offset = Vector2(-(icon_gap + icon_size * 0.5), size.y * 0.5)
	scale = Vector2.ONE * (1.0 + grow_amount * _kick)
	position = _base_pos + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amount * _kick
	if _halo != null:
		var bright := 1.0 + flash_amount * _kick
		_halo.self_modulate = Color(bright, bright, bright, 1.0)


func _build_icon() -> void:
	var tex := icon_texture if icon_texture != null else GoldPickup._get_placeholder()

	_icon = TextureRect.new()
	_icon.texture = tex
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art and icon_texture != null \
			else CanvasItem.TEXTURE_FILTER_LINEAR
	_icon.size = Vector2(icon_size, icon_size)
	# Same brightening as the floor coin's material (tint x strength). self_modulate so the halo isn't affected.
	var boosted := glow_tint * glow_strength
	_icon.self_modulate = Color(boosted.r, boosted.g, boosted.b, 1.0)
	add_child(_icon)

	if halo_opacity <= 0.0:
		return
	var halo_tex := _make_halo(tex)
	if halo_tex == null:
		return
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var halo := TextureRect.new()
	halo.texture = halo_tex
	halo.material = additive
	halo.show_behind_parent = true
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var s := icon_size * halo_size
	halo.size = Vector2(s, s)
	halo.position = Vector2(icon_size - s, icon_size - s) * 0.5   # centered on the coin
	halo.modulate = Color(glow_tint.r, glow_tint.g, glow_tint.b, halo_opacity)
	_icon.add_child(halo)
	_halo = halo


# Coin sits to the left of the text, vertically centered on it.
func _place_icon() -> void:
	if _icon != null:
		_icon.position = Vector2(-(icon_size + icon_gap), (size.y - icon_size) * 0.5)


# Builds a blurred copy of the coin with empty space around it, for the halo.
# Repeated halving averages the pixels; scaling back up smoothly gives the soft falloff.
static func _make_halo(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	# Canvas twice the coin's size with the coin centered, so the blur has room to spread.
	var canvas := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w / 2, h / 2))
	var full := canvas.get_size()
	for i in 3:
		canvas.resize(maxi(canvas.get_width() / 2, 1), maxi(canvas.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	canvas.resize(full.x, full.y, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(canvas)
