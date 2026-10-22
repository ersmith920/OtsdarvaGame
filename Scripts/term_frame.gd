# The screen of a full-screen menu drawn as one old terminal display (pause menu, gun store,
# Combiner): a thin frame around the whole screen with "+" registration marks and tick
# rulers down its sides, an inverted title bar across the top (system name, the screen's
# title, live status cells on the right), and a key-hint line along the bottom with a
# blinking cursor and a session clock. A faint refresh bar rolls down the screen.
#
#   var frame := TermFrame.new()
#   frame.title = "SYSTEM PAUSED"
#   frame.hints = "ESC  RESUME    LMB  SELECT"
#   menu.add_child(frame)          # under the menu's own windows
#   frame.status = ["T+03:12", "SCRAP 1234"]
#   frame.boot()                   # traces itself on
class_name TermFrame
extends Control

## Gap between the frame and the screen edge, and the title bar's height.
const INSET := 14.0
const BAR_H := 26.0
const SYSTEM := "OTSDARVA//OS"

var title := "":
	set(v): title = v; queue_redraw()
## Status cells shown right-aligned in the title bar.
var status : Array = []:
	set(v): status = v; queue_redraw()
## The key-hint line along the bottom.
var hints := "":
	set(v): hints = v; queue_redraw()
var accent := HudStyle.ORANGE

var _boot := 1.0
var _time := 0.0
var _session_start := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_session_start = Time.get_ticks_msec()


## Traces the frame on and slides the title bar open (call when the menu opens).
func boot(delay := 0.0) -> void:
	_boot = 0.0
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(self, "_boot", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var font := HudStyle.TERM_BOLD
	var thin := HudStyle.TERM_FONT
	var r := Rect2(Vector2(INSET, INSET), size - Vector2(INSET, INSET) * 2.0)
	var b := _boot
	var line := Color(accent, 0.8)

	# The frame, traced on from the top-left corner.
	HudStyle.draw_frame(self, r, line, b, 1.5, 0.0, 0.0)
	# Registration marks on the corners and the middles of the edges.
	if b > 0.6:
		var a := Color(accent, smoothstep(0.6, 1.0, b))
		for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
				Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y),
				Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]:
			draw_line(p - Vector2(7, 0), p + Vector2(7, 0), a, 1.5)
			draw_line(p - Vector2(0, 7), p + Vector2(0, 7), a, 1.5)
	# Tick rulers down both sides (every 12 px, longer every 60).
	var ruler_a := Color(accent, 0.4 * b)
	var y := r.position.y + BAR_H + 12.0
	var n := 0
	while y < r.end.y - 30.0:
		var long := n % 5 == 0
		var tick := 9.0 if long else 4.0
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + tick, y), ruler_a, 1.0)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x - tick, y), ruler_a, 1.0)
		y += 12.0
		n += 1

	# Title bar: inverted, opening out from the left.
	var bar := Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2.0) * smoothstep(0.1, 0.7, b), BAR_H))
	draw_rect(bar, accent)
	if b > 0.5:
		var fs := 14
		var base := bar.position.y + BAR_H * 0.5 + fs * 0.36
		var head := "%s  >  %s" % [SYSTEM, title.to_upper()]
		draw_string(font, Vector2(bar.position.x + 12.0, base), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.INK)
		# Status cells, right to left, divided by bars.
		var x := r.end.x - 12.0
		for i in range(status.size() - 1, -1, -1):
			var cell := String(status[i])
			var w := font.get_string_size(cell, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			x -= w
			draw_string(font, Vector2(x, base), cell, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.INK)
			x -= 12.0
			draw_rect(Rect2(x, bar.position.y + 5.0, 2.0, BAR_H - 10.0), HudStyle.INK)
			x -= 12.0

	# Bottom line: key hints, then a session clock and a blinking cursor on the right.
	if b > 0.8:
		var fs2 := 13
		var by := r.end.y - 10.0
		draw_line(Vector2(r.position.x + 10.0, by - 20.0), Vector2(r.end.x - 10.0, by - 20.0), Color(accent, 0.35), 1.0)
		draw_string(thin, Vector2(r.position.x + 14.0, by), hints, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, accent)
		var secs := (Time.get_ticks_msec() - _session_start) / 1000
		@warning_ignore("integer_division")
		var clock := "SESSION %02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]
		var cw := thin.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(thin, Vector2(r.end.x - 34.0 - cw, by), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(accent, 0.7))
		if fmod(_time, 1.0) < 0.55:
			draw_rect(Rect2(r.end.x - 26.0, by - fs2 * 0.8, 9.0, fs2 * 0.95), accent)

	# The refresh bar: a faint band rolling slowly down the screen.
	var band_y := fmod(_time * 120.0, r.size.y + 160.0) - 80.0 + r.position.y
	for i in 8:
		var h := 10.0
		draw_rect(Rect2(r.position.x, band_y + i * h, r.size.x, h), Color(accent, 0.012 * (1.0 - absf(i - 3.5) / 4.0)))
