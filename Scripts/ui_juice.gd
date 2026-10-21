# Shared UI "juice": the small animations, sounds and effects every menu uses, so timing and
# easing match everywhere. All of it keeps working while the game is paused (menus pause it).
#
#   UIJuice.pop_in(panel)                     fade + scale in (slight overshoot)
#   UIJuice.pop_out(panel, func(): ...)       shrink + fade out, then run the callback
#   UIJuice.deal_in([card_a, card_b, ...])    one after another, flipping in
#   UIJuice.flip_in(card)                     a card turning over (scale x 0 -> 1)
#   UIJuice.hover_lift(control)               lifts on hover, presses in on click (+ sounds)
#   UIJuice.flash(control) / UIJuice.punch(control)
#   UIJuice.burst(overlay, center, color, rarity)   sparks flying out (bigger for higher rarity)
#   UIJuice.play(UIJuice.Sfx.CLICK)
#   UIJuice.glass_style() / UIJuice.blur_material()
class_name UIJuice
extends RefCounted

enum Sfx { HOVER, CLICK, OPEN, CLOSE, PICK, REWARD, JACKPOT }

## Master volume for all UI sounds (dB).
const VOLUME_DB := -10.0
## Seconds for pop-ins and pop-outs.
const POP_TIME := 0.18
const DEAL_STAGGER := 0.07
const HOVER_SCALE := 1.04
const PRESS_SCALE := 0.96

static var _sounds := {}
static var _chimes := []
static var _chimes_started := false
## Number of chimes (one per rarity) and how much louder than the other UI sounds they are.
const CHIME_COUNT := 6
const CHIME_VOLUME_DB := 2.0
static var _last_hover_ms := 0
static var _blur : ShaderMaterial
static var _spark_mat : CanvasItemMaterial


# ======================================================================
# Motion
# ======================================================================

## A tween that runs while the game is paused, owned by `node` (dies with it).
static func tween_of(node: Node) -> Tween:
	var t := node.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t


## Scales from the control's center from now on (and keeps it centered if it resizes).
static func center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	if not c.has_meta(&"juice_pivot"):
		c.set_meta(&"juice_pivot", true)
		c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)


## Fades and scales a control in, with a small overshoot. delay: seconds to wait first.
static func pop_in(c: Control, delay := 0.0, from_scale := 0.88, time := POP_TIME) -> Tween:
	center_pivot(c)
	c.scale = Vector2.ONE * from_scale
	c.modulate.a = 0.0
	var t := tween_of(c)
	t.set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, time).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, time * 0.7).set_delay(delay)
	return t


## Shrinks and fades a control out, then calls done (if valid).
static func pop_out(c: Control, done := Callable(), time := POP_TIME * 0.7) -> Tween:
	center_pivot(c)
	var t := tween_of(c)
	t.set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE * 0.9, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(c, "modulate:a", 0.0, time)
	if done.is_valid():
		t.chain().tween_callback(done)
	return t


## A card turning over: squashed flat, then opening up (with a small bounce).
static func flip_in(c: Control, delay := 0.0, time := 0.22) -> Tween:
	center_pivot(c)
	c.scale = Vector2(0.0, 1.0)
	c.modulate.a = 0.0
	var t := tween_of(c)
	t.set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, time).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, time * 0.5).set_delay(delay)
	return t


## Several controls flipping in one after another.
static func deal_in(controls: Array, start_delay := 0.0, stagger := DEAL_STAGGER) -> void:
	for i in controls.size():
		flip_in(controls[i], start_delay + i * stagger)


## A quick scale bump (e.g. when something changes).
static func punch(c: Control, amount := 0.12, time := 0.22) -> Tween:
	center_pivot(c)
	var t := tween_of(c)
	t.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), time * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## A bright flash that fades back (brightens everything the control draws).
static func flash(c: Control, strength := 1.0, time := 0.3) -> Tween:
	var t := tween_of(c)
	c.self_modulate = Color(1, 1, 1, 1) * (1.0 + 1.5 * strength)
	t.tween_property(c, "self_modulate", Color.WHITE, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t


## Hover: grows a little and plays a soft tick. Click: presses in and plays a click.
## Works on any control that gets mouse events (buttons, or panels with MOUSE_FILTER_PASS/STOP).
static func hover_lift(c: Control, sounds := true) -> void:
	if c.has_meta(&"juice_hover"):
		return
	c.set_meta(&"juice_hover", true)
	center_pivot(c)
	var to := func(s: float, time: float) -> void:
		if c.has_meta(&"juice_tween"):
			var old : Tween = c.get_meta(&"juice_tween")
			if old != null and old.is_valid():
				old.kill()
		var t := tween_of(c)
		t.tween_property(c, "scale", Vector2.ONE * s, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		c.set_meta(&"juice_tween", t)
	c.mouse_entered.connect(func() -> void:
		if c is BaseButton and (c as BaseButton).disabled:
			return
		to.call(HOVER_SCALE, 0.14)
		if sounds:
			play(Sfx.HOVER))
	c.mouse_exited.connect(func() -> void: to.call(1.0, 0.16))
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if c is BaseButton and (c as BaseButton).disabled:
				return
			if e.pressed:
				to.call(PRESS_SCALE, 0.06)
				if sounds:
					play(Sfx.CLICK)
			else:
				to.call(HOVER_SCALE, 0.12))


## A soft breathing glow (for a button that's waiting to be pressed). Stop with stop_pulse().
static func pulse(c: Control, strength := 0.35, period := 1.1) -> void:
	stop_pulse(c)
	var t := tween_of(c).set_loops()
	t.tween_property(c, "self_modulate", Color.WHITE * (1.0 + strength), period * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(c, "self_modulate", Color.WHITE, period * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.set_meta(&"juice_pulse", t)


static func stop_pulse(c: Control) -> void:
	if c.has_meta(&"juice_pulse"):
		var t : Tween = c.get_meta(&"juice_pulse")
		if t != null and t.is_valid():
			t.kill()
		c.remove_meta(&"juice_pulse")
	c.self_modulate = Color.WHITE


# ======================================================================
# Sparks
# ======================================================================

## Sparks flying out from `center` (global position) in `color`. The higher the rarity, the
## more and bigger the sparks (Mythic sparks are rainbow). `overlay` is any Control they're
## drawn on top of (they're top-level, so it just needs to be on the right layer).
static func burst(overlay: Control, center: Vector2, color: Color, rarity := Rarity.COMMON, spread := 1.0) -> void:
	if _spark_mat == null:
		_spark_mat = CanvasItemMaterial.new()
		_spark_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var count := 10 + rarity * 8
	var reach := (90.0 + rarity * 40.0) * spread
	var mythic := rarity >= Rarity.MYTHIC
	for i in count:
		var spark := ColorRect.new()
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.top_level = true
		var length := randf_range(6.0, 16.0) * (1.0 + rarity * 0.15)
		spark.size = Vector2(length, randf_range(2.0, 4.0))
		spark.pivot_offset = Vector2(0, spark.size.y * 0.5)
		# Mythic sparks are every color of the rainbow; the rest are the rarity color.
		var base := Color.from_hsv(randf(), 0.55, 1.0) if mythic else color
		spark.color = base.lerp(Color.WHITE, randf_range(0.0, 0.4))
		spark.material = _spark_mat
		overlay.add_child(spark)
		var angle := randf() * TAU
		var dir := Vector2.from_angle(angle)
		spark.rotation = angle
		spark.global_position = center
		var t := tween_of(spark)
		t.set_parallel(true)
		var time := randf_range(0.35, 0.65) * (1.0 + rarity * 0.08)
		t.tween_property(spark, "global_position", center + dir * reach * randf_range(0.5, 1.0), time) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(spark, "scale", Vector2(0.2, 1.0), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(spark, "modulate:a", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(spark.queue_free)
	# A soft ring expanding out behind the sparks.
	var ring := _Ring.new()
	ring.color = color
	ring.top_level = true
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.material = _spark_mat
	if mythic:
		Rarity.paint(ring, Rarity.MYTHIC)
	overlay.add_child(ring)
	ring.global_position = center
	var rt := tween_of(ring)
	rt.set_parallel(true)
	rt.tween_property(ring, "radius", reach * 1.1, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.45)
	rt.chain().tween_callback(ring.queue_free)


# A circle outline drawn around its own position (for burst()).
class _Ring extends Control:
	var color := Color.WHITE
	var radius := 4.0:
		set(v):
			radius = v
			queue_redraw()
	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, 3.0, true)


# ======================================================================
# Sounds (made in code: short synth blips, so no sound files are needed)
# ======================================================================

## Plays a UI sound. Hover ticks are rate-limited so sweeping over a row isn't noisy.
static func play(kind: Sfx, pitch := 1.0) -> void:
	if kind == Sfx.HOVER:
		var now := Time.get_ticks_msec()
		if now - _last_hover_ms < 45:
			return
		_last_hover_ms = now
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = _sound(kind)
	audio.volume_db = VOLUME_DB
	audio.pitch_scale = pitch * randf_range(0.97, 1.03)
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


## The item-get chime for a rarity (Rarity.COMMON .. MYTHIC): a quick, bright bell
## arpeggio climbing to a held note, in the spirit of KH2's ability / level-up jingle. Rarer
## items get a longer climb, a full chord on the last note and a glittering sparkle tail.
## Built off the main thread ahead of time (warm_chimes) so the first pickup doesn't hitch.
static func play_chime(rarity: int) -> void:
	rarity = clampi(rarity, 0, CHIME_COUNT - 1)
	var stream : AudioStreamWAV = _chimes[rarity] if _chimes.size() == CHIME_COUNT else _build_chime(rarity)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = VOLUME_DB + CHIME_VOLUME_DB
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)


## Builds every chime on a worker thread. Safe to call more than once.
static func warm_chimes() -> void:
	if _chimes_started:
		return
	_chimes_started = true
	WorkerThreadPool.add_task(func() -> void:
		var built := []
		for r in CHIME_COUNT:
			built.append(_build_chime(r))
		_chimes = built)   # one assignment, so the main thread sees all or nothing


static func _build_chime(rarity: int) -> AudioStreamWAV:
	const RATE := 32000
	# Major arpeggio climbing through the octaves (semitones above the root).
	const STEPS := [0, 4, 7, 12, 16, 19, 24, 28, 31]
	const ROOT := 659.26   # E5
	var count : int = [3, 4, 5, 6, 7, 8][rarity]
	var step_time := 0.07 - 0.004 * rarity
	var hold := 0.8 + 0.15 * rarity
	var length := step_time * count + hold + 0.6
	var buf := PackedFloat32Array()
	buf.resize(int(length * RATE))

	var freq_of := func(semi: float) -> float: return ROOT * pow(2.0, semi / 12.0)
	# The climb.
	for i in count:
		var last := i == count - 1
		_bell(buf, RATE, i * step_time, freq_of.call(STEPS[i]), hold if last else 0.35, 0.55 if last else 0.4)
	var end_t := (count - 1) * step_time
	var top : float = STEPS[count - 1]
	# Rare and up: the held note becomes a chord.
	if rarity >= Rarity.RARE:
		_bell(buf, RATE, end_t, freq_of.call(top - 5.0), hold, 0.22)
		_bell(buf, RATE, end_t, freq_of.call(top - 8.0), hold, 0.18)
	if rarity >= Rarity.LEGENDARY:
		_bell(buf, RATE, end_t, freq_of.call(top - 12.0), hold * 1.2, 0.25)
	# Uncommon and up: sparkle, quiet high pentatonic glints tumbling after the top note.
	if rarity >= Rarity.UNCOMMON:
		var glints := 3 + rarity * 3
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234 + rarity   # the same sparkle every time
		const PENTA := [0, 2, 4, 7, 9]
		for g in glints:
			var t := end_t + 0.04 + g * (0.05 + 0.01 * rng.randf())
			var semi : float = 24 + PENTA[rng.randi() % 5] + 12 * (rng.randi() % 2)
			_bell(buf, RATE, t, freq_of.call(semi), 0.18, 0.12 * (1.0 - float(g) / glints) + 0.04)

	# Echo taps for a little space (KH's jingles ring out).
	var echo := PackedFloat32Array(buf)
	for tap in [[0.11, 0.28], [0.19, 0.16], [0.31, 0.09]]:
		var d := int(tap[0] * RATE)
		for i in range(d, buf.size()):
			echo[i] += buf[i - d] * tap[1]
	# Normalize, then fade the very end.
	var peak := 0.001
	for v in echo:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	var fade := int(0.05 * RATE)
	var data := PackedByteArray()
	data.resize(echo.size() * 2)
	for i in echo.size():
		var v := echo[i] * gain
		if i > echo.size() - fade:
			v *= float(echo.size() - i) / fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# Adds one bell/glockenspiel-like note into buf: a sine with a slightly detuned twin (shimmer)
# plus higher partials (one inharmonic, for the metallic ring) that die away faster.
static func _bell(buf: PackedFloat32Array, rate: int, start: float, freq: float, length: float, vol: float) -> void:
	const PARTIALS := [[1.0, 1.0, 1.0], [2.0, 0.32, 2.2], [3.01, 0.1, 3.5], [4.16, 0.07, 5.0]]   # ratio, amp, decay x
	var first := int(start * rate)
	var count := int(length * rate)
	var w := TAU / rate
	for i in count:
		var idx := first + i
		if idx >= buf.size():
			break
		var t := float(i) / rate
		var attack := minf(t / 0.003, 1.0)
		var base := exp(-t * 4.5 / length)
		var v := 0.0
		for p in PARTIALS:
			var f : float = freq * p[0]
			if f > rate * 0.45:
				continue   # above what the sample rate can hold: it would alias into noise
			v += p[1] * exp(-t * p[2] * 4.0 / length) * sin(w * f * i)
		v += 0.35 * base * sin(w * freq * 1.004 * i)   # detuned twin
		buf[idx] += vol * attack * base * v


static func _sound(kind: Sfx) -> AudioStreamWAV:
	if _sounds.has(kind):
		return _sounds[kind]
	var wav : AudioStreamWAV
	match kind:
		Sfx.HOVER: wav = _synth([[1800.0, 0.03, 0.25]])
		Sfx.CLICK: wav = _synth([[900.0, 0.045, 0.5], [1350.0, 0.03, 0.25]])
		Sfx.OPEN: wav = _synth([[520.0, 0.07, 0.35], [780.0, 0.09, 0.35]], true)
		Sfx.CLOSE: wav = _synth([[780.0, 0.06, 0.3], [520.0, 0.08, 0.3]], true)
		Sfx.PICK: wav = _synth([[660.0, 0.06, 0.45], [990.0, 0.08, 0.45], [1320.0, 0.14, 0.4]], true)
		Sfx.REWARD: wav = _synth([[523.0, 0.08, 0.4], [659.0, 0.08, 0.4], [784.0, 0.08, 0.4], [1047.0, 0.3, 0.45]], true)
		Sfx.JACKPOT: wav = _synth([[523.0, 0.07, 0.4], [659.0, 0.07, 0.4], [784.0, 0.07, 0.4], [1047.0, 0.07, 0.4],
				[1319.0, 0.07, 0.4], [1568.0, 0.55, 0.5]], true)
	_sounds[kind] = wav
	return wav


# notes: [frequency, seconds, volume]. sequence: notes play one after another (else stacked).
static func _synth(notes: Array, sequence := false) -> AudioStreamWAV:
	const RATE := 22050
	var total := 0.0
	for n in notes:
		total = total + n[1] if sequence else maxf(total, n[1])
	var frames := int((total + 0.05) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(frames)
	var start := 0.0
	for n in notes:
		var freq : float = n[0]
		var length : float = n[1]
		var vol : float = n[2]
		var first := int(start * RATE)
		var count := int((length + 0.04) * RATE)
		for i in count:
			var idx := first + i
			if idx >= frames:
				break
			var t := float(i) / RATE
			# Quick attack, smooth decay; a little octave on top makes it bell-like.
			var env := minf(t / 0.004, 1.0) * exp(-t * 6.0 / maxf(length, 0.01))
			buf[idx] += vol * env * (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t))
		if sequence:
			start += length
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# ======================================================================
# Shared looks
# ======================================================================

## The dark "glass" panel used across menus: see-through dark, thin light border, soft glow.
static func glass_style(radius := 8, border := Color(1, 1, 1, 0.14), bg := Color(0.04, 0.045, 0.06, 0.82)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.set_content_margin_all(12)
	return style


## For the backdrop behind a paused menu: blurs and darkens the game behind it.
## Put it on a full-screen ColorRect: the rect's color is the tint (its alpha = how dark).
## Each call gives a new material, so fade_backdrop() can fade one menu's backdrop alone.
static func blur_material() -> ShaderMaterial:
	if _blur == null:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 2.5;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec3 raw = texture(screen, SCREEN_UV).rgb;
	// A few offset samples from a blurry mip level: soft and cheap.
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 sum = textureLod(screen, SCREEN_UV, blur).rgb * 0.4;
	sum += textureLod(screen, SCREEN_UV + vec2(px.x, px.y), blur).rgb * 0.15;
	sum += textureLod(screen, SCREEN_UV + vec2(-px.x, px.y), blur).rgb * 0.15;
	sum += textureLod(screen, SCREEN_UV + vec2(px.x, -px.y), blur).rgb * 0.15;
	sum += textureLod(screen, SCREEN_UV + vec2(-px.x, -px.y), blur).rgb * 0.15;
	vec3 dimmed = mix(sum, COLOR.rgb, COLOR.a);
	COLOR = vec4(mix(raw, dimmed, amount), 1.0);
}
"""
		_blur = ShaderMaterial.new()
		_blur.shader = shader
	var mat := _blur.duplicate() as ShaderMaterial
	return mat


## Fades a blur backdrop (a ColorRect using blur_material()) in (to 1) or out (to 0).
static func fade_backdrop(rect: ColorRect, to: float, time := 0.2) -> Tween:
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return null
	var t := tween_of(rect)
	t.tween_property(mat, "shader_parameter/amount", to, time)
	return t
