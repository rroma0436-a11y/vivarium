extends Control
## Керування польотом літака (і ручне керування Beep) (кілька пальців одночасно):
## ліворуч — джойстик (вліво/вправо — поворот, вгору — швидше, вниз — повільніше),
## праворуч — кнопки «вгору» й «вниз» (тримати), «В ангар» — літак сам летить на аеродром, «Сісти» — сідає тут.

signal home_pressed
signal land_pressed

var home_text := "В ангар"
var land_text := "Сісти"
var show_down := true                  # кнопка «вниз» (для Ніки не треба)
var up_big := "▲"
var up_small := "вгору"

var joy := Vector2.ZERO
var climb := 0.0
var _joy_touch := -1
var _up_touch := -1
var _down_touch := -1
var _font: Font
const JOY_R := 105.0
const KNOB_R := 44.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	visible = false


func _joy_c() -> Vector2:
	return Vector2(170, size.y - 170)


func _up_rect() -> Rect2:
	return Rect2(size.x - 170, size.y - 330, 140, 130)


func _down_rect() -> Rect2:
	return Rect2(size.x - 170, size.y - 180, 140, 130)


func _home_rect() -> Rect2:
	return Rect2(size.x - 390, size.y - 130, 190, 90)


func _land_rect() -> Rect2:
	return Rect2(size.x - 390, size.y - 240, 190, 90)


func reset() -> void:
	joy = Vector2.ZERO
	climb = 0.0
	_joy_touch = -1
	_up_touch = -1
	_down_touch = -1
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if not (e is InputEventScreenTouch or e is InputEventScreenDrag):
		return
	var le := make_input_local(e)
	var p: Vector2 = le.position
	var idx: int = e.index
	var used := false
	if e is InputEventScreenTouch:
		if e.pressed:
			if p.distance_to(_joy_c()) < JOY_R * 1.5 and _joy_touch < 0:
				_joy_touch = idx
				_set_joy(p)
				used = true
			elif _up_rect().grow(12).has_point(p):
				_up_touch = idx
				used = true
			elif show_down and _down_rect().grow(12).has_point(p):
				_down_touch = idx
				used = true
			elif _home_rect().grow(8).has_point(p):
				var au = get_node_or_null("/root/Main/Audio")
				if au:
					au.play("click", -6.0)
				home_pressed.emit()
				used = true
			elif land_text != "" and _land_rect().grow(8).has_point(p):
				var au2 = get_node_or_null("/root/Main/Audio")
				if au2:
					au2.play("click", -6.0)
				land_pressed.emit()
				used = true
		else:
			if idx == _joy_touch:
				_joy_touch = -1
				joy = Vector2.ZERO
				used = true
			if idx == _up_touch:
				_up_touch = -1
				used = true
			if idx == _down_touch:
				_down_touch = -1
				used = true
	elif e is InputEventScreenDrag:
		if idx == _joy_touch:
			_set_joy(p)
			used = true
		elif idx == _up_touch or idx == _down_touch:
			used = true
	climb = (1.0 if _up_touch >= 0 else 0.0) - (1.0 if _down_touch >= 0 else 0.0)
	if used:
		get_viewport().set_input_as_handled()
		queue_redraw()


func _set_joy(p: Vector2) -> void:
	var d := (p - _joy_c()) / JOY_R
	if d.length() > 1.0:
		d = d.normalized()
	joy = Vector2(d.x, -d.y)          # y: вгору на екрані — швидше


func _draw() -> void:
	var c := _joy_c()
	draw_circle(c, JOY_R, Color(1, 1, 1, 0.22))
	draw_arc(c, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.75), 4.0, true)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var tip := c + Vector2(cos(a), sin(a)) * (JOY_R - 14)
		var side := Vector2(-sin(a), cos(a)) * 9
		var back := c + Vector2(cos(a), sin(a)) * (JOY_R - 30)
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(1, 1, 1, 0.7))
	var k := c + Vector2(joy.x, -joy.y) * JOY_R
	draw_circle(k, KNOB_R, Color(0.95, 0.35, 0.3, 0.92))
	draw_arc(k, KNOB_R, 0, TAU, 32, Color(1, 1, 1, 0.9), 3.0, true)
	_button(_up_rect(), up_big, up_small, _up_touch >= 0, Color(0.3, 0.65, 0.85))
	if show_down:
		_button(_down_rect(), "▼", "вниз", _down_touch >= 0, Color(0.3, 0.65, 0.85))
	_button(_home_rect(), home_text, "", false, Color(0.55, 0.45, 0.85))
	if land_text != "":
		_button(_land_rect(), land_text, "", false, Color(0.35, 0.7, 0.4))


func _button(r: Rect2, big: String, small: String, down: bool, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.15) if down else Color(col, 0.9)
	sb.set_corner_radius_all(24)
	sb.shadow_color = Color(0.1, 0.05, 0.2, 0.25)
	sb.shadow_size = 2 if down else 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)
	var fs := 46 if small != "" else 28
	var tw := _font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := r.position.y + r.size.y * (0.58 if small != "" else 0.62)
	draw_string(_font, Vector2(r.position.x + (r.size.x - tw) / 2.0, y), big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if small != "":
		var sw := _font.get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(_font, Vector2(r.position.x + (r.size.x - sw) / 2.0, r.position.y + r.size.y - 16), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
